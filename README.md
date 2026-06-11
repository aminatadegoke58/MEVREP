# MEV Exposure Reporter

> Quantify how much a wallet has lost to **sandwich attacks**,
> **frontruns**, and **backruns** on EVM chains.

[![python](https://img.shields.io/badge/python-3.9%2B-blue)]()
[![license](https://img.shields.io/badge/license-MIT--0-green)]()
[![rpc](https://img.shields.io/badge/RPC-JSON--RPC%20%7C%20EVM-orange)]()

## Overview

Given a wallet address and an EVM JSON-RPC URL, this tool walks the
wallet's recent swap transactions, looks inside the same blocks for
sandwich / frontrun / backrun patterns, and produces a structured
report with a 0–100 **MEV exposure score** and per-incident detail.

It works against any EVM chain but ships with first-class support for
the Pharos networks (see [Supported networks](#supported-networks)).

## Features

- **Sandwich attack detection** — three txs in one block, same pool,
  attacker brackets the victim (confidence 0.85).
- **Frontrun detection** — non-victim tx with the same `to` + same
  function selector that lands before the victim in the same block
  (confidence 0.70).
- **Backrun detection** — same as frontrun but lands after the victim
  (confidence 0.60).
- **MEV exposure score** — a 0–100 heuristic that weights sandwiches
  most heavily, designed to be intuitive rather than statistically
  calibrated.
- **Top attacker list** — ranks EOAs that have extracted from this
  wallet the most, suitable for blocklist / RPC-level filtering.
- **Multi-format output** — text (default), JSON, Markdown, or HTML
  via the `report.py` formatter.
- **No web3 framework dependency** — uses plain `eth_*` JSON-RPC, so
  it runs anywhere Python 3.9+ runs.
- **Pluggable** — add a new DEX by appending its function selector
  to `references/detection-rules.md`.

## Supported networks

The tool runs against any EVM-compatible JSON-RPC endpoint. The
following networks are explicitly supported out of the box and used
in the examples below.

| Network                | Chain ID | RPC URL                              | Native token | Explorer                          |
|------------------------|----------|--------------------------------------|--------------|-----------------------------------|
| Pharos Pacific Mainnet | `1672`   | `https://rpc.pharos.xyz`             | PROS         | https://www.pharosscan.xyz/       |
| Pharos Atlantic Testnet| `688689` | `https://atlantic.dplabs-internal.com` | PHRS         | https://atlantic.pharosscan.xyz/  |

You can target either by passing the matching `--rpc-url` flag
(see [Usage](#usage)).

## Framework

- **Language:** Python 3.9+
- **RPC protocol:** JSON-RPC (`eth_blockNumber`, `eth_getBlockByNumber`,
  `eth_getTransactionByHash`, `eth_getTransactionReceipt`,
  `eth_getLogs`, `eth_chainId`)
- **External CLIs (optional):** `cast` / `forge` from
  [Foundry](https://book.getfoundry.xyz/) for native balance fallback
  and tx decoding; `jq` for ergonomic RPC URL extraction in shell
  pipelines.
- **No web3 framework required** — the engine speaks JSON-RPC directly
  over `requests` so it has the smallest possible install footprint
  and the fewest moving parts.

## Dependencies

Runtime (Python):

- `requests>=2.31` — HTTP client used by `src/rpc.py`.

External (only if you want the optional CLIs):

- `cast` / `forge` — Foundry CLI (https://book.getfoundry.xyz/getting-started/installation).
- `jq` — command-line JSON processor, used in README shell snippets.

Everything is pinned in `requirements.txt` at the repo root.

## Install

### 1. Install Python 3.9+ and pip

```bash
# macOS
brew install python@3.11
# Debian/Ubuntu/Termux
apt install -y python3 python3-pip
```

Verify with `python3 --version`.

### 2. (Optional) Install Foundry if you want cast/forge fallback

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Verify with `cast --version`. Foundry is OPTIONAL for this skill — the bash CLI in `scripts/cli.sh` works without it.

### 3. Get the skill

```bash
git clone https://github.com/arikky1122/MEVREP
cd MEVREP
pip install -r requirements.txt
chmod +x scripts/*.sh
```

That's it. No build step, no native compilation. The skill is a Python 3.9+ module wrapped by a bash CLI for easy invocation.
## Quick test (try it in 30 seconds)

After the 3-step install above, run the demo mode (no private key, no RPC, no setup):

```bash
bash scripts/detect.sh --demo
```

You should see a printed report. The demo uses synthetic data, so it works offline.

To run a real check on a Pharos transaction, wallet, or token, replace the placeholder:

```bash
bash scripts/detect.sh --wallet 0xYOUR_WALLET
```

## Use in an AI agent (Claude Code / Codex / OpenClaw / Pharos Agent Center)

The skill ships with a `SKILL.md` that AI agents auto-load. Once installed in your agent, just ask in natural language — the agent will read `SKILL.md` and run the bash script for you.

```text
"Has wallet 0xabc... lost any funds to sandwich attacks on Pharos?"
```

The agent will run `bash scripts/detect.sh --demo` (or the live command with the address you gave) and read the result back to you.

### Install in your agent

**Option A — Pharos Agent Center** (one-line install):

```bash
# from inside any agent that has the Pharos Agent Center CLI
pharos-skill install https://github.com/arikky1122/MEVREP
```

**Option B — OpenClaw / Claude Code / Codex** (one-line via npm):

```bash
npx skills add https://github.com/arikky1122/MEVREP
```

**Option C — Manual install** (drop into your agent's skills directory):

```bash
# Clone the skill
git clone https://github.com/arikky1122/MEVREP
cd MEVREP

# Claude Code: copy to ~/.claude/skills/
mkdir -p ~/.claude/skills/MEVREP
cp -r . ~/.claude/skills/MEVREP/

# Codex: copy to ~/.codex/skills/
mkdir -p ~/.codex/skills/MEVREP
cp -r . ~/.codex/skills/MEVREP/

# OpenClaw: copy to ~/.openclaw/skills/
mkdir -p ~/.openclaw/skills/MEVREP
cp -r . ~/.openclaw/skills/MEVREP/

# Then restart the agent — the skill will be auto-loaded.
```
## Usage

### Scan a Pharos mainnet wallet

```bash
python src/detect_mev.py \
  --wallet 0xYourWallet \
  --rpc-url https://rpc.pharos.xyz \
  --block-count 2000
```

### Scan a Pharos Atlantic testnet wallet

```bash
python src/detect_mev.py \
  --wallet 0xYourWallet \
  --rpc-url https://atlantic.dplabs-internal.com \
  --block-count 2000
```

### Output as JSON, then format as Markdown

```bash
python src/detect_mev.py \
  --wallet 0xYourWallet \
  --rpc-url https://rpc.pharos.xyz \
  --format json \
  | python src/report.py --format markdown --out mev-report.md
```

### Output as HTML

```bash
python src/detect_mev.py \
  --wallet 0xYourWallet \
  --rpc-url https://rpc.pharos.xyz \
  --format json \
  | python src/report.py --format html --out mev-report.html
```

### Command-line flags

| Flag             | Required | Default | Description                                   |
|------------------|----------|---------|-----------------------------------------------|
| `--wallet`       | yes      | —       | 0x address to analyze                         |
| `--rpc-url`      | yes      | —       | JSON-RPC endpoint                             |
| `--block-count`  | no       | 5000    | How many recent blocks to scan                |
| `--min-loss-usd` | no       | 0.5     | Ignore dust extraction below this USD         |
| `--format`       | no       | text    | `text` (default) or `json`                    |

### Sample output

See `examples/sample-output.md` for what a real report looks like.

## AI Agent Integration

This repository ships a `SKILL.md` at the root that any agent
runtime can load to discover the skill. The flow is:

1. The agent reads `SKILL.md` to learn the capability and required
   arguments (`--wallet`, `--rpc-url`).
2. The agent collects the wallet address and target network from
   the user (it never invents either).
3. The agent runs `python src/detect_mev.py --wallet <addr>
   --rpc-url <rpc>` and captures stdout.
4. If the user wants a formatted report, the agent pipes the JSON
   output through `python src/report.py --format <fmt>`.
5. The agent presents the report inline, with the headline
   "MEV exposure score" and total estimated loss surfaced first.

A typical prompt that triggers the skill:

> "How much have I lost to MEV on Pharos mainnet over the last 2000
> blocks? My wallet is `0xYourWallet`."

A typical reply:

> **MEV Exposure Score: 20 / 100** — **Total estimated loss: $0.00**
>
> | Class     | Count |
> |-----------|-------|
> | Sandwich  | 2     |
> | Frontrun  | 3     |
> | Backrun   | 1     |
>
> Top attacker: `0x6b75…b3a3` (2 incidents). See `mev-report.md` for
> per-incident breakdown.

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


## Tests

```bash
pytest tests/ -v  # or: python3 src/scan.py --wallet 0xdemo --format md
```

The test suite covers the engine's heuristics, the JSON output schema, and (when run with `cast` installed) a live RPC smoke test against Pharos Pacific Mainnet.

## Repository layout

```
.
├── README.md                  # this file
├── SKILL.md                   # Agent-side description (loaded by Claude/Codex/etc.)
├── scripts/
│   └── scan.sh          # bash + cast engine — the entire skill
├── assets/
│   └── networks.json          # Pharos Skill Engine network config
└── tests/
    └── test_*.sh              # bash smoke test
```
## License

[MIT-0](https://opensource.org/licenses/MIT-0) — free to use, modify,
redistribute. No attribution required.

---

**Author:** arikky1122
**Built with:** Python 3.9+ and a healthy distrust of public memepools.
