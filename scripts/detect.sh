#!/usr/bin/env bash
# MEVREP — Pharos MEV Exposure Reporter
# https://github.com/arikky1122/MEVREP
#
# Heuristic MEV-exposure scanner for any EVM chain reachable via JSON-RPC.
# Reads:
#   - A wallet's ERC20 Transfer events (proxy for swap activity)
# Produces:
#   - MEV exposure score 0-100
#   - Verdict: NONE / LOW / MEDIUM / HIGH / CRITICAL
#   - text, json, or markdown report
#
# All human-readable output (banner, progress, status) goes to STDERR so
# --format json / --format markdown output on STDOUT stays parseable by
# jq / pipeline tools.
#
# Usage:
#   bash scripts/detect.sh --demo
#   bash scripts/detect.sh --wallet 0x... --blocks 5000
#   bash scripts/detect.sh --wallet 0x... --format json
#   bash scripts/detect.sh --wallet 0x... --format markdown
#
# Requires:
#   - Foundry (cast): curl -L https://foundry.paradigm.xyz | bash && foundryup
#   - bash 4+ and standard coreutils
# Optional:
#   - jq (for prettified JSON when --format json is used)

set -uo pipefail   # NOTE: deliberately NOT -e — empty grep matches are normal
                   # during a clean scan and must not abort the script.

# ---- Foundry required ----
if ! command -v cast >/dev/null 2>&1; then
  cat >&2 <<'EOF'
Error: 'cast' not found. Install Foundry first:

  curl -L https://foundry.paradigm.xyz | bash
  source ~/.bashrc   # or restart your shell
  foundryup

Then verify with:  cast --version
EOF
  exit 1
fi

# ---- Tiny logger (stderr only) ----
log() { printf '%s\n' "$*" >&2; }

# ---- Locate repo root (parent of scripts/) ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NET_JSON="$REPO_ROOT/assets/networks.json"
[ -f "$NET_JSON" ] || { log "Error: $NET_JSON not found"; exit 1; }

# ---- Read network config (jq if present, otherwise pure awk) ----
read_net() {
  local name="$1" field="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg n "$name" --arg f "$field" \
      '.networks[] | select(.name==$n) | .[$f] // ""' "$NET_JSON"
  else
    awk -v n="$name" -v f="$field" '
      $0 ~ "\"name\": *\""n"\"" {found=1}
      found && $0 ~ "\""f"\": *\"" { sub(".*\""f"\": *\"",""); sub("\".*",""); print; exit }
      found && $0 ~ "^    }" {exit}
    ' "$NET_JSON"
  fi
}

# ---- Defaults ----
WALLET=""
RPC_URL=""
CHAIN="mainnet"
BLOCKS=5000
FORMAT="text"
DEMO=0

# ---- Usage ----
usage() {
  cat <<USAGE
MEVREP — Pharos MEV Exposure Reporter

Usage:
  bash scripts/detect.sh --wallet 0x... [--chain mainnet|testnet]
                          [--blocks N] [--format text|json|markdown]
                          [--demo] [--help]

Examples:
  bash scripts/detect.sh --demo
  bash scripts/detect.sh --wallet 0xYOUR_WALLET --blocks 2000
  bash scripts/detect.sh --wallet 0xYOUR_WALLET --format json
  bash scripts/detect.sh --wallet 0xYOUR_WALLET --format markdown
  bash scripts/detect.sh --wallet 0xYOUR_WALLET --chain testnet

Prerequisites:
  Foundry (cast):  curl -L https://foundry.paradigm.xyz | bash && foundryup
  Optional:        jq  (for prettified JSON output)

Output:
  - Human-readable status (banner, progress) goes to STDERR
  - The structured report (text/json/markdown) goes to STDOUT
  - This means: bash scripts/detect.sh --format json | jq . works cleanly
USAGE
}

# ---- Arg parse ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)        usage; exit 0 ;;
    --wallet)         WALLET="$2"; shift 2 ;;
    --chain)          CHAIN="$2"; shift 2 ;;
    --rpc-url)        RPC_URL="$2"; shift 2 ;;
    --blocks)         BLOCKS="$2"; shift 2 ;;
    --format)         FORMAT="$2"; shift 2 ;;
    --demo)           DEMO=1; shift ;;
    *)                log "Unknown arg: $1"; usage >&2; exit 1 ;;
  esac
done

# ---- Validate format ----
case "$FORMAT" in
  text|json|markdown) ;;
  *) log "Error: --format must be text|json|markdown (got '$FORMAT')"; exit 1 ;;
esac

# ---- Validate chain (alias then networks.json check) ----
case "$CHAIN" in
  mainnet) NET_NAME="mainnet" ;;
  testnet) NET_NAME="atlantic-testnet" ;;
  *)       NET_NAME="$CHAIN" ;;
esac
if command -v jq >/dev/null 2>&1; then
  VALID_CHAINS=$(jq -r '.networks[].name' "$NET_JSON" | tr '\n' '|' | sed 's/|$//')
else
  VALID_CHAINS=$(grep -oE '"name": *"[^"]+"' "$NET_JSON" | sed -E 's/.*"name": *"([^"]+)".*/\1/' | tr '\n' '|' | sed 's/|$//')
fi
if ! echo "$NET_NAME" | grep -qE "^($VALID_CHAINS)$"; then
  log "Error: --chain must be one of: $VALID_CHAINS (got '$CHAIN')"
  exit 1
fi
[ -z "$RPC_URL" ]     && RPC_URL="$(read_net "$NET_NAME" rpcUrl)"
EXPLORER_URL="$(read_net "$NET_NAME" explorerUrl | sed 's#/$##')"
CHAIN_ID="$(read_net "$NET_NAME" chainId)"
NATIVE_TOKEN="$(read_net "$NET_NAME" nativeToken)"

# ---- Demo mode (no RPC) ----
if [ "$DEMO" = "1" ]; then
  WALLET="${WALLET:-0x67992af9a87f2d6a3062c333d8a06abbe3929438}"
fi

# ---- Validate wallet ----
if [ -z "$WALLET" ]; then
  log "Error: --wallet required (or use --demo)"
  usage >&2
  exit 1
fi
if ! [[ "$WALLET" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
  log "Error: --wallet must be a 0x-prefixed 40-hex address"
  exit 1
fi

# ---- Validate blocks ----
if ! [[ "$BLOCKS" =~ ^[0-9]+$ ]] || [ "$BLOCKS" -lt 1 ]; then
  log "Error: --blocks must be a positive integer"
  exit 1
fi
[ "$BLOCKS" -gt 50000 ] && { log "Error: --blocks capped at 50000 to stay polite to public RPCs"; exit 1; }

[ -z "$CHAIN_ID" ] && { log "Error: chainId not found in networks.json"; exit 1; }
[ -z "$RPC_URL" ]  && { log "Error: rpcUrl not found in networks.json"; exit 1; }

# ---- Banner (stderr) ----
log ""
log "========================================================================"
log "  MEV EXPOSURE REPORT"
log "  Wallet:  $WALLET"
log "  Chain:   $NET_NAME (chainId $CHAIN_ID)"
log "========================================================================"
log ""

# =========================================================================
# Live RPC path
# =========================================================================
if [ "$DEMO" = "0" ]; then
  # --- Wallet info ---
  NONCE_HEX="$(cast nonce --rpc-url "$RPC_URL" "$WALLET" 2>/dev/null || echo "0x0")"
  NONCE="$(cast --to-dec "$NONCE_HEX" 2>/dev/null || echo 0)"
  BALANCE_WEI="$(cast balance --rpc-url "$RPC_URL" "$WALLET" 2>/dev/null || echo "0")"
  log "  Wallet nonce:     $NONCE  (outgoing tx count)"
  log "  Wallet balance:   $BALANCE_WEI wei  (~$NATIVE_TOKEN)"

  # --- Head block ---
  HEAD_HEX="$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null || echo "0x0")"
  HEAD="$(cast --to-dec "$HEAD_HEX" 2>/dev/null || echo 0)"
  START=$(( HEAD - BLOCKS ))
  [ "$START" -lt 0 ] && START=0
  log "  Head block:       $HEAD"
  log "  Scanning blocks:  [$START, $HEAD]  (last $BLOCKS)"
  log ""

  # --- Scan: count Transfer events (topic[0]=Transfer, topic[1]=wallet-padded) ---
  SWAP_TOPIC="0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
  PADDED_WALLET="0x000000000000000000000000${WALLET#0x}"

  TEMP=$(mktemp -d)
  LOGS_FILE="$TEMP/logs.jsonl"
  : > "$LOGS_FILE"

  current=$START
  BATCH=999
  BATCH_NUM=0
  BATCH_FAILS=0
  log "  Fetching Transfer events for the wallet..."

  while [ "$current" -le "$HEAD" ]; do
    end=$(( current + BATCH ))
    [ "$end" -gt "$HEAD" ] && end=$HEAD
    BATCH_NUM=$(( BATCH_NUM + 1 ))

    # Use cast --to-hex for portability (avoid bash 32-bit printf overflow
    # on chains with block numbers > 2^31).
    from_hex="$(cast --to-hex "$(printf '%d' "$current")" 2>/dev/null || echo "0x$(printf '%x' "$current")")"
    to_hex="$(cast --to-hex "$(printf '%d' "$end")" 2>/dev/null || echo "0x$(printf '%x' "$end")")"

    # eth_getLogs expects a SINGLE object {}, not an array [].
    # Hard timeout: 30s per batch — if the RPC stalls, kill cast and move on.
    resp="$(timeout 30 cast rpc --rpc-url "$RPC_URL" eth_getLogs \
      "{\"fromBlock\":\"$from_hex\",\"toBlock\":\"$to_hex\",\"topics\":[\"$SWAP_TOPIC\",\"$PADDED_WALLET\"]}" \
      2>/dev/null || echo "TIMEOUT_OR_ERROR")"

    if [ "$resp" = "[]" ] || [ -z "$resp" ] || [ "$resp" = "TIMEOUT_OR_ERROR" ]; then
      if [ "$resp" = "TIMEOUT_OR_ERROR" ]; then
        BATCH_FAILS=$(( BATCH_FAILS + 1 ))
        log "    [batch $BATCH_NUM] $current..$end: timeout/error (skipped)"
      fi
      current=$(( end + 1 ))
      continue
    fi

    printf '%s\n' "$resp" | grep -oE '"blockNumber":"0x[a-fA-F0-9]+","address":"0x[a-fA-F0-9]{40}"' \
      | sed -E 's/.*"blockNumber":"([^"]+)".*"address":"([^"]+)".*/\1 \2/' \
      >> "$LOGS_FILE" 2>/dev/null || true

    new_count=$(wc -l < "$LOGS_FILE" | tr -d ' ')
    log "    [batch $BATCH_NUM] $current..$end: $new_count events so far"

    current=$(( end + 1 ))
  done

  if [ "$BATCH_FAILS" -gt 0 ]; then
    log "  Warning: $BATCH_FAILS batch(es) failed/timed-out. Results may be incomplete."
    log "  Try a smaller --blocks (e.g. --blocks 1000) and re-run."
  fi

  TOTAL_LOGS=$(wc -l < "$LOGS_FILE" | tr -d ' ')
  UNIQUE_BLOCKS=$(awk '{print $1}' "$LOGS_FILE" | sort -u | wc -l | tr -d ' ')
  UNIQUE_TOKENS=$(awk '{print $2}' "$LOGS_FILE" | sort -u | wc -l | tr -d ' ')

  rm -rf "$TEMP"
else
  # =========================================================================
  # Demo path (no RPC; synthetic but plausible numbers)
  # =========================================================================
  NONCE=47
  BALANCE_WEI="1000000000000000000"  # 1.0 PROS
  HEAD=0; START=0
  TOTAL_LOGS=12
  UNIQUE_BLOCKS=9
  UNIQUE_TOKENS=3
  log "  (DEMO mode — synthetic numbers, no RPC call made)"
  log "  Wallet nonce:     $NONCE  (outgoing tx count)"
  log "  Wallet balance:   $BALANCE_WEI wei  (~$NATIVE_TOKEN)"
  log ""
fi

# ---- Scoring ----
SCORE=0
INCIDENT_COUNT=0
if   [ "$TOTAL_LOGS" -ge 200 ]; then SCORE=85; VERDICT="CRITICAL"
elif [ "$TOTAL_LOGS" -ge 100 ]; then SCORE=65; VERDICT="HIGH"
elif [ "$TOTAL_LOGS" -ge 30  ]; then SCORE=40; VERDICT="MEDIUM"
elif [ "$TOTAL_LOGS" -ge 5   ]; then SCORE=20; VERDICT="LOW"
else                                SCORE=5;  VERDICT="NONE"
fi
INCIDENT_COUNT=$(( TOTAL_LOGS / 3 ))
[ "$INCIDENT_COUNT" -gt 100 ] && INCIDENT_COUNT=100

# ---- Format output (stdout only) ----
EXPLORER_LINK="$EXPLORER_URL/address/$WALLET"
GEN_TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

case "$FORMAT" in
  json)
    if command -v jq >/dev/null 2>&1; then
      jq -n \
        --arg wallet    "$WALLET" \
        --arg chain     "$NET_NAME" \
        --argjson cid   "$CHAIN_ID" \
        --arg explorer  "$EXPLORER_LINK" \
        --argjson nonce "$NONCE" \
        --argjson start "$START" \
        --argjson head  "$HEAD" \
        --argjson blocks "$BLOCKS" \
        --argjson logs  "$TOTAL_LOGS" \
        --argjson ub    "$UNIQUE_BLOCKS" \
        --argjson ut    "$UNIQUE_TOKENS" \
        --argjson score "$SCORE" \
        --arg verdict   "$VERDICT" \
        --arg ts        "$GEN_TS" \
        '{
          wallet: $wallet,
          chain: $chain,
          chainId: $cid,
          explorer: $explorer,
          victimTxCount: $nonce,
          scannedBlocks: $blocks,
          startBlock: $start,
          endBlock: $head,
          swapEvents: $logs,
          uniqueBlocks: $ub,
          uniqueTokens: $ut,
          incidentCount: ($logs / 3 | floor),
          mevScore: $score,
          verdict: $verdict,
          generatedAt: $ts
        } | if .incidentCount > 100 then .incidentCount = 100 else . end'
    else
      cat <<JSON
{
  "wallet": "$WALLET",
  "chain": "$NET_NAME",
  "chainId": $CHAIN_ID,
  "explorer": "$EXPLORER_LINK",
  "victimTxCount": $NONCE,
  "scannedBlocks": $BLOCKS,
  "startBlock": $START,
  "endBlock": $HEAD,
  "swapEvents": $TOTAL_LOGS,
  "uniqueBlocks": $UNIQUE_BLOCKS,
  "uniqueTokens": $UNIQUE_TOKENS,
  "incidentCount": $INCIDENT_COUNT,
  "mevScore": $SCORE,
  "verdict": "$VERDICT",
  "generatedAt": "$GEN_TS"
}
JSON
    fi
    ;;

  markdown)
    cat <<MD
# MEV Exposure Report

| Field | Value |
|---|---|
| Wallet | \`$WALLET\` |
| Chain | $NET_NAME (chainId $CHAIN_ID) |
| Generated | $GEN_TS |
| Explorer | $EXPLORER_LINK |

## Verdict: **$VERDICT**

## Score: **$SCORE / 100**

| Metric | Value |
|---|---|
| Scanned blocks | $BLOCKS |
| Outgoing tx count (nonce) | $NONCE |
| Transfer events matched | $TOTAL_LOGS |
| Unique blocks touched | $UNIQUE_BLOCKS |
| Unique tokens touched | $UNIQUE_TOKENS |
| Estimated incidents | $INCIDENT_COUNT |

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
MD
    ;;

  text|*)
    cat <<TEXT
  Scanned blocks:       $BLOCKS
  Outgoing tx count:    $NONCE
  Transfer events:      $TOTAL_LOGS
  Unique blocks:        $UNIQUE_BLOCKS
  Unique tokens:        $UNIQUE_TOKENS
  Estimated incidents:  $INCIDENT_COUNT
  MEV exposure score:   $SCORE/100

  >>> VERDICT: $VERDICT  <<<

  Explorer: $EXPLORER_LINK
TEXT
    ;;
esac

exit 0
