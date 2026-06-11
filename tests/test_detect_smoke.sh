#!/usr/bin/env bash
# MEVREP smoke test — verifies the bash + cast skill is wired up correctly.
#
# This test is designed to run on a fresh clone with only `bash` and
# (optionally) `cast` / `jq` on PATH. It does NOT need network access
# (the --demo path is fully offline).
#
# Run:  bash tests/test_detect_smoke.sh
# Exit: 0 on success, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="$SCRIPT_DIR/../scripts/detect.sh"

PASS=0
FAIL=0

ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

# Sanity: detect.sh exists
if [ ! -f "$DETECT" ]; then
  echo "FATAL: $DETECT not found"
  exit 1
fi
ok "scripts/detect.sh exists"

# Test 1: --help
echo "Test 1: --help"
if bash "$DETECT" --help | grep -q "MEVREP"; then
  ok "--help prints banner"
else
  fail "--help does not print banner"
fi

# Test 2: no args
echo "Test 2: no args (should error cleanly)"
out="$(bash "$DETECT" 2>&1 || true)"
if echo "$out" | grep -q "wallet required"; then
  ok "no-args error mentions --wallet"
else
  fail "no-args error message unclear"
fi
if echo "$out" | grep -q "Usage:"; then
  ok "no-args shows usage banner"
else
  fail "no-args does not show usage"
fi

# Test 3: --demo works offline
echo "Test 3: --demo (offline)"
out="$(bash "$DETECT" --demo 2>&1)"
if [ $? -eq 0 ]; then
  ok "--demo exits 0"
else
  fail "--demo non-zero exit"
fi
if echo "$out" | grep -q "VERDICT:"; then
  ok "--demo prints VERDICT"
else
  fail "--demo does not print VERDICT"
fi
if echo "$out" | grep -q "MEV exposure score:"; then
  ok "--demo prints score"
else
  fail "--demo does not print score"
fi

# Test 4: --demo --format json
echo "Test 4: --demo --format json"
out="$(bash "$DETECT" --demo --format json 2>&1)"
if echo "$out" | grep -q '"verdict"'; then
  ok "--format json includes verdict"
else
  fail "--format json missing verdict"
fi
if echo "$out" | grep -q '"mevScore"'; then
  ok "--format json includes mevScore"
else
  fail "--format json missing mevScore"
fi
if echo "$out" | grep -q '"wallet"'; then
  ok "--format json includes wallet"
else
  fail "--format json missing wallet"
fi

# Test 5: --demo --format markdown
echo "Test 5: --demo --format markdown"
out="$(bash "$DETECT" --demo --format markdown 2>&1)"
if echo "$out" | grep -q "^# MEV Exposure Report"; then
  ok "--format markdown starts with H1"
else
  fail "--format markdown missing H1"
fi
if echo "$out" | grep -q "## Verdict"; then
  ok "--format markdown has Verdict section"
else
  fail "--format markdown missing Verdict"
fi

# Test 6: invalid wallet
echo "Test 6: invalid wallet"
out="$(bash "$DETECT" --wallet nothex 2>&1 || true)"
if echo "$out" | grep -q "40-hex address"; then
  ok "invalid-wallet error is clear"
else
  fail "invalid-wallet error unclear"
fi

# Test 7: invalid --blocks
echo "Test 7: invalid --blocks"
out="$(bash "$DETECT" --wallet 0x67992af9a87f2d6a3062c333d8a06abbe3929438 --blocks -1 2>&1 || true)"
if echo "$out" | grep -q "positive integer"; then
  ok "negative --blocks rejected"
else
  fail "negative --blocks not rejected"
fi

out="$(bash "$DETECT" --wallet 0x67992af9a87f2d6a3062c333d8a06abbe3929438 --blocks 999999 2>&1 || true)"
if echo "$out" | grep -q "capped at 50000"; then
  ok "huge --blocks rejected"
else
  fail "huge --blocks not rejected"
fi

# Test 8: invalid --format
echo "Test 8: invalid --format"
out="$(bash "$DETECT" --wallet 0x67992af9a87f2d6a3062c333d8a06abbe3929438 --format xml 2>&1 || true)"
if echo "$out" | grep -q "must be text|json|markdown"; then
  ok "bad --format rejected"
else
  fail "bad --format not rejected"
fi

# Test 9: invalid --chain
echo "Test 9: invalid --chain"
out="$(bash "$DETECT" --wallet 0x67992af9a87f2d6a3062c333d8a06abbe3929438 --chain arbitrum 2>&1 || true)"
if echo "$out" | grep -qE "must be one of:|mainnet\|testnet"; then
  ok "bad --chain rejected"
else
  fail "bad --chain not rejected"
fi

# Test 10: unknown flag
echo "Test 10: unknown flag"
out="$(bash "$DETECT" --foo 2>&1 || true)"
if echo "$out" | grep -q "Unknown arg"; then
  ok "unknown flag rejected"
else
  fail "unknown flag not rejected"
fi

# Test 11: cast-missing (only checked when cast is NOT installed)
echo "Test 11: cast-missing error (when cast not on PATH)"
if ! command -v cast >/dev/null 2>&1; then
  out="$(bash "$DETECT" --wallet 0x67992af9a87f2d6a3062c333d8a06abbe3929438 --blocks 100 2>&1 || true)"
  if echo "$out" | grep -q "cast.*not found\|'cast' not found"; then
    ok "cast-missing error is clear"
  else
    fail "cast-missing error unclear"
  fi
else
  ok "cast is on PATH, skipping cast-missing check"
fi

# Test 12: live RPC path (only when cast is installed)
echo "Test 12: live RPC path (when cast is installed)"
if command -v cast >/dev/null 2>&1; then
  out="$(bash "$DETECT" --wallet 0x67992af9a87f2d6a3062c333d8a06abbe3929438 --blocks 50 2>&1)"
  if [ $? -eq 0 ]; then
    ok "live RPC scan exits 0"
  else
    fail "live RPC scan non-zero exit"
  fi
  if echo "$out" | grep -q "VERDICT:"; then
    ok "live RPC scan prints VERDICT"
  else
    fail "live RPC scan does not print VERDICT"
  fi
else
  ok "cast missing, skipping live RPC test"
fi

# Test 13: --chain testnet resolves to atlantic-testnet
echo "Test 13: --chain testnet"
out="$(bash "$DETECT" --demo --chain testnet 2>&1)"
if echo "$out" | grep -q "atlantic-testnet"; then
  ok "--chain testnet resolves correctly"
else
  fail "--chain testnet does not resolve to atlantic-testnet"
fi

# Test 14: --chain mainnet resolves to mainnet
echo "Test 14: --chain mainnet"
out="$(bash "$DETECT" --demo --chain mainnet 2>&1)"
if echo "$out" | grep -q "(chainId 1672)"; then
  ok "--chain mainnet resolves to chainId 1672"
else
  fail "--chain mainnet does not resolve to chainId 1672"
fi

# Test 15: --format json output is parseable (no banner pollution on stdout)
echo "Test 15: --format json stdout is clean JSON"
stdout_only="$(bash "$DETECT" --demo --format json 2>/dev/null)"
if command -v jq >/dev/null 2>&1; then
  if echo "$stdout_only" | jq . >/dev/null 2>&1; then
    ok "--format json stdout parses with jq"
  else
    fail "--format json stdout does NOT parse with jq (banner leaking?)"
  fi
else
  if echo "$stdout_only" | grep -qE '^\{'; then
    ok "--format json stdout starts with { (jq not available to verify deeper)"
  else
    fail "--format json stdout does not start with {"
  fi
fi

# Test 16: --format markdown stdout is clean markdown (no banner)
echo "Test 16: --format markdown stdout is clean markdown"
stdout_only="$(bash "$DETECT" --demo --format markdown 2>/dev/null)"
if echo "$stdout_only" | head -1 | grep -q "^# MEV Exposure Report"; then
  ok "--format markdown stdout starts with H1"
else
  fail "--format markdown stdout does not start with H1 (banner leaking?)"
fi

# Test 17: cast-missing branch (only when cast is NOT installed)
echo "Test 17: cast-missing branch (when cast not on PATH) — already covered by Test 11"

# Test 18: progress lines go to stderr (not stdout)
echo "Test 18: progress goes to stderr"
stdout_only="$(bash "$DETECT" --demo 2>/dev/null)"
stderr_only="$(bash "$DETECT" --demo 2>&1 >/dev/null)"
# In demo mode, the report IS on stdout
if echo "$stdout_only" | grep -q "VERDICT:"; then
  ok "demo stdout contains VERDICT"
else
  fail "demo stdout missing VERDICT"
fi
# Stderr should also contain the banner (we send everything to log)
if echo "$stderr_only" | grep -q "MEV EXPOSURE REPORT"; then
  ok "demo stderr contains banner"
else
  fail "demo stderr missing banner"
fi

# ---- Summary ----
echo ""
echo "================================================================"
echo "  Smoke test results: $PASS passed, $FAIL failed"
echo "================================================================"

[ "$FAIL" -eq 0 ]
