# MEV Exposure Reporter

> Quantify a wallet's exposure to **sandwich attacks**, **frontruns**,
> and **backruns** on any EVM chain.

[![bash](https://img.shields.io/badge/bash-4%2B-blue)]()
[![foundry](https://img.shields.io/badge/Foundry-cast%20%7C%20forge-orange)]()
[![license](https://img.shields.io/badge/license-MIT-green)]()
[![rpc](https://img.shields.io/badge/RPC-JSON--RPC%20%7C%20EVM-purple)]()

A read-only Bash + Foundry `cast` skill that scans a wallet's recent
ERC20 Transfer events and emits an **MEV exposure score (0–100)** with a
**NONE / LOW / MEDIUM / HIGH / CRITICAL** verdict.

The skill ships with first-class support for the **Pharos** networks
(Pacific mainnet chainId 1672, Atlantic testnet chainId 688689) and
works against any EVM-compatible JSON-RPC endpoint.

## Features

- **MEV exposure score** — a 0–100 heuristic that weighs transaction
  density, unique tokens touched, and unique blocks covered.
- **Verdict ladder** — NONE / LOW / MEDIUM / HIGH / CRITICAL with a
  clear action associated with each band.
- **Multi-format output** — `text` (default), `json` (machine-readable),
  `markdown` (drop into a doc).
- **Offline demo** — `--demo` mode prints a synthetic report with no
  RPC call, useful for testing the install.
- **Read-only** — no private key, no signing, no transactions.
- **No Python, no pip, no node** — just bash + `cast` (Foundry).
- **Pluggable network** — add any EVM chain by appending to
  `assets/networks.json`.

## Supported networks

The tool runs against any EVM-compatible JSON-RPC endpoint. The
following networks are explicitly supported out of the box:

| Network                | Chain ID | RPC URL                                  | Native token | Explorer                            |
|------------------------|----------|------------------------------------------|--------------|-------------------------------------|
| Pharos Pacific Mainnet | `1672`   | `https://rpc.pharos.xyz`                 | PROS         | https://www.pharosscan.xyz/         |
| Pharos Atlantic Testnet| `688689` | `https://atlantic.dplabs-internal.com`   | PHRS         | https://atlantic.pharosscan.xyz/    |

You can target either by passing the matching `--chain` flag
(see [Usage](#usage)).

## Framework

- **Language:** Bash 4+ (no Python, no node)
- **Engine:** Foundry `cast` CLI for all JSON-RPC reads
- **Network config:** `assets/networks.json` (canonical Pharos Skill
  Engine schema)
- **Output formatter:** built into `scripts/detect.sh` (text / json /
  markdown)

## Dependencies

| Dependency | Required? | Install |
|---|---|---|
| `bash` 4+ | Yes | Pre-installed on macOS, Linux, WSL, and modern Termux |
| `cast` (Foundry) | Yes | `curl -L https://foundry.paradigm.xyz \| bash && foundryup` |
| `jq` | Optional | Used for prettified JSON output and `assets/networks.json` parsing; `apt install jq` / `brew install jq` |
| `coreutils` | Yes | Pre-installed on every Unix |

## Install

### 1. Install Foundry (one-time)

```bash
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc   # or open a new terminal
foundryup
cast --version
```

If you're on **Termux** (Android ARM), the `foundryup` installer does
**not** ship an Android ARM64 binary by default. Use one of these
workarounds:

```bash
# Option A — proot-distro (clean, recommended)
pkg install proot-distro
proot-distro install debian
proot-distro login debian
# now you're in Debian on the phone
curl -L https://foundry.paradigm.xyz | bash && foundryup

# Option B — Android arm64 tarball directly
curl -L -o foundry.tar.gz \
  https://github.com/foundry-rs/foundry/releases/latest/download/foundry_v1.7.1_android_arm64.tar.gz
mkdir -p $PREFIX/local/bin
tar -xzf foundry.tar.gz -C $PREFIX/local/bin forge cast anvil chisel
cast --version
```

### 2. (Optional) Install `jq` for prettier JSON

```bash
# Debian / Ubuntu / Termux
apt install -y jq
# macOS
brew install jq
```

The script works without `jq` (falls back to sed + heredoc), but
`--format json` output is nicer with it.

### 3. Get the skill

```bash
git clone https://github.com/arikky1122/MEVREP
cd MEVREP
chmod +x scripts/*.sh
```

That's it. No build step, no native compilation.

## Quick test (try it in 30 seconds)

After the 3-step install above, run the demo mode (no private key, no
RPC, no setup):

```bash
bash scripts/detect.sh --demo
```

You should see a printed report. The demo uses synthetic data, so it
works offline.

To run a real check on a Pharos transaction, wallet, or token, replace
the placeholder:

```bash
bash scripts/detect.sh --wallet 0xYOUR_WALLET
```

## Use in an AI agent (Claude Code / Codex / OpenClaw / Pharos Agent Center)

The skill ships with a `SKILL.md` that AI agents auto-load. Once
installed in your agent, just ask in natural language — the agent will
read `SKILL.md` and run the bash script for you.

```text
"How exposed is wallet 0xabc... to MEV on Pharos mainnet?"
```

The agent will run `bash scripts/detect.sh --demo` (offline) or the
live command with the address you gave, and read the result back to
you.

### Install in your agent

**Option A — Pharos Agent Center** (one-line install):

```bash
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

### Demo (offline, no RPC, no wallet)

```bash
bash scripts/detect.sh --demo
```

### Scan a Pharos mainnet wallet

```bash
bash scripts/detect.sh --wallet 0xYourWallet --blocks 2000
```

### Scan a Pharos Atlantic testnet wallet

```bash
bash scripts/detect.sh --wallet 0xYourWallet --chain testnet --blocks 2000
```

### JSON output (for an agent pipeline)

```bash
bash scripts/detect.sh --wallet 0xYourWallet --format json | jq .
```

### Markdown output (drop into a doc)

```bash
bash scripts/detect.sh --wallet 0xYourWallet --format markdown > mev-report.md
```

### Command-line flags

| Flag        | Required | Default  | Description                                                  |
|-------------|----------|----------|--------------------------------------------------------------|
| `--wallet`  | yes (or `--demo`) | — | `0x`-prefixed 40-hex address to analyze                  |
| `--chain`   | no       | `mainnet` | `mainnet` (Pharos Pacific, 1672) or `testnet` (Atlantic, 688689) |
| `--rpc-url` | no       | from `assets/networks.json` | Override the default JSON-RPC endpoint            |
| `--blocks`  | no       | `5000`   | How many recent blocks to scan (max 50000)                   |
| `--format`  | no       | `text`   | `text` (default), `json`, or `markdown`                      |
| `--demo`    | no       | —        | Run synthetic-data mode (no RPC call)                        |
| `--help`    | no       | —        | Print the usage banner                                       |

### Sample output

See `examples/sample-output.md` for what a real report looks like.

## AI Agent Integration

This repository ships a `SKILL.md` at the root that any agent
runtime can load to discover the skill. The flow is:

1. The agent reads `SKILL.md` to learn the capability and required
   arguments (`--wallet`, optional `--chain` and `--blocks`).
2. The agent collects the wallet address and target network from
   the user (it never invents either).
3. The agent runs `bash scripts/detect.sh --wallet <addr>
   [--chain mainnet|testnet] [--blocks N] [--format text|json|markdown]`
   and captures stdout.
4. The agent presents the report inline, surfacing the **verdict** and
   the **MEV exposure score** first.

A typical prompt that triggers the skill:

> "How exposed is wallet `0xYourWallet` to MEV on Pharos mainnet over
> the last 2000 blocks?"

A typical reply:

> **Verdict: LOW** — **Score: 20 / 100**
> - 12 transfer events across 9 blocks, touching 3 tokens
> - Explorer: https://www.pharosscan.xyz/address/0xYourWallet

## Repository layout

```
MEVREP/
├── SKILL.md                       # Agent-facing skill spec
├── README.md                      # This file
├── LICENSE                        # MIT
├── assets/
│   └── networks.json              # Pharos Skill Engine network config
├── scripts/
│   └── detect.sh                  # The whole skill (bash + cast)
├── references/
│   └── detection-rules.md         # Heuristics and scoring rules
├── examples/
│   └── sample-output.md           # What a real report looks like
└── tests/
    └── test_detect_smoke.sh       # Smoke test
```

## Tests

```bash
bash tests/test_detect_smoke.sh
```

The smoke test verifies:

- `--help` prints the usage banner and exits 0
- `--demo` runs offline and exits 0
- All three formats (`text`, `json`, `markdown`) work
- Bad inputs are rejected with a clear error
- If `cast` is on PATH, the live RPC path is exercised on a real Pharos
  address with a small `--blocks` to confirm the filter works

## How scoring works

See `references/detection-rules.md` for the full rule set. In short:

| Total ERC20 Transfer events matched | Score | Verdict   |
|------------------------------------:|------:|-----------|
| ≥ 200                               |  85   | CRITICAL  |
| 100 – 199                           |  65   | HIGH      |
| 30 – 99                             |  40   | MEDIUM    |
| 5 – 29                              |  20   | LOW       |
| 0 – 4                               |   5   | NONE      |

The score is a *proxy for MEV extraction surface*, not a dollar-loss
estimate. It tells you how much swap-shaped activity a wallet emits
that sandwichers and arbitrageurs can see.

## Limitations

- The score is a *lower bound* — sophisticated multi-block strategies
  may be missed.
- USD value is not estimated; the score is purely a density heuristic.
- Detection works against public RPC nodes; for very deep history, use
  an archive node or an indexer like The Graph / Covalent.
- The skill does NOT submit transactions. For dollar-loss attribution,
  pair it with an indexer that has full `event` + `transfer` history.

## Roadmap

- [ ] Wire in an on-chain price oracle (Uniswap TWAP or Chainlink).
- [ ] Add archive-node support for deep historical scans.
- [ ] Expand the `KNOWN_MEV_BOTS` allowlist.
- [ ] Optional Telegram / Discord notifier for live exposure.

## Contributing

PRs welcome — especially new EVM chain entries in `assets/networks.json`
and new detection heuristics in `references/detection-rules.md`.

## License

[MIT](LICENSE) — free to use, modify, redistribute. Attribution
appreciated but not required.

---

**Author:** arikky1122
**Built with:** bash, cast, and a healthy distrust of public memepools.
