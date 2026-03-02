#!/usr/bin/env bash
# run-all.sh — Run all skill-triggering tests
#
# Usage: bash tests/skill-triggering/run-all.sh
#
# Iterates all prompt files in prompts/, runs run-test.sh for each,
# and reports a pass/fail summary.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPTS_DIR="$SCRIPT_DIR/prompts"
RUN_TEST="$SCRIPT_DIR/run-test.sh"

PASS=0
FAIL=0
TOTAL=0
FAILURES=()

echo "=== Skill Triggering Tests ==="
echo ""

for prompt_file in "$PROMPTS_DIR"/*.txt; do
  [[ -f "$prompt_file" ]] || continue
  TOTAL=$((TOTAL + 1))

  if bash "$RUN_TEST" "$prompt_file"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAILURES+=("$(basename "$prompt_file" .txt)")
  fi
done

echo ""
echo "=== Results ==="
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"

if [[ $FAIL -gt 0 ]]; then
  echo ""
  echo "Failed tests:"
  for f in "${FAILURES[@]}"; do
    echo "  - $f"
  done
  exit 1
fi

echo "All tests passed."
exit 0
