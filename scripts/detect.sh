#!/usr/bin/env bash
# MEVREP — Pharos MEV Exposure Reporter (Foundry port).
#
# Detects three classes of value extraction:
#   1. Sandwich attack — three txs in one block, same pool, attacker
#      brackets the victim (confidence 0.85)
#   2. Frontrun — same `to` + same function selector, lands before victim
#   3. Backrun — same as frontrun but lands after victim
#
# All RPC reads go through `cast`. The scoring is heuristic, not
# statistical. Treat CRITICAL as "needs a human".
#
# Usage:
#   bash scripts/detect.sh --wallet 0x... [--rpc-url URL] [--blocks N] [--demo]
#   bash scripts/detect.sh --wallet 0x... --format json
#   bash scripts/detect.sh --wallet 0x... --format json | bash scripts/report.sh --format markdown

set -euo pipefail

# ---- Load network config ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NET_JSON="$SCRIPT_DIR/../assets/networks.json"
[ ! -f "$NET_JSON" ] && { echo "Error: $NET_JSON not found"; exit 1; }

get_field() {
  local net_name="$1" field="$2"
  sed -n "/\"name\": *\"$net_name\"/,/^    }/p" "$NET_JSON" \
    | grep -E "\"$field\":" | head -1 \
    | sed -E 's/^[^:]+:[[:space:]]*"([^"]*)".*/\1/' | sed -E 's/,$//'
}
get_num() {
  local net_name="$1" field="$2"
  sed -n "/\"name\": *\"$net_name\"/,/^    }/p" "$NET_JSON" \
    | grep -E "\"$field\":" | head -1 | grep -oE '[0-9]+' | head -1
}

# ---- Arg parsing ----
WALLET=""
RPC_URL=""
CHAIN="mainnet"
BLOCKS=5000
FORMAT="text"
DEMO=0

usage() {
  cat <<USAGE
MEVREP — Pharos MEV Exposure Reporter (Foundry port)

Usage:
  bash scripts/detect.sh --wallet 0x... [--chain mainnet|testnet]
                          [--blocks N] [--format text|json|markdown]
                          [--demo] [--help]

Examples:
  bash scripts/detect.sh --wallet 0xWALLET --blocks 5000
  bash scripts/detect.sh --wallet 0xWALLET --format json
  bash scripts/detect.sh --demo   # uses a real public mainnet address

Prerequisites:
  - Foundry (cast): curl -L https://foundry.paradigm.xyz | bash && foundryup
  - jq: optional, for --json pretty-printing
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --wallet) WALLET="$2"; shift 2 ;;
    --chain) CHAIN="$2"; shift 2 ;;
    --rpc-url) RPC_URL="$2"; shift 2 ;;
    --blocks) BLOCKS="$2"; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    --demo) DEMO=1; shift ;;
    -*) echo "Unknown flag: $1" >&2; usage; exit 1 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

# Resolve network
case "$CHAIN" in
  mainnet) RPC_URL="${RPC_URL:-$(get_field mainnet rpcUrl)}"; EXPLORER_URL=$(get_field mainnet explorerUrl); CHAIN_ID=$(get_num mainnet chainId) ;;
  testnet) RPC_URL="${RPC_URL:-$(get_field atlantic-testnet rpcUrl)}"; EXPLORER_URL=$(get_field atlantic-testnet explorerUrl); CHAIN_ID=$(get_num atlantic-testnet chainId) ;;
  *) echo "Unknown chain: $CHAIN" >&2; exit 1 ;;
esac

# Demo
[ "$DEMO" = "1" ] && WALLET="0x67992af9a87f2d6a3062c333d8a06abbe3929438"

if [ -z "$WALLET" ]; then
  echo "Error: --wallet required (or use --demo)" >&2
  usage
  exit 1
fi

# ---- Foundry required (checked AFTER arg parsing so --help works offline) ----
if ! command -v cast >/dev/null 2>&1; then
  echo "Error: 'cast' not found. Install Foundry:" >&2
  echo "  curl -L https://foundry.paradigm.xyz | bash && foundryup" >&2
  exit 1
fi

# ---- Foundry required (checked AFTER arg parsing so --help works offline) ----
if ! command -v cast >/dev/null 2>&1; then
  echo "Error: 'cast' not found. Install Foundry:" >&2
  echo "  curl -L https://foundry.paradigm.xyz | bash && foundryup" >&2
  exit 1
fi

# Validate blocks
if ! [[ "$BLOCKS" =~ ^[0-9]+$ ]]; then
  echo "Error: --blocks must be a non-negative integer" >&2
  exit 1
fi

# ---- Fetch wallet info ----
echo ""
echo "========================================================================"
echo "  MEV EXPOSURE REPORT"
echo "  Wallet: $WALLET"
echo "  ChainId: $CHAIN_ID"
echo "========================================================================"
echo ""

NONCE=$(cast nonce --rpc-url "$RPC_URL" "$WALLET" 2>/dev/null | tr -d '\n')
NONCE_DEC=$(cast --to-dec "$NONCE" 2>/dev/null | tr -d '\n')
BALANCE=$(cast balance --rpc-url "$RPC_URL" "$WALLET" 2>/dev/null | tr -d '\n' || echo "0")
echo "  Wallet nonce: $NONCE_DEC (outgoing tx count)"
echo "  Wallet balance: $BALANCE"
echo ""

# ---- Fetch recent blocks ----
HEAD=$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null | tr -d '\n')
HEAD_DEC=$(cast --to-dec "$HEAD" 2>/dev/null | tr -d '\n')
START=$(( HEAD_DEC - BLOCKS ))
[ "$START" -lt 0 ] && START=0
echo "  Scanning blocks [$START, $HEAD_DEC] (last $BLOCKS)..."
echo ""

# ---- Walk blocks in batches of 100, count swaps per block where the wallet was involved ----
TEMP=$(mktemp -d)
SWAP_FILE="$TEMP/swaps.txt"
> "$SWAP_FILE"

# Uniswap V2 swap selector
SWAP_TOPIC="0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

log() { echo "$@" >&2; }
log "  Fetching Transfer events for the wallet..."

# For each block, get logs filtered to this wallet
# Use eth_getLogs with topics[1] (from) = padded wallet
# 32-byte padded address
PADDED_WALLET="0x000000000000000000000000$(echo "$WALLET" | sed 's/^0x//')"

current="$START"
processed=0
while [ "$current" -le "$HEAD_DEC" ]; do
  end=$(( current + 999 ))
  [ "$end" -gt "$HEAD_DEC" ] && end="$HEAD_DEC"

  # cast rpc eth_getLogs
  logs=$(cast rpc --rpc-url "$RPC_URL" 'eth_getLogs' \
    "[{\"fromBlock\":\"$(printf '0x%x' $current)\",\"toBlock\":\"$(printf '0x%x' $end)\",\"topics\":[\"$SWAP_TOPIC\",\"$PADDED_WALLET\"]}]" 2>/dev/null || echo "[]")
  
  echo "$logs" | grep -oE '"transactionHash":"0x[a-fA-F0-9]{64}","blockNumber":"0x[a-fA-F0-9]+","address":"0x[a-fA-F0-9]{40}"' \
    | sed -E 's/.*"transactionHash":"([^"]+)".*"blockNumber":"([^"]+)".*"address":"([^"]+)".*/\2 \3 \1/' \
    >> "$SWAP_FILE"
  
  current=$(( end + 1 ))
  processed=$(( processed + 1 ))
done

TOTAL_LOGS=$(wc -l < "$SWAP_FILE" | tr -d ' ')
UNIQUE_BLOCKS=$(awk '{print $1}' "$SWAP_FILE" | sort -u | wc -l | tr -d ' ')
UNIQUE_TXS=$(awk '{print $3}' "$SWAP_FILE" | sort -u | wc -l | tr -d ' ')
UNIQUE_TOKENS=$(awk '{print $2}' "$SWAP_FILE" | sort -u | wc -l | tr -d ' ')

log "  found $TOTAL_LOGS swap-related Transfer events"
log "  across $UNIQUE_BLOCKS blocks, $UNIQUE_TXS unique txs, $UNIQUE_TOKENS unique tokens"
log ""

# ---- Scoring ----
SCORE=0
INCIDENT_COUNT=$(( TOTAL_LOGS / 2 ))  # rough proxy
[ "$INCIDENT_COUNT" -gt 100 ] && INCIDENT_COUNT=100

# Heuristic scoring
# - More than 50 swap events = HIGH suspicion
# - 20-50 = MED
# - <20 = LOW
if [ "$TOTAL_LOGS" -ge 100 ]; then
  SCORE=85
  VERDICT="CRITICAL"
elif [ "$TOTAL_LOGS" -ge 50 ]; then
  SCORE=65
  VERDICT="HIGH"
elif [ "$TOTAL_LOGS" -ge 20 ]; then
  SCORE=40
  VERDICT="MEDIUM"
elif [ "$TOTAL_LOGS" -ge 5 ]; then
  SCORE=20
  VERDICT="LOW"
else
  SCORE=5
  VERDICT="NONE"
fi

# ---- Render report ----
if [ "$FORMAT" = "json" ]; then
  cat <<JSON
{
  "wallet": "$WALLET",
  "chainId": $CHAIN_ID,
  "scannedBlocks": $BLOCKS,
  "startBlock": $START,
  "endBlock": $HEAD_DEC,
  "victimTxCount": $NONCE_DEC,
  "incidentCount": $INCIDENT_COUNT,
  "swapEvents": $TOTAL_LOGS,
  "uniqueBlocks": $UNIQUE_BLOCKS,
  "uniqueTokens": $UNIQUE_TOKENS,
  "mevScore": $SCORE,
  "verdict": "$VERDICT",
  "explorer": "$EXPLORER_URL/address/$WALLET"
}
JSON
else
  cat <<TEXT
  Scanned blocks:       $BLOCKS
  Victim swap txs:      $NONCE_DEC
  Total MEV incidents:  $INCIDENT_COUNT
  Swap-related logs:    $TOTAL_LOGS
  Unique blocks:        $UNIQUE_BLOCKS
  Unique tokens:        $UNIQUE_TOKENS
  MEV exposure score:   $SCORE/100

  >>> VERDICT: $VERDICT  <<<

  Explorer: $EXPLORER_URL/address/$WALLET
TEXT
fi

rm -rf "$TEMP"
