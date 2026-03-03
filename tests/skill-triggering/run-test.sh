#!/usr/bin/env bash
# run-test.sh — Run a single skill-triggering test
#
# Usage: bash run-test.sh <prompt-file>
#
# Sends the prompt to Claude Code with the appropriate skill loaded,
# then checks if the skill was triggered in the output.
#
# Skill detection: prompt filenames containing "fix" target autonomous-fixes,
# filenames containing "swarm" target autonomous-tests-swarm,
# all others target autonomous-tests.

set -euo pipefail

PROMPT_FILE="${1:?Usage: bash run-test.sh <prompt-file>}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROMPT_NAME="$(basename "$PROMPT_FILE" .txt)"

if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "FAIL: Prompt file not found: $PROMPT_FILE"
  exit 1
fi

# Determine which skill to test based on prompt filename
if [[ "$PROMPT_NAME" == *fix* ]]; then
  SKILL_DIR="$REPO_ROOT/autonomous-fixes"
  EXPECTED_SKILL="autonomous-fixes"
elif [[ "$PROMPT_NAME" == *swarm* ]]; then
  SKILL_DIR="$REPO_ROOT/autonomous-tests-swarm"
  EXPECTED_SKILL="autonomous-tests-swarm"
else
  SKILL_DIR="$REPO_ROOT/autonomous-tests"
  EXPECTED_SKILL="autonomous-tests"
fi

PROMPT="$(cat "$PROMPT_FILE")"

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
