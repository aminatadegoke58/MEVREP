# Example: MEV Exposure Report

> Generated against a public test wallet on Pharos atlantic-testnet.
> See `SKILL.md` for the full command line.

```
================================================================
  MEV EXPOSURE REPORT
  Wallet: 0xA1B2C3D4E5F60718293A4B5C6D7E8F9012345678
  ChainId: 688689
================================================================

  Scanned blocks:       2000
  Victim swap txs:      47
  Total MEV incidents:  6
    - sandwich:         2
    - frontrun:         3
    - backrun:          1

  >>> MEV EXPOSURE SCORE: 20 / 100 <<<
  >>> TOTAL EST. LOSS:   $0.00      <<<

  Top attacker addresses:
    0x6b75d8af00080e383a8d4b3f3315c4f4f8b9b3a3  --  2 incident(s)
    0x0000000000007f150bd6f54c40a34d7c3d5e9f56  --  1 incident(s)

  Incidents (up to 50 shown):
  ------------------------------------------------------------
  [ sandwich]  block 12345    victim 0xabcd1234…  atk 0x6b75d8af…  conf 0.85
  [ sandwich]  block 12401    victim 0xabcd1234…  atk 0x6b75d8af…  conf 0.85
  [  frontrun] block 12388    victim 0xabcd1234…  atk 0x0000…7f15  conf 0.70
  [  frontrun] block 12412    victim 0xabcd1234…  atk 0x0000…7f15  conf 0.70
  [  frontrun] block 12477    victim 0xabcd1234…  atk 0x0000…7f15  conf 0.70
  [  backrun]  block 12500    victim 0xabcd1234…  atk 0x6b75d8af…  conf 0.60
```

## Reading the report

- **MEV Exposure Score** is a 0–100 heuristic, not a dollar value.
  Higher = more of your swaps are being extracted.
- **Total Estimated Loss** requires on-chain price quotes; the default
  is $0.00 unless you wire up an oracle in `price_native_units_to_usd()`.
- **Top attackers** are EOAs that have sandwiched you more than once.
  Add them to your blocklist / RPC-level filter if possible.
- **Confidence** reflects detection certainty. ≥0.80 is high confidence
  (sandwich is the strongest signal).

## Next steps for the user

1. Use a private mempool (Flashbots Protect, MEV Blocker) to make your
   txs invisible to sandwich bots.
2. Tighten slippage on UniswapV3 routes to 0.3%–0.5%.
3. Avoid large single-tx swaps; split into multiple smaller ones.
