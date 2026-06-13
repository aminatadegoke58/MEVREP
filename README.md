# MEV Exposure Reporter

> Quantify how much a wallet has lost to sandwich attacks, frontruns, and backruns on Pharos.

[![foundry](https://img.shields.io/badge/built%20with-Foundry-orange)]()
[![bash](https://img.shields.io/badge/script-bash-blue)]()
[![license](https://img.shields.io/badge/license-MIT-green)]()
[![pharos](https://img.shields.io/badge/network-Pharos-blueviolet)]()
[![ai-agent](https://img.shields.io/badge/callable%20by-AI%20agent-purple)]()

## What it is

This is a **skill built for the Pharos network** — a self-contained, deterministic bash script that runs on top of the [Pharos](https://pharos.network) EVM chains. It is **not** an AI agent itself, and not a chatbot. It is a single bash script that:

- takes input from the caller via CLI flags,
- reads live on-chain data from Pharos via `cast` (Foundry),
- runs its own scoring/heuristic logic in pure bash,
- prints a structured report (text, JSON, or markdown) to stdout.

Walks a wallet's recent swap transactions, looks inside the same blocks for sandwich / frontrun / backrun patterns, and produces a structured report with a 0-100 MEV exposure score and per-incident detail.

## Use it from an AI agent

This skill is designed to be **called by an AI agent** (a Claude Code / Codex / Cursor agent, the Pharos Agent Center, or any custom LLM agent). The agent reads `SKILL.md` to discover the skill's flags, fills them in based on the user's request, and runs the bash script in its sandbox. The agent's job is just to translate "score this wallet for MEV risk" into `bash scripts/detect.sh --wallet 0x... --blocks 5000`.

Typical agent-side flow:

```text
User -> Agent: "Score wallet 0xabc... for MEV exposure on Pharos"
Agent -> looks up SKILL.md for MEV Exposure Reporter
Agent -> picks the right flag combo: --wallet 0xabc... 
Agent -> runs: bash scripts/detect.sh --wallet 0xabc... 
Agent -> reads the output, presents it to the user in a friendly form
```

The script prints structured output to stdout and human-readable progress to stderr, so the agent can parse the stdout cleanly (with `jq`) without being polluted by progress messages.

## Install

You need three things: **Foundry** (for `cast`), **jq** (for JSON pretty-printing), and **git** (to clone the repo).

```bash
# 1. Install Foundry (gives you cast, forge, anvil, chisel)
curl -L https://foundry.paradigm.xyz | bash
foundryup
# Reload your shell so the new commands are on PATH:
exec $SHELL
cast --version   # should print 1.x or higher

# 2. Install jq (optional — only needed for --format json pretty-printing)
# macOS:   brew install jq
# Ubuntu:  sudo apt-get install -y jq
# Alpine:  apk add jq
jq --version

# 3. Clone this repo
git clone https://github.com/aminatadegoke58/MEVREP.git
cd MEVREP
chmod +x scripts/*.sh tests/*.sh
```

## Quick test (30 seconds, no API keys needed)

```bash
bash scripts/detect.sh --demo
```

The first time you run this, the script may take a few seconds to fetch block data over RPC. Subsequent runs are cached by the RPC provider.

## Usage

```bash
# Scan a wallet for MEV exposure over the last 5000 blocks
bash scripts/detect.sh --wallet 0xWALLET --blocks 5000

# Run the demo against a known active wallet
bash scripts/detect.sh --demo

# Output as JSON
bash scripts/detect.sh --wallet 0xWALLET --format json
```

### All flags

```
--wallet 0xWALLET --blocks N --chain mainnet|testnet --format text|json|markdown --demo
```

## Networks

The skill is built to run against the Pharos EVM chains. The chain config is stored in `assets/networks.json` and read at startup — no hardcoded URLs in the script.

| Network | Chain ID | RPC URL | Default |
|---|---:|---|:---:|
| mainnet (Pacific Ocean) | 1672 | `https://rpc.pharos.xyz` | ✓ |
| atlantic-testnet | 688689 | `https://atlantic.dplabs-internal.com` |  |

The script defaults to mainnet. Pass `--chain testnet` to use the testnet instead. You can also override the RPC URL directly with `--rpc-url https://your-rpc.example.com`.

## Set it up in an AI agent

Three install paths for any AI agent that wants to call this skill.

### Path A — Pharos Agent Center (for the official Pharos LLM agent)

The Pharos Agent Center is the official agent runtime for the Pharos network. It reads `SKILL.md` from any skill repo to discover capabilities, dependencies, and required flags.

1. **Copy the skill into the Agent Center's skills directory:**
   ```bash
   # After cloning this repo:
   cp -r scripts assets SKILL.md README.md foundry.toml LICENSE \
     ~/.pharos/agent-center/skills/MEVREP/
   ```

2. **Reload the Agent Center's skill registry:**
   ```bash
   pharos-agent reload-skills
   # or restart the Agent Center daemon
   ```

3. **Invoke from the agent's chat UI** (or via the Agent Center's CLI / API):
   ```text
   User: "Score wallet `0xabc...` for MEV exposure on Pharos"
   Agent Center: loads MEV Exposure Reporter, runs:
     bash ~/.pharos/agent-center/skills/MEVREP/scripts/detect.sh --wallet 0xWALLET --chain mainnet
   ```

### Path B — `npx skills add` (for Claude Code, Cursor, Codex, generic MCP agents)

```bash
npx skills add https://github.com/aminatadegoke58/MEVREP --skill MEVREP
```

The agent's `skills` plugin will discover the SKILL.md, surface the skill in its tool list, and let the LLM pick the right flags when the user asks.

### Path C — Manual copy (any agent that reads `~/.claude/skills/`)

```bash
mkdir -p ~/.claude/skills/MEVREP
cp -r scripts assets SKILL.md README.md foundry.toml LICENSE ~/.claude/skills/MEVREP/
```

Restart the agent. It will pick up the new skill on next tool discovery.

### Path D — Direct invocation (shell agents, cron jobs, CI pipelines)

```bash
bash scripts/detect.sh --demo
```

No agent needed — just shell + Foundry.

### What the agent says to invoke this skill

| Caller says | Script invocation |
|---|---|
| Score wallet `0xabc...` for MEV exposure | `bash scripts/detect.sh --wallet 0xabc... --blocks 5000` |
| Run the MEV detector demo | `bash scripts/detect.sh --demo` |
| Show the MEV report as JSON | `bash scripts/detect.sh --wallet 0xabc... --format json` |
| "Run the demo" | `bash scripts/detect.sh --demo` |

The agent should read the script's `--help` output to discover all available flags, then build the right command line for the user's request.

## Framework

| Layer | Tech | Purpose |
|---|---|---|
| Engine | **bash 4+** | Script host (single file per skill) |
| RPC client | **Foundry / cast** | All chain reads — block, tx, receipt, eth_call, eth_getLogs |
| Chain config | **JSON** (`assets/networks.json`) | Network endpoints + chain IDs |
| Data format | **JSON** | Cast's native output; jq used only for pretty-printing |
| Runtime | Any POSIX shell, Foundry 1.0+ | Tested on Linux + macOS |

## Dependencies

**Required:**
- [Foundry](https://getfoundry.sh) (gives you `cast`, `forge`, `anvil`)
- `bash` 4+ (preinstalled on macOS, Ubuntu 20+, most Linux)

**Optional:**
- `jq` — only required if you pass `--format json` for pretty-printed output
- `git` — only required if you're cloning the repo (you already have it)

## Tests

Each repo ships with a bash smoke test that verifies:
1. `--help` works (no cast required)
2. The script prints a useful error when args are missing
3. The script prints a clear error when cast is not installed
4. The script rejects unknown flags and bad network names
5. (If applicable) `from-block > to-block` is detected and rejected

```bash
bash tests/test_*.sh
```

The test runs offline — no RPC calls, no API keys. It exercises the help text, arg parser, and error paths.

## Repository layout

```
MEVREP/
├── SKILL.md              # Skill contract (Capability Index, Error Handling, Security Reminders)
├── README.md             # This file
├── foundry.toml          # Minimal config so cast can find the project root
├── LICENSE               # MIT
├── assets/
│   └── networks.json     # mainnet + testnet chain config (read by every script)
├── scripts/
│   └── detect.sh          # The single bash script that does the work
└── tests/
    └── test_*.sh         # Offline smoke test (no cast required)
```

## License

MIT — see `LICENSE`.

---
