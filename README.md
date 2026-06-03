# MEV Exposure Reporter

> Quantify how much a wallet has lost to **sandwich attacks**,
> **frontruns**, and **backruns** on any EVM chain.

[![python](https://img.shields.io/badge/python-3.9%2B-blue)]()
[![license](https://img.shields.io/badge/license-MIT--0-green)]()
[![rpc](https://img.shields.io/badge/RPC-JSON--RPC%20%7C%20EVM-orange)]()

## What it does

Given a wallet address and an EVM JSON-RPC URL, this tool:

1. Walks the wallet's recent transactions.
2. Identifies every swap (Uniswap V2 / V3, Sushi, PancakeSwap, and any
   router registered in `references/detection-rules.md`).
3. Looks **inside the same block** for sandwich, frontrun, and backrun
   patterns around each victim swap.
4. Produces a human-readable report with:
   - Total estimated USD loss.
   - A 0–100 **MEV exposure score**.
   - Top attacker EOAs.
   - Per-incident detail (block, tx hash, attacker, confidence).

It works on any EVM chain — Ethereum, Pharos mainnet (with atlantic-testnet
supported as well), Base, Arbitrum, etc. — provided you have a JSON-RPC
endpoint.

## Specifications

| Item              | Value                                        |
|-------------------|----------------------------------------------|
| **Network**       | Pharos mainnet (primary); atlantic-testnet and any EVM chain also supported |
| **Framework**     | Plain Python 3.9+; no web3 framework dependency |
| **RPC protocol**  | JSON-RPC (`eth_*` methods)                   |
| **License**       | MIT-0 (free to use, modify, redistribute)    |
| **Dependencies**  | `requests` (see `requirements.txt`)          |
| **External tools**| Optional: `cast` / `forge` (Foundry) for native balance + tx decoding fallback |
| **Inputs**        | Wallet address, RPC URL, optional block range |
| **Outputs**       | Text, JSON, Markdown, or HTML report         |

## Quick start

```bash
# Clone and install
git clone https://github.com/aminatadegoke58/MEVREP.git
cd MEVREP
pip install -r requirements.txt

# Scan a wallet on Pharos mainnet
python src/detect_mev.py \
  --wallet 0xYourWallet \
  --rpc-url https://mainnet.pharosnetwork.xyz \
  --block-count 2000
```

To target a different chain, just swap the `--rpc-url`:

```bash
# Pharos atlantic-testnet
python src/detect_mev.py \
  --wallet 0xYourWallet \
  --rpc-url https://atlantic-rpc.pharosnetwork.xyz \
  --block-count 2000

# Ethereum mainnet
python src/detect_mev.py \
  --wallet 0xYourWallet \
  --rpc-url https://eth.llamarpc.com \
  --block-count 2000
```

For JSON output (pipe into the report formatter):

```bash
python src/detect_mev.py \
  --wallet 0xYourWallet \
  --rpc-url https://mainnet.pharosnetwork.xyz \
  --format json \
  | python src/report.py --format markdown --out mev-report.md
```

## Use with an AI agent

The skill spec at `SKILL.md` is the entry point the agent reads. The
agent will:

1. Read `SKILL.md` and `references/detection-rules.md` to learn the
   available capabilities.
2. Use the RPC URL the user provides (or fall back to a known EVM RPC).
3. Invoke `src/detect_mev.py` with the user's wallet.
4. Format the output with `src/report.py` and present it in the chat.

A typical agent prompt that triggers this skill:

> "How much have I lost to MEV over the last 2000 blocks? My wallet is
> `0xYourWallet`."

## Repository layout

```
MEVREP/
├── SKILL.md                       # Agent-facing skill spec
├── README.md                      # This file
├── LICENSE                        # MIT-0
├── requirements.txt
├── src/
│   ├── detect_mev.py              # Core detection engine
│   ├── report.py                  # Text / Markdown / HTML formatter
│   └── rpc.py                     # JSON-RPC client
├── references/
│   └── detection-rules.md         # How patterns are detected
└── examples/
    └── sample-output.md           # What a real report looks like
```

## How detection works

- **Sandwich** — three txs in one block, same pool, attacker brackets
  victim. Confidence 0.85.
- **Frontrun** — non-victim tx with same `to` + same selector, lands
  *before* victim in the same block. Confidence 0.70.
- **Backrun** — same as frontrun but lands *after*. Confidence 0.60.

See `references/detection-rules.md` for the full list of function
selectors, the score formula, and how to add a new DEX.

## Roadmap

- [ ] Wire in an on-chain price oracle (Uniswap TWAP or Chainlink).
- [ ] Add archive-node support for deep historical scans.
- [ ] Expand the `KNOWN_MEV_BOTS` allowlist.
- [ ] Optional Telegram / Discord notifier for live exposure.

## Contributing

PRs welcome — especially new DEX router selectors and MEV-bot
allowlist entries.

## License

[MIT-0](https://opensource.org/licenses/MIT-0) — free to use, modify,
redistribute. No attribution required.

---

**Author:** aminatadegoke58
**Built with:** Python 3.9+ and a healthy distrust of public memepools.
