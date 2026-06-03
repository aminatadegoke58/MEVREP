---
name: mev-exposure-reporter
description: >
  REQUIRED for any task that requires quantifying a wallet's losses to
  Maximal Extractable Value (MEV) on an EVM chain. Invoke when the user asks
  to "analyze MEV exposure", "show MEV losses", "check sandwich attacks",
  "frontrun report", "how much did I lose to MEV", "slippage analysis",
  or wants a per-token / per-protocol breakdown of value extracted from
  their wallet's swap transactions. Use the bundled `src/detect_mev.py`
  detector to scan a wallet's transaction history via JSON-RPC (works
  with any EVM RPC URL, including Pharos atlantic-testnet / mainnet
  endpoints defined in `pharos-skill-engine/assets/networks.json`).
  Do not attempt MEV exposure analysis without reading this skill.
version: 0.1.0
requires:
  - python >= 3.9
  - requests
  - anyBins:
      - cast   # optional, used for native balance / tx decoding fallback
      - jq
---

# MEV Exposure Reporter

Quantify how much a wallet lost to **sandwich attacks** and **frontrunning**
on any EVM-compatible chain (Ethereum, Pharos, Base, Arbitrum, etc.).

The skill ships a Python detection engine that:

1. Pulls the wallet's recent transactions via JSON-RPC.
2. Decodes `swap*` events from major AMMs (Uniswap V2/V3, Sushi, PancakeSwap,
   and any router whose selectors are in `references/detection-rules.md`).
3. Detects three classes of MEV extraction:
   - **Sandwich** — victim tx sits between two attacker txs in the same
     block, all touching the same pool, attacker makes a guaranteed profit
     on the back-run.
   - **Frontrun** — attacker tx with the same `to`/function and a higher gas
     price in the same block as victim.
   - **Backrun** — attacker tx that follows victim in the same block and
     profits from the victim's price impact.
4. Estimates USD value lost using the token amounts and an on-chain price
   reference (USDC/USDT pair or a router quote).

## When to use

- The user asks "how much have I lost to MEV?"
- The user asks to audit a wallet for sandwich attacks.
- The user wants a per-victim-tx breakdown of value extraction.
- The user wants a single "MEV exposure score" for a wallet.

## When NOT to use

- Single-tx debugging (use `pharos-skill-engine` query.md instead).
- Approval/permission auditing (use a dedicated approval tool).
- General portfolio aggregation (use `pharos-skill-engine`).

## Inputs

| Input          | Required | Description                                   |
|----------------|----------|-----------------------------------------------|
| `wallet`       | yes      | 0x address to analyze                         |
| `rpc_url`      | yes      | JSON-RPC endpoint (Pharos atlantic-testnet, mainnet, or any EVM) |
| `block_count`  | no       | How many recent blocks to scan (default 5000) |
| `min_loss_usd` | no       | Ignore dust extraction below this USD (default 0.50) |
| `format`       | no       | `text` (default) or `json`                    |

## Outputs

A structured report with:

- Total USD lost to MEV.
- Number of victim transactions.
- Per-incident detail: tx hash, block, attacker address (if known),
  estimated loss in USD, attack class.
- A list of attacker EOAs (top offenders).
- A wallet "MEV exposure score" 0-100.

## Quick start

```bash
# 1. Install
pip install -r requirements.txt

# 2. Run a scan on Pharos atlantic testnet
python src/detect_mev.py \
  --wallet 0xYourWalletHere \
  --rpc-url "$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .rpcUrl' \
        /path/to/pharos-skill-engine/assets/networks.json)" \
  --block-count 2000

# 3. Get a JSON report
python src/detect_mev.py \
  --wallet 0xYourWalletHere \
  --rpc-url https://atlantic-rpc.pharosnetwork.xyz \
  --format json > report.json
```

## Agent invocation pattern

When the user asks for an MEV report, the Agent should:

1. Resolve the RPC URL from `pharos-skill-engine/assets/networks.json`
   (unless the user supplies one).
2. Ask the user for the wallet address (never invent one).
3. Run `src/detect_mev.py` with the parameters above.
4. Pipe the output through `src/report.py` to produce a human-readable
   summary.
5. Present the report inline, with a top-level "Total MEV loss" headline
   number and a sortable table of incidents.

## Error handling

| Error                              | Cause                          | Action |
|------------------------------------|--------------------------------|--------|
| `rpc unreachable`                  | Bad / dead RPC URL             | Ask user for a working RPC or use Pharos fallback |
| `wallet has no txs in range`       | Wallet inactive or new         | Increase `--block-count` or confirm address |
| `unknown router selector`          | DEX not yet supported          | Add selector to `references/detection-rules.md` |
| `insufficient price reference`     | Token has no USDC pair         | Note the unknown token, skip USD estimate |

## Limitations

- MEV loss is a *lower bound* — sophisticated multi-block strategies may
  be missed.
- USD value depends on price reference availability per token.
- Detection works against public RPC nodes; for very deep history use an
  archive node or an indexer like The Graph / Covalent.
