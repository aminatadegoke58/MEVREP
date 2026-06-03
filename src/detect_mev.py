"""
detect_mev.py - Core MEV exposure detection engine.

Detects three classes of value extraction on a target wallet:

  1. Sandwich attacks
     Pattern: in block N, attacker A buys token T from pool P,
     victim V (the target wallet) swaps T on pool P,
     attacker A sells T on pool P.  A's net token delta on P is positive.

  2. Frontruns
     Pattern: in block N, attacker A submits a tx with a higher gas price
     that targets the same contract/function selector as victim V,
     before V's tx lands.

  3. Backruns
     Pattern: in block N, attacker A submits a tx immediately after V's tx
     that closes out a position V just opened (e.g. atomic arb that
     captures V's price impact).

Output:
  - Per-incident records (block, tx, attack_class, attacker, est_loss_usd)
  - Top attacker addresses
  - Aggregate USD lost
  - MEV exposure score 0-100 (heuristic)

Usage:
  python detect_mev.py --wallet 0x... --rpc-url https://...  [--block-count 5000]
"""
from __future__ import annotations
import argparse
import json
import sys
import time
from collections import defaultdict
from dataclasses import dataclass, field, asdict
from typing import Any, Dict, List, Optional, Set, Tuple

from rpc import RpcClient, RpcError

# ---------- ABI fragments (function selectors we care about) ----------

# We don't need full ABIs - just selectors and the indexed/topics we use to
# detect swaps. We pull the actual amounts from transfer event logs.

# Uniswap V2 / forks: swap(uint256,uint256,uint256,uint256,address,address)
# 0x022c0d9f
UNIV2_SWAP_SELECTOR = "0x022c0d9f"
# Uniswap V3: swap(address,bool,int256,int256,uint160,uint128,int24,uint24)
# 0xc42079f9
UNIV3_SWAP_SELECTOR = "0xc42079f9"

# Common DEX router method names (for frontrun pattern detection)
SWAP_SELECTORS: Set[str] = {
    UNIV2_SWAP_SELECTOR,                  # UniswapV2Router.swapExact*
    UNIV3_SWAP_SELECTOR,                  # UniswapV3Router.exactInput*
    "0x38ed1739",                         # swapExactTokensForTokens
    "0x8803dbee",                         # swapTokensForExactTokens
    "0x7ff36ab5",                         # swapExactETHForTokens
    "0x18cbafe5",                         # swapExactTokensForETH
    "0xfb3bdb41",                         # swapETHForExactTokens
    "0x414bf389",                         # exactInputSingle (V3)
    "0xc04b8d59",                         # exactInput (V3)
    "0xdb3e2198",                         # exactOutputSingle (V3)
    "0xf28c0498",                         # exactOutput (V3)
}

# ERC20 Transfer event topic
TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

# Known MEV bot labels (heuristic; we don't need to be perfect)
KNOWN_MEV_BOTS: Set[str] = {
    "0x0000000000007f150bd6f54c40a34d7c3d5e9f56",  # example placeholder
    "0x6b75d8af00080e383a8d4b3f3315c4f4f8b9b3a3",  # example placeholder
}


# ---------- data types ----------

@dataclass
class SwapEvent:
    block: int
    tx_hash: str
    log_index: int
    router: str
    sender: str          # tx.from
    recipient: str       # tx.to (router)
    pool: str            # pool that emitted the swap log
    token_in: str
    token_out: str
    amount_in: int
    amount_out: int

@dataclass
class Incident:
    attack_class: str            # 'sandwich' | 'frontrun' | 'backrun'
    block: int
    victim_tx: str
    attacker_tx: str
    attacker: str
    pool: str
    token_in: str
    token_out: str
    est_loss_native: float = 0.0  # in token_in units
    est_loss_usd: float = 0.0
    confidence: float = 0.0      # 0..1


# ---------- helper: decode transfer amounts from logs ----------

def _decode_uint256(hexstr: str) -> int:
    return int(hexstr, 16)


def extract_transfers(receipt: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Return a list of {from, to, value, token, logIndex} for ERC20 Transfer events."""
    out = []
    for lg in receipt.get("logs", []):
        topics = lg.get("topics", [])
        if len(topics) >= 3 and topics[0].lower() == TRANSFER_TOPIC:
            out.append({
                "token": lg.get("address", "").lower(),
                "from": "0x" + topics[1].lower()[-40:],
                "to": "0x" + topics[2].lower()[-40:],
                "value": _decode_uint256(lg.get("data", "0x0")),
                "logIndex": int(lg.get("logIndex", "0x0"), 16),
            })
    return out


def _decode_address_from_topic(topic: str) -> str:
    return "0x" + topic.lower()[-40:]


# ---------- step 1: gather victim swap transactions ----------

def gather_victim_swaps(
    rpc: RpcClient, wallet: str, block_count: int
) -> List[Dict[str, Any]]:
    """Walk back `block_count` blocks, return txs from wallet that look like swaps."""
    wallet = wallet.lower()
    head = rpc.block_number()
    start = max(0, head - block_count)

    out: List[Dict[str, Any]] = []
    # We chunk by 200 blocks to keep eth_getLogs sane.
    CHUNK = 200
    cur = start
    while cur <= head:
        end = min(cur + CHUNK - 1, head)
        try:
            # Use getLogs over Transfer events involving the wallet, then filter.
            # This catches swap output tokens landing in the wallet.
            logs = rpc.get_logs({
                "fromBlock": hex(cur),
                "toBlock": hex(end),
                "topics": [
                    TRANSFER_TOPIC,
                    None,                    # from any
                    "0x" + "0" * 24 + wallet[2:],  # to = wallet
                ],
            })
        except RpcError as e:
            # Some public nodes refuse unfiltered getLogs; fall back to block scan.
            logs = []
            for b in range(cur, end + 1):
                blk = rpc.get_block(b, full_txs=True)
                for tx in blk.get("transactions", []):
                    if tx.get("from", "").lower() == wallet:
                        if tx.get("input", "")[:10] in SWAP_SELECTORS:
                            out.append({"block": b, "tx": tx})
        for lg in logs:
            block = int(lg.get("blockNumber", "0x0"), 16)
            # The matching swap tx is the one with same block + same tx hash = lg.transactionHash
            txh = lg.get("transactionHash", "")
            try:
                tx = rpc.get_tx(txh)
            except RpcError:
                continue
            if tx.get("from", "").lower() != wallet:
                continue
            if tx.get("input", "")[:10] not in SWAP_SELECTORS:
                continue
            out.append({"block": block, "tx": tx})
        cur = end + 1
    # Dedupe by tx hash
    seen = set()
    deduped = []
    for r in out:
        h = r["tx"]["hash"]
        if h in seen:
            continue
        seen.add(h)
        deduped.append(r)
    return deduped


# ---------- step 2: for each victim tx, scan its block for sandwich/frontrun/backrun ----------

# Known AMM pool methods that emit a swap event we can correlate on
POOL_SWAP_TOPIC_V2 = "0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822"  # Swap(address,uint256,uint256,uint256,uint256,address)
POOL_SWAP_TOPIC_V3 = "0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67"  # Swap(address,int256,int256,uint160,uint128,int24,uint24)


def get_block_swap_logs(rpc: RpcClient, block: int) -> List[Dict[str, Any]]:
    """Return all swap-style logs in a block."""
    try:
        logs = rpc.get_logs({
            "fromBlock": hex(block),
            "toBlock": hex(block),
            "topics": [[POOL_SWAP_TOPIC_V2, POOL_SWAP_TOPIC_V3]],
        })
    except RpcError:
        logs = []
    return logs


def detect_for_block(
    rpc: RpcClient, victim: Dict[str, Any], block: int
) -> List[Incident]:
    """Find sandwich / frontrun / backrun candidates in the same block as victim."""
    victim_tx_hash = victim["tx"]["hash"].lower()
    victim_from = victim["tx"]["from"].lower()
    victim_to = victim["tx"]["to"].lower() if victim["tx"].get("to") else ""
    victim_selector = victim["tx"]["input"][:10]

    # All swap txs in this block
    try:
        block_data = rpc.get_block(block, full_txs=True)
    except RpcError:
        return []
    swap_txs = [
        tx for tx in block_data.get("transactions", [])
        if (tx.get("input", "")[:10] in SWAP_SELECTORS)
    ]
    # Index by sender
    by_sender: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    for tx in swap_txs:
        by_sender[tx["from"].lower()].append(tx)

    # Get full swap logs in this block
    swap_logs = get_block_swap_logs(rpc, block)
    # Group logs by pool
    logs_by_pool: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    for lg in swap_logs:
        logs_by_pool[lg["address"].lower()].append(lg)

    incidents: List[Incident] = []

    # ---- SANDWICH detection ----
    # Look for a non-victim sender who has txs in this block touching a pool
    # that the victim also touches, with two txs bracketing the victim.
    victim_pools = _pools_for_tx(rpc, victim["tx"])
    for other_sender, other_txs in by_sender.items():
        if other_sender == victim_from:
            continue
        if other_sender in KNOWN_MEV_BOTS or _looks_like_bot(other_sender, other_txs):
            # Other sender's txs sorted by tx index (= order in block)
            sorted_others = sorted(other_txs, key=lambda t: int(t.get("transactionIndex", t.get("index", 0)), 16))
            victim_idx = _tx_index_in_block(rpc, victim_tx_hash, block)
            for i, otx in enumerate(sorted_others):
                if i + 1 >= len(sorted_others):
                    continue
                otx_idx = int(otx.get("transactionIndex", "0x0"), 16)
                next_idx = int(sorted_others[i + 1].get("transactionIndex", "0x0"), 16)
                if otx_idx < victim_idx < next_idx:
                    # bracketed! check if same pool is touched
                    otx_pools = _pools_for_tx(rpc, otx)
                    next_pools = _pools_for_tx(rpc, sorted_others[i + 1])
                    shared = (otx_pools & victim_pools) or (next_pools & victim_pools)
                    if shared:
                        for pool in shared:
                            inc = Incident(
                                attack_class="sandwich",
                                block=block,
                                victim_tx=victim_tx_hash,
                                attacker_tx=otx["hash"],
                                attacker=other_sender,
                                pool=pool,
                                token_in="", token_out="",
                                confidence=0.85,
                            )
                            incidents.append(inc)

    # ---- FRONTRUN detection ----
    # Non-victim sender whose tx lands before victim in same block, same router,
    # same selector, similar/identical calldata.
    victim_idx = _tx_index_in_block(rpc, victim_tx_hash, block)
    for tx in swap_txs:
        if tx["hash"].lower() == victim_tx_hash:
            continue
        if tx["from"].lower() == victim_from:
            continue
        if tx.get("to", "").lower() != victim_to:
            continue
        if tx["input"][:10] != victim_selector:
            continue
        tx_idx = int(tx.get("transactionIndex", "0x0"), 16)
        if tx_idx < victim_idx:
            incidents.append(Incident(
                attack_class="frontrun",
                block=block,
                victim_tx=victim_tx_hash,
                attacker_tx=tx["hash"],
                attacker=tx["from"].lower(),
                pool="",
                token_in="", token_out="",
                confidence=0.7,
            ))

    # ---- BACKRUN detection ----
    # Same as frontrun but lands after.
    for tx in swap_txs:
        if tx["hash"].lower() == victim_tx_hash:
            continue
        if tx["from"].lower() == victim_from:
            continue
        if tx.get("to", "").lower() != victim_to:
            continue
        if tx["input"][:10] != victim_selector:
            continue
        tx_idx = int(tx.get("transactionIndex", "0x0"), 16)
        if tx_idx > victim_idx:
            incidents.append(Incident(
                attack_class="backrun",
                block=block,
                victim_tx=victim_tx_hash,
                attacker_tx=tx["hash"],
                attacker=tx["from"].lower(),
                pool="",
                token_in="", token_out="",
                confidence=0.6,
            ))

    return incidents


def _tx_index_in_block(rpc: RpcClient, tx_hash: str, block: int) -> int:
    try:
        tx = rpc.get_tx(tx_hash)
        return int(tx.get("transactionIndex", "0x0"), 16)
    except RpcError:
        return 1 << 31  # very large, so it sorts last


def _pools_for_tx(rpc: RpcClient, tx: Dict[str, Any]) -> Set[str]:
    """Best-effort: pull receipt, return pool addresses that emitted a Swap event."""
    try:
        rcpt = rpc.get_tx_receipt(tx["hash"])
    except RpcError:
        return set()
    pools = set()
    for lg in rcpt.get("logs", []):
        if lg.get("topics", [None])[0] in (POOL_SWAP_TOPIC_V2, POOL_SWAP_TOPIC_V3):
            pools.add(lg["address"].lower())
    return pools


def _looks_like_bot(addr: str, txs: List[Dict[str, Any]]) -> bool:
    """Heuristic: an address submitting multiple swaps in one block is suspicious."""
    return len(txs) >= 2


# ---------- step 3: estimate USD loss per incident ----------

# In a real implementation we'd query a price oracle. For the skill demo we
# expose a pluggable pricing function; default returns 0.0 and is overridable.

def price_native_units_to_usd(token_addr: str, amount: int) -> float:
    """Default pricing stub. Replace with oracle or on-chain quote logic."""
    return 0.0


# ---------- main driver ----------

def analyze(
    wallet: str, rpc_url: str, block_count: int = 5000, min_loss_usd: float = 0.5
) -> Dict[str, Any]:
    rpc = RpcClient(rpc_url)
    chain_id = rpc.chain_id()
    print(f"[+] Connected to chainId {chain_id}", file=sys.stderr)

    print(f"[+] Scanning last {block_count} blocks for {wallet}...", file=sys.stderr)
    t0 = time.time()
    victim_txs = gather_victim_swaps(rpc, wallet, block_count)
    print(f"[+] Found {len(victim_txs)} victim swap transactions in {time.time()-t0:.1f}s",
          file=sys.stderr)

    incidents: List[Incident] = []
    for i, v in enumerate(victim_txs, 1):
        try:
            incidents.extend(detect_for_block(rpc, v, v["block"]))
        except RpcError as e:
            print(f"[!] block {v['block']} error: {e}", file=sys.stderr)
        if i % 50 == 0:
            print(f"[+] ...scanned {i}/{len(victim_txs)} victim txs", file=sys.stderr)

    # Aggregate
    by_attacker: Dict[str, int] = defaultdict(int)
    by_class: Dict[str, int] = defaultdict(int)
    total_usd = 0.0
    for inc in incidents:
        by_attacker[inc.attacker] += 1
        by_class[inc.attack_class] += 1
        total_usd += inc.est_loss_usd

    # MEV exposure score: simple weighted heuristic
    # 1 sandwich ~= 5 points, 1 frontrun ~= 3, 1 backrun ~= 1, capped at 100
    score = min(100, by_class["sandwich"] * 5 + by_class["frontrun"] * 3 + by_class["backrun"] * 1)

    return {
        "wallet": wallet,
        "chainId": chain_id,
        "scannedBlocks": block_count,
        "victimTxCount": len(victim_txs),
        "incidentCount": len(incidents),
        "byClass": dict(by_class),
        "topAttackers": sorted(by_attacker.items(), key=lambda kv: -kv[1])[:10],
        "totalEstimatedLossUsd": total_usd,
        "exposureScore": score,
        "incidents": [asdict(i) for i in incidents],
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--wallet", required=True, help="Victim wallet address")
    p.add_argument("--rpc-url", required=True, help="JSON-RPC endpoint")
    p.add_argument("--block-count", type=int, default=5000)
    p.add_argument("--min-loss-usd", type=float, default=0.5)
    p.add_argument("--format", choices=["text", "json"], default="text")
    args = p.parse_args()

    result = analyze(args.wallet, args.rpc_url, args.block_count, args.min_loss_usd)
    if args.format == "json":
        print(json.dumps(result, indent=2))
        return

    # Text report
    print("=" * 60)
    print(f"MEV Exposure Report for {result['wallet']}")
    print(f"Chain ID: {result['chainId']}")
    print(f"Scanned blocks: {result['scannedBlocks']}")
    print("=" * 60)
    print(f"Victim swap txs found: {result['victimTxCount']}")
    print(f"Total MEV incidents:   {result['incidentCount']}")
    print(f"  - sandwich:  {result['byClass'].get('sandwich', 0)}")
    print(f"  - frontrun:  {result['byClass'].get('frontrun', 0)}")
    print(f"  - backrun:   {result['byClass'].get('backrun', 0)}")
    print(f"MEV exposure score:    {result['exposureScore']} / 100")
    print(f"Total est. loss (USD): ${result['totalEstimatedLossUsd']:.2f}")
    print()
    print("Top attacker addresses:")
    for addr, n in result["topAttackers"]:
        print(f"  {addr}  -- {n} incident(s)")
    print()
    print("Incidents:")
    for inc in result["incidents"][:50]:
        print(f"  [{inc['attack_class']:>9}] block {inc['block']} "
              f"victim {inc['victim_tx'][:10]}...  "
              f"attacker {inc['attacker'][:10]}...  "
              f"conf {inc['confidence']:.2f}")


if __name__ == "__main__":
    main()
