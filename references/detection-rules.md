# MEV Detection Rules

This file documents the heuristics used by `scripts/detect.sh`. It is
meant to be both human-readable and editable — adjusting the scoring
ladder is as simple as editing the table at the bottom.

## What we actually count

`scripts/detect.sh` does **not** perform transaction-level sandwich /
frontrun / backrun analysis on the EVM bytecode level. Instead, it
measures **MEV exposure surface** — i.e. how visible the wallet's swap
activity is to bots in the mempool — by counting:

1. **ERC20 Transfer events** that involve the wallet as `from` or `to`
   over the last N blocks. This is a cheap proxy for "swap-shaped
   activity" because almost every DEX interaction emits a Transfer.
2. **Unique blocks** containing those events — how many distinct
   blocks the wallet has emitted swap activity in.
3. **Unique tokens** touched — how many distinct ERC20 contracts the
   wallet has interacted with. More tokens = more pools a sandwicher
   can extract from.
4. **Outgoing tx count (nonce)** — the wallet's lifetime outgoing tx
   count, as a baseline for the recent activity ratio.

These four numbers feed the score and verdict.

## Why not full sandwich detection?

A real per-tx sandwich / frontrun / backrun detector would need to:

- Decode every transaction's calldata to identify swap method
  selectors (Uniswap V2 / V3, Sushi, PancakeSwap, etc.).
- For each victim swap, look at the surrounding txs in the same block
  for bracket / same-selector patterns.
- Compute the attacker's net token delta to confirm profit.
- Optionally price the extracted value in USD via an on-chain oracle.

That is a **deep EVM-tx-analysis engine** (10+ KB of Python in earlier
versions of this skill). The current Foundry port prioritises:

- **Cheap to run** — pure bash + `cast`, no Python, no node.
- **No install footprint** — single `git clone` and you're done.
- **Safe** — read-only, no key, no signing.
- **Deterministic** — works offline (`--demo`) so it's testable.

A future version can layer full sandwich detection on top by
post-processing the `events` field of the JSON output, or by reading
the per-block `eth_getBlockByNumber(...)` txs list and decoding each
one's `to` and `input` selector.

## Attack classes (documented for completeness)

### 1. Sandwich attack

A sandwich attack has the structure:

```
Block N
├── tx[i]   attacker A swaps X → Y on pool P   (frontrun leg)
├── tx[i+1] victim V swaps X → Y on pool P     (the meat)
└── tx[i+2] attacker A swaps Y → X on pool P   (backrun leg)
```

Conditions for a sandwich to be flagged in a full detector:

- All three transactions are in the **same block**.
- The two attacker transactions are sent by the **same EOA**.
- The attacker's two transactions **bracket** the victim's transaction
  (lower and higher `transactionIndex`).
- The attacker touched the **same pool** as the victim (cross-checked
  via `Swap` event logs).

Confidence: **0.85** (rises with the heuristic adders below).

### 2. Frontrun

A frontrun is a transaction that lands *before* the victim in the same
block, with:

- The same `to` (router) address.
- The same function selector.
- A higher effective gas price (or simply earlier in block order).

Confidence: **0.70** — high enough to surface, low enough to be
reviewed. A frontrun alone is not proof of value extraction, only of
priority displacement.

### 3. Backrun

A backrun is the mirror of a frontrun: a transaction that lands
*after* the victim in the same block, with the same router + selector,
often closing an arbitrage loop opened by the victim.

Confidence: **0.60** — the lowest, because a backrun is sometimes
benign (e.g. a follow-up portfolio rebalance).

## Function selectors we treat as "swap"

| Selector       | Function                                 | Router family    |
|----------------|------------------------------------------|------------------|
| `0x022c0d9f`   | `swap(uint256,uint256,uint256,uint256)` | UniswapV2 pair   |
| `0x38ed1739`   | `swapExactTokensForTokens`               | UniswapV2 router |
| `0x8803dbee`   | `swapTokensForExactTokens`               | UniswapV2 router |
| `0x7ff36ab5`   | `swapExactETHForTokens`                  | UniswapV2 router |
| `0x18cbafe5`   | `swapExactTokensForETH`                  | UniswapV2 router |
| `0xfb3bdb41`   | `swapETHForExactTokens`                  | UniswapV2 router |
| `0xc42079f9`   | `Swap` event topic (V3)                  | UniswapV3 pool   |
| `0x414bf389`   | `exactInputSingle`                       | UniswapV3 router |
| `0xc04b8d59`   | `exactInput`                             | UniswapV3 router |
| `0xdb3e2198`   | `exactOutputSingle`                      | UniswapV3 router |
| `0xf28c0498`   | `exactOutput`                            | UniswapV3 router |

To add a new DEX, append its swap-method selectors to this table and
(if the DEX uses a non-standard swap event topic) add the topic hash
to your downstream detector.

## Score formula

The current bash port uses a single ladder based on **total Transfer
events** matched. The full version uses a weighted count:

```
score = min(100, 5 * sandwich + 3 * frontrun + 1 * backrun)
```

The current score ladder (used by `scripts/detect.sh`):

| Total Transfer events | Score | Verdict   |
|----------------------:|------:|-----------|
| ≥ 200                 |  85   | CRITICAL  |
| 100 – 199             |  65   | HIGH      |
| 30 – 99               |  40   | MEDIUM    |
| 5 – 29                |  20   | LOW       |
| 0 – 4                 |   5   | NONE      |

Interpretation:

- **0–10:** healthy wallet, low MEV exposure
- **11–30:** some bot activity, consider tighter slippage
- **31–60:** significant exposure, recommend private mempool
- **61+:** critical, large fraction of swaps are being extracted

## Adjusting the ladder

The ladder lives near the bottom of `scripts/detect.sh`:

```bash
if   [ "$TOTAL_LOGS" -ge 200 ]; then SCORE=85; VERDICT="CRITICAL"
elif [ "$TOTAL_LOGS" -ge 100 ]; then SCORE=65; VERDICT="HIGH"
…
```

To raise the bar (e.g. you only want to be alerted on wallets with
>500 events), bump the thresholds. To make the score more sensitive,
lower them. No recompile needed — `bash scripts/detect.sh` reads the
script fresh on every invocation.

## Adding a new EVM chain

Append a new entry to `assets/networks.json`:

```json
{
  "name": "my-chain",
  "rpcUrl": "https://rpc.mychain.example",
  "chainId": 12345,
  "explorerUrl": "https://explorer.mychain.example/",
  "nativeToken": "ETH"
}
```

Then pass `--chain my-chain` (after extending the `case` statement in
`detect.sh` to accept it). The default network remains `mainnet`.

## Adding a new scoring rule

The cleanest place to add a new rule is in the scoring block of
`scripts/detect.sh`. For example, to weight **unique tokens** more
heavily:

```bash
# existing ladder above
EXTRA=0
[ "$UNIQUE_TOKENS" -ge 20 ] && EXTRA=20
[ "$UNIQUE_TOKENS" -ge 10 ] && [ "$EXTRA" -eq 0 ] && EXTRA=10
SCORE=$(( SCORE + EXTRA ))
[ "$SCORE" -gt 100 ] && SCORE=100
```

Bump the score, optionally demote the verdict if it crosses a
threshold, and re-test with `bash tests/test_detect_smoke.sh`.
