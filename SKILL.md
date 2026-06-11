---
name: mev-exposure-reporter
description: >
  Quantify a wallet's MEV (sandwich, frontrun, backrun) exposure on any
  EVM chain. Invoke when the user asks "how much have I lost to MEV",
  "analyze MEV exposure", "show MEV losses", "check sandwich attacks",
  "frontrun report", or wants a per-token / per-block breakdown of
  value-extraction surface around their wallet's transactions. Uses
  Foundry's `cast` CLI to scan recent blocks for ERC20 Transfer events
  involving the wallet and produces an MEV exposure score 0–100 plus a
  NONE / LOW / MEDIUM / HIGH / CRITICAL verdict. Do not attempt MEV
  analysis without reading this skill first.
version: 2.0.0
requires: any
bins: [bash, cast]
author: arikky1122
tags: [pharos, security, mev, defi, sandwich, frontrun, agent-skill, foundry]
agents: [claude, codex, gemini, openclaw]
---


# MEV Exposure Reporter

Quantify a wallet's **MEV exposure surface** on any EVM-compatible chain
reachable via JSON-RPC. The skill reads the wallet's recent ERC20
Transfer events, counts unique blocks and unique tokens touched, and
emits:

- An **MEV exposure score** 0–100
- A verdict: **NONE / LOW / MEDIUM / HIGH / CRITICAL**
- Per-block, per-token counts of activity (a proxy for swap density)
- An optional JSON or Markdown report

This is a **read-only** skill — no private key, no signing, no
transactions.

## When to use

- The user asks "how much have I lost to MEV on Pharos?"
- The user asks to audit a wallet for sandwich / frontrun / backrun risk.
- The user wants a quick "MEV exposure score" for a wallet.
- The user wants a per-token / per-block breakdown of their swap surface.

## When NOT to use

- Single-tx debugging (use a chain query / debug skill).
- Allowance / permission auditing (use a dedicated approval skill).
- General portfolio aggregation (use a wallet asset aggregator).

## Inputs

| Input         | Required | Description                                              |
|---------------|----------|----------------------------------------------------------|
| `wallet`      | yes      | `0x`-prefixed 40-hex address to analyze                  |
| `chain`       | no       | `mainnet` (default, Pharos chainId 1672) or `testnet` (Atlantic, 688689) |
| `rpc_url`     | no       | Override the default JSON-RPC URL (read from `assets/networks.json`) |
| `blocks`      | no       | How many recent blocks to scan (default 5000, max 50000) |
| `format`      | no       | `text` (default), `json`, or `markdown`                  |
| `demo`        | no       | Run synthetic-data mode (no RPC call, useful for offline testing) |

## Outputs

A structured report with:

- Total ERC20 Transfer events involving the wallet in the scanned range
- Number of unique blocks and unique tokens touched
- Estimated incident count (`events / 3`, capped at 100)
- An MEV exposure score 0–100 with a NONE / LOW / MEDIUM / HIGH / CRITICAL verdict
- A direct link to the wallet on the Pharos block explorer

## Quick start

```bash
# 1. Install Foundry (one-time)
curl -L https://foundry.paradigm.xyz | bash && source ~/.bashrc && foundryup

# 2. Clone the skill
git clone https://github.com/arikky1122/MEVREP
cd MEVREP
chmod +x scripts/*.sh

# 3. Run a scan
bash scripts/detect.sh --wallet 0xYOUR_WALLET --blocks 5000

# 4. Get a JSON report
bash scripts/detect.sh --wallet 0xYOUR_WALLET --format json > report.json

# 5. Get a Markdown report
bash scripts/detect.sh --wallet 0xYOUR_WALLET --format markdown > report.md

# 6. Try the offline demo (no RPC, no wallet)
bash scripts/detect.sh --demo
```

## Agent invocation pattern

When the user asks for an MEV report, the Agent should:

1. Resolve the wallet address — ask the user, never invent one.
2. Resolve the chain — default to `mainnet`, allow `testnet`.
3. Run `bash scripts/detect.sh --wallet <addr> [--chain mainnet|testnet]
   [--blocks N] [--format text|json|markdown]`.
4. Capture stdout. If the user wants a formatted report, switch
   `--format markdown` or pipe `--format json` through `jq` for prettier
   output.
5. Present the report inline, surfacing the **verdict** and the
   **MEV exposure score** first.

A typical prompt that triggers the skill:

> "How exposed is wallet `0xabc...` to MEV on Pharos mainnet?"

A typical reply:

> **Verdict: LOW** — **Score: 20 / 100**
> - 12 transfer events across 9 blocks, touching 3 tokens
> - Explorer: https://www.pharosscan.xyz/address/0xabc...

## Error handling

| Error                              | CLI Error Signature                | Action |
|------------------------------------|------------------------------------|--------|
| `cast` not installed               | `Error: 'cast' not found…`         | Tell user to run the Foundry installer |
| `assets/networks.json` missing     | `Error: …networks.json not found`  | Re-clone the repo (don't run from a partial copy) |
| Invalid wallet format              | `Error: --wallet must be a 0x-prefixed 40-hex address` | Ask user for a valid address |
| Negative / too-large blocks        | `Error: --blocks must be a positive integer` / `… capped at 50000` | Re-pick a smaller range |
| Wallet has no activity in range    | `Verdict: NONE` with 0 events      | Normal — wallet is clean or new. Try a larger `--blocks` |
| RPC rate-limited                   | `eth_getLogs` returns `[]` or errors | Backs off per batch; try `--blocks 1000` first, then scale up |
| Unknown format / chain             | `Error: --format must be text|json|markdown` / `--chain must be mainnet|testnet` | Use one of the documented values |

## Limitations

- The score is a heuristic based on ERC20 Transfer density — a
  *lower bound* on MEV exposure, not a dollar-loss estimate.
- Multi-block MEV strategies and private-mempool extractions may be
  missed.
- Detection is read-only and works against any public RPC node; for
  very deep history, use an archive node.
- The score is **not** a per-tx loss calculation. It tells you the
  *shape* of your swap surface, not the dollar amount extracted.

## Security

- The skill is **read-only** — no private key is required or accepted.
- Never paste private keys into the chat when running this skill.
- The skill calls only the RPC endpoint configured in
  `assets/networks.json` (or whatever `--rpc-url` you pass). It does
  not call any third-party service.

## Network Configuration

Network RPC URLs and chain IDs are sourced from `assets/networks.json`
(canonical Pharos Skill Engine schema). To add a new EVM chain, append
a new object to the `networks` array:

```json
{
  "name": "my-chain",
  "rpcUrl": "https://rpc.mychain.example",
  "chainId": 12345,
  "explorerUrl": "https://explorer.mychain.example/",
  "nativeToken": "ETH"
}
```

## Capability Index

| User Need | Capability | Detailed Instructions |
|---|---|---|
| Quick read-only check | `bash scripts/detect.sh --wallet 0x...` | text report printed inline |
| JSON for an agent | `--format json` | Output is a structured payload importable via `jq` |
| Markdown for a doc | `--format markdown` | Output is a `report.md`-shaped document |
| Bounded scan | `--blocks N` | Default 5000, max 50000 |
| Network switch | `--chain mainnet` / `--chain testnet` | Default `mainnet` (Pharos Pacific, chainId 1672) |
| Demo / offline | `--demo` | No RPC call; synthetic numbers, useful for testing |

## General Error Handling

| Error Scenario | CLI Behavior | User-Facing Action |
|---|---|---|
| Wallet with no activity | `Verdict: NONE`, score 5 | Increase `--blocks` or check the address |
| RPC returns errors | `cast rpc` errors are swallowed per-batch; report still completes | Re-run with smaller `--blocks` (e.g. 1000) |
| `cast` missing | `Error: 'cast' not found…` with install instructions | Run the Foundry installer |
| Bad input | Script exits 1 with a one-line error and the usage banner | Re-run with the right flag |

## Security Reminders

- **Private Key Protection** — the skill is read-only and never
  accepts a private key. Do not paste keys into chat.
- **Network Confirmation** — before any future write-skill integration,
  confirm the network with the user.
- **No External API** — the skill calls only the configured JSON-RPC
  endpoint. No third-party service is contacted.

## Write Operation Pre-checks

This skill is **read-only** and never submits a transaction, so the
full 4-step write pre-check is not applicable. If a future version
adds a write path, the pre-checks must include:

1. **Private Key Check** — `--private-key` / `$PRIVATE_KEY` must be set.
2. **Derive Public Address** — `cast wallet address`; confirm the key
   is for the intended network.
3. **Network Confirmation** — prompt the user with "You are about to
   write to Pacific mainnet. Continue? (y/N)".
4. **Automatic Balance Check** — `cast balance`; if below the operation
   cost + gas, abort with a clear error.
