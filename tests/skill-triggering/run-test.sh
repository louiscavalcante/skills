#!/usr/bin/env bash
# run-test.sh — Run a single skill-triggering test
#
# Usage: bash run-test.sh <prompt-file>
#
# Sends the prompt to Claude Code with the autonomous-tests skill loaded,
# then checks if the skill was triggered in the output.

set -euo pipefail

PROMPT_FILE="${1:?Usage: bash run-test.sh <prompt-file>}"
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)/autonomous-tests"
EXPECTED_SKILL="autonomous-tests"

if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "FAIL: Prompt file not found: $PROMPT_FILE"
  exit 1
fi

PROMPT="$(cat "$PROMPT_FILE")"
PROMPT_NAME="$(basename "$PROMPT_FILE" .txt)"

# Run Claude Code in print mode with the skill loaded, capture output
OUTPUT=$(claude --skill-dir "$SKILL_DIR" --print "$PROMPT" 2>&1) || true

# Check if the skill was triggered (look for skill name in output)
if echo "$OUTPUT" | grep -qi "$EXPECTED_SKILL"; then
  echo "PASS: $PROMPT_NAME"
  exit 0
else
  echo "FAIL: $PROMPT_NAME — skill '$EXPECTED_SKILL' not found in output"
  exit 1
fi
