---
name: mev-exposure-reporter
description: >
  REQUIRED for any task that requires quantifying a wallet's losses to
  Maximal Extractable Value (MEV) on an EVM chain. Invoke when the user asks
  to "analyze MEV exposure", "show MEV losses", "check sandwich attacks",
  "frontrun report", "how much did I lose to MEV", "slippage analysis",
  or wants a per-token / per-protocol breakdown of value extracted from
  their wallet's swap transactions. Use the bundled `src/detect_mev.py`
  detector to scan a wallet's transaction history via JSON-RPC against
  any EVM-compatible RPC endpoint.
  Do not attempt MEV exposure analysis without reading this skill.
version: 1.1.0
requires: read
bins: [python3]
author: arikky1122
tags: [pharos, security, mev, defi, sandwich, frontrun, agent-skill]
agents: [claude, codex, gemini, openclaw]
---


# MEV Exposure Reporter

Quantify how much a wallet lost to **sandwich attacks** and **frontrunning**
on any EVM-compatible chain.

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

- Single-tx debugging (use a general-purpose chain query tool).
- Approval/permission auditing (use a dedicated approval tool).
- General portfolio aggregation (use a wallet asset aggregator).

## Inputs

| Input          | Required | Description                                   |
|----------------|----------|-----------------------------------------------|
| `wallet`       | yes      | 0x address to analyze                         |
| `rpc_url`      | yes      | JSON-RPC endpoint (any EVM-compatible chain)  |
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

# 2. Run a scan
python src/detect_mev.py \
  --wallet 0xYourWalletHere \
  --rpc-url https://rpc.pharos.xyz \
  --block-count 2000

# 3. Get a JSON report
python src/detect_mev.py \
  --wallet 0xYourWalletHere \
  --rpc-url https://rpc.pharos.xyz \
  --format json > report.json
```

## Agent invocation pattern

When the user asks for an MEV report, the Agent should:

1. Resolve the RPC URL — accept the user's URL, or use a known EVM RPC
   for the chain the user mentions.
2. Ask the user for the wallet address (never invent one).
3. Run `src/detect_mev.py` with the parameters above.
4. Pipe the output through `src/report.py` to produce a human-readable
   summary.
5. Present the report inline, with a top-level "Total MEV loss" headline
   number and a sortable table of incidents.

## Error handling

| Error                              | Cause                          | Action |
|------------------------------------|--------------------------------|--------|
| `rpc unreachable`                  | Bad / dead RPC URL             | Ask user for a working RPC |
| `wallet has no txs in range`       | Wallet inactive or new         | Increase `--block-count` or confirm address |
| `unknown router selector`          | DEX not yet supported          | Add selector to `references/detection-rules.md` |
| `insufficient price reference`     | Token has no USDC pair         | Note the unknown token, skip USD estimate |

## Limitations

- MEV loss is a *lower bound* — sophisticated multi-block strategies may
  be missed.
- USD value depends on price reference availability per token.
- Detection works against public RPC nodes; for very deep history use an
  archive node or an indexer like The Graph / Covalent.

## Prerequisites

```bash
python3 --version   # 3.10+
```

The skill uses only the Python standard library (`urllib.request`,
`json`, `argparse`). No third-party packages, no Foundry, no
`pip install` step.

The skill is **read-only** — no private key is required or accepted.

## Network Configuration

Network RPC URLs and chain IDs are sourced from
`assets/networks.json` (canonical Pharos Skill Engine schema). To
add a new network, append a new object to the `networks` array and
update `defaultNetwork` if needed.

## Capability Index

| User Need | Capability | Detailed Instructions |
|---|---|---|
| Default entry point | CLI with a `--wallet` / `--safe` / `--governor` flag | See the `Usage` section in the README; the CLI takes a target identifier and prints a Markdown or JSON report |
| JSON for an agent | `--format json` | Output is a structured payload that an agent can import directly |
| Markdown report | pipe to `report.py` | `python3 src/... --format json \| python3 src/report.py --format markdown --out X.md` |
| Bounded scan | `--max-blocks` / `--lookback` / `--block-count` | Default scans are bounded to stay within the public Pharos RPC's request rate |
| Network switch | `--chain mainnet\|testnet` | Default is Atlantic testnet; pass `--chain mainnet` to switch |

## General Error Handling

| Error Scenario | CLI Error Signature | Handling |
|---|---|---|
| Target not on the specified chain | `null` receipt / no data returned | Exit with "not found on chain=X; try `--chain <other>`" |
| RPC rate-limited (HTTP 429) | Backoff response from RPC | Built-in exponential backoff (0.4s, 0.8s, 1.6s, 3.2s) with 4 retry attempts |
| Bad target format | Validator rejects the input | CLI prints a usage hint; no RPC call is made |
| Missing required arg | `argparse` exits with usage | CLI prints required args; user re-invokes with the right flags |
| No matches (clean target) | Empty result / `verdict: clean` | Normal case — emit the "no issues" report, no error |

## Security Reminders

- **Private Key Protection** — the skill is read-only and never
  accepts a private key. Do not paste keys into chat.
- **Network Confirmation** — before any future write-skill
  integration, confirm the network with the user.
- **No External API** — the skill does not call any third-party
  service beyond the Pharos RPC and PharosScan (where applicable).
  All data is fetched directly.

## Write Operation Pre-checks

This skill is **read-only** and never submits a transaction, so the
full 4-step write pre-check is not applicable. If a future version
adds a write path, the pre-checks must include:

1. **Private Key Check** — `--private-key` / `$PRIVATE_KEY` must be
   set; warn if the key has zero balance.
2. **Derive Public Address** — `cast wallet address`; confirm the
   key is for the intended network.
3. **Network Confirmation** — prompt the user with "You are about
   to write to Pacific mainnet. Continue? (y/N)".
4. **Automatic Balance Check** — `cast balance`; if below the
   operation cost + gas, abort with a clear error.
