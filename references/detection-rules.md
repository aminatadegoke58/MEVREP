# MEV Detection Rules

This file documents the heuristics used by `src/detect_mev.py`. It is meant
to be both human-readable and editable — adding a new DEX router is as
simple as appending its function selector to the list below.

## Attack classes

### 1. Sandwich attack

A sandwich attack has the structure:

```
Block N
├── tx[i]   attacker A swaps X → Y on pool P   (frontrun leg)
├── tx[i+1] victim V swaps X → Y on pool P     (the meat)
└── tx[i+2] attacker A swaps Y → X on pool P   (backrun leg)
```

Conditions for a sandwich to be flagged:

- All three transactions are in the **same block**.
- The two attacker transactions are sent by the **same EOA**.
- The attacker's two transactions **bracket** the victim's transaction
  (lower and higher `transactionIndex`).
- The attacker touched the **same pool** as the victim (cross-checked via
  `Swap` event logs).

Confidence is set to **0.85** by default and rises with:

- The attacker also appeared in past blocks against this wallet (+0.05).
- The two attacker txs land within ±5 positions of the victim (+0.05).
- The attacker's net token delta is positive (verifiable post-hoc via
  `eth_getBalance` + ERC20 balance diff) (+0.05).

### 2. Frontrun

A frontrun is a transaction that lands *before* the victim in the same
block, with:

- The same `to` (router) address.
- The same function selector.
- A higher effective gas price (or simply earlier in block order).

Confidence: **0.70** — high enough to surface, low enough to be reviewed.
A frontrun alone is not proof of value extraction, only of priority
displacement.

### 3. Backrun

A backrun is the mirror of a frontrun: a transaction that lands *after*
the victim in the same block, with the same router + selector, often
closing an arbitrage loop opened by the victim.

Confidence: **0.60** — the lowest, because a backrun is sometimes
benign (e.g. a follow-up portfolio rebalance).

## Function selectors we treat as "swap"

| Selector       | Function                                 | Router family |
|----------------|------------------------------------------|---------------|
| `0x022c0d9f`   | `swap(uint256,uint256,uint256,uint256)` | UniswapV2 pair |
| `0x38ed1739`   | `swapExactTokensForTokens`               | UniswapV2 router |
| `0x8803dbee`   | `swapTokensForExactTokens`               | UniswapV2 router |
| `0x7ff36ab5`   | `swapExactETHForTokens`                  | UniswapV2 router |
| `0x18cbafe5`   | `swapExactTokensForETH`                  | UniswapV2 router |
| `0xfb3bdb41`   | `swapETHForExactTokens`                  | UniswapV2 router |
| `0xc42079f9`   | `Swap` event topic (V3)                   | UniswapV3 pool |
| `0x414bf389`   | `exactInputSingle`                       | UniswapV3 router |
| `0xc04b8d59`   | `exactInput`                             | UniswapV3 router |
| `0xdb3e2198`   | `exactOutputSingle`                      | UniswapV3 router |
| `0xf28c0498`   | `exactOutput`                            | UniswapV3 router |

To add a new DEX, append the swap-method selectors to `SWAP_SELECTORS`
in `src/detect_mev.py` and (if the DEX uses a non-standard swap event
topic) add the topic hash to `POOL_SWAP_TOPIC_V2` / `POOL_SWAP_TOPIC_V3`
in the same file.

## Known MEV bot EOAs

We maintain a small allowlist of public MEV-bot labels (see
`KNOWN_MEV_BOTS` in `detect_mev.py`). When an attacker EOA matches a
known bot, confidence for any incident involving that EOA is bumped to
**0.95**.

> Pull requests expanding this list are welcome.

## Score formula

The "MEV exposure score" 0–100 is a simple weighted count, designed to
be intuitive rather than statistically calibrated:

```
score = min(100, 5 * sandwich + 3 * frontrun + 1 * backrun)
```

Interpretation:

- **0–10:** healthy wallet, low MEV exposure
- **11–30:** some bot activity, consider tighter slippage
- **31–60:** significant exposure, recommend private mempool
- **61+:** critical, large fraction of swaps are being extracted
