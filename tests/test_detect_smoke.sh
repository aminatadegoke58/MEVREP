#!/bin/bash
set -e
SCRIPT="scripts/detect.sh"
bash "$SCRIPT" --help >/dev/null
if bash "$SCRIPT" 2>&1 | grep -q "wallet required\|--demo"; then
  echo "OK: no-args shows usage"
else
  echo "FAIL: no-args"; exit 1
fi
if ! command -v cast >/dev/null 2>&1; then
  if bash "$SCRIPT" --wallet 0xabc 2>&1 | grep -q "cast.*not found"; then
    echo "OK: cast-missing error clear"
  else
    echo "FAIL: cast-missing error unclear"; exit 1
  fi
fi
echo "All smoke tests passed."
