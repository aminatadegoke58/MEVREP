# Example: MEV Exposure Report

Below are three real examples of the three output formats, all
produced by `scripts/detect.sh` against a known active Pharos mainnet
address.

## 1. Text output (default)

```bash
$ bash scripts/detect.sh --wallet 0x67992af9a87f2d6a3062c333d8a06abbe3929438 --blocks 100
```

```
========================================================================
  MEV EXPOSURE REPORT
  Wallet:  0x67992af9a87f2d6a3062c333d8a06abbe3929438
  Chain:   mainnet (chainId 1672)
========================================================================

  Wallet nonce:     10183  (outgoing tx count)
  Wallet balance:   49701210000000000 wei  (~PROS)
  Head block:       9898286
  Scanning blocks:  [9898186, 9898286]  (last 100)

  Scanned blocks:       100
  Outgoing tx count:    10183
  Transfer events:      0
  Unique blocks:        0
  Unique tokens:        0
  Estimated incidents:  0
  MEV exposure score:   5/100

  >>> VERDICT: NONE  <<<

  Explorer: https://www.pharosscan.xyz/address/0x67992af9a87f2d6a3062c333d8a06abbe3929438
```

## 2. JSON output

```bash
$ bash scripts/detect.sh --wallet 0x67992af9a87f2d6a3062c333d8a06abbe3929438 --blocks 5000 --format json
```

```json
{
  "wallet": "0x67992af9a87f2d6a3062c333d8a06abbe3929438",
  "chain": "mainnet",
  "chainId": 1672,
  "explorer": "https://www.pharosscan.xyz/address/0x67992af9a87f2d6a3062c333d8a06abbe3929438",
  "victimTxCount": 10183,
  "scannedBlocks": 5000,
  "startBlock": 9893290,
  "endBlock": 9898290,
  "swapEvents": 0,
  "uniqueBlocks": 0,
  "uniqueTokens": 0,
  "incidentCount": 0,
  "mevScore": 5,
  "verdict": "NONE",
  "generatedAt": "2026-06-11T17:20:47Z"
}
```

## 3. Markdown output

```bash
$ bash scripts/detect.sh --wallet 0x67992af9a87f2d6a3062c333d8a06abbe3929438 --format markdown > mev-report.md
```

```markdown
# MEV Exposure Report

| Field | Value |
|---|---|
| Wallet | `0x67992af9a87f2d6a3062c333d8a06abbe3929438` |
| Chain | mainnet (chainId 1672) |
| Generated | 2026-06-11T17:20:47Z |
| Explorer | https://www.pharosscan.xyz/address/0x67992af9a87f2d6a3062c333d8a06abbe3929438 |

## Verdict: **NONE**

## Score: **5 / 100**

| Metric | Value |
|---|---|
| Scanned blocks | 5000 |
| Outgoing tx count (nonce) | 10183 |
| Transfer events matched | 0 |
| Unique blocks touched | 0 |
| Unique tokens touched | 0 |
| Estimated incidents | 0 |

## Score interpretation

- **0–10** — NONE: clean wallet, low MEV exposure
- **11–30** — LOW: a few bot interactions; tighten slippage
- **31–60** — MEDIUM: meaningful exposure; consider private mempool
- **61+** — HIGH / CRITICAL: large fraction of swaps extracted

## Next steps

1. Use a private mempool (Flashbots Protect, MEV Blocker) to hide txs from sandwichers.
2. Tighten slippage on UniswapV3 routes to 0.3%–0.5%.
3. Avoid large single-tx swaps; split into multiple smaller ones.
4. Inspect top attacker EOAs and blocklist them at the RPC level.
```

## 4. Demo output (offline, no RPC)

```bash
$ bash scripts/detect.sh --demo
```

```
========================================================================
  MEV EXPOSURE REPORT
  Wallet:  0x67992af9a87f2d6a3062c333d8a06abbe3929438
  Chain:   mainnet (chainId 1672)
========================================================================

  (DEMO mode — synthetic numbers, no RPC call made)
  Wallet nonce:     47  (outgoing tx count)
  Wallet balance:   1000000000000000000 wei  (~PROS)

  Scanned blocks:       5000
  Outgoing tx count:    47
  Transfer events:      12
  Unique blocks:        9
  Unique tokens:        3
  Estimated incidents:  4
  MEV exposure score:   20/100

  >>> VERDICT: LOW  <<<

  Explorer: https://www.pharosscan.xyz/address/0x67992af9a87f2d6a3062c333d8a06abbe3929438
```

## Reading the report

- **Verdict** is the headline. NONE / LOW / MEDIUM / HIGH / CRITICAL.
- **MEV Exposure Score** is a 0–100 heuristic, not a dollar value.
  Higher = more of your swap surface is visible to extractors.
- **Transfer events matched** is the count of ERC20 Transfer logs
  whose `from` (or `to`) is the wallet. This is a proxy for
  swap-shaped activity in the scanned range.
- **Unique tokens** touched tells you how many distinct ERC20
  contracts the wallet interacted with — a larger number means more
  pools are visible to sandwichers.
- **Explorer** is a direct link to the wallet on the Pharos block
  explorer so a human can dig into individual txs.

## Next steps for a human user

1. Use a private mempool (Flashbots Protect, MEV Blocker) to make your
   txs invisible to sandwich bots.
2. Tighten slippage on UniswapV3 routes to 0.3%–0.5%.
3. Avoid large single-tx swaps; split into multiple smaller ones.
4. Inspect top attacker EOAs and add them to a local RPC-level
   blocklist.
