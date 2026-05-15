#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
shopt -s nullglob

failed=0
for f in tests/*_test.lua; do
  echo "--- $f ---"
  if ! nvim --headless -u NONE \
       --cmd "set rtp+=$(pwd)" \
       -l "$f"; then
    failed=$((failed + 1))
  fi
done

if [ "$failed" -gt 0 ]; then
  echo "FAILED: $failed test file(s)"
  exit 1
fi
echo "ALL TESTS PASSED"
