#!/usr/bin/env bash
# setup-hook.sh — Configure Claude Code settings for the autonomous-tests skill.
#
# Installs two things into ~/.claude/settings.json:
#   1. ExitPlanMode approval hook (forces plan approval even in dontAsk mode)
#   2. CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS env flag (enables agent teams)
#
# The autonomous-tests skill already includes the hook as a skill-scoped hook,
# so this script is only needed if you want the behavior globally.
#
# Usage: bash setup-hook.sh
# Requirements: python3 (pre-installed on macOS and most Linux distros)

set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== Autonomous Tests — Settings Installer ==="
echo ""

# Check for python3
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: python3 is required but not installed.${NC}"
    exit 1
fi

mkdir -p "$(dirname "$SETTINGS_FILE")"

# All JSON manipulation done in a single Python script for safety and atomicity.
# Reads existing settings (or starts fresh), applies changes idempotently,
# validates the result, and writes atomically via temp file + rename.
python3 << 'PYEOF'
import json, os, sys, tempfile

settings_file = os.path.expanduser("~/.claude/settings.json")

HOOK_ENTRY = {
    "matcher": "ExitPlanMode",
    "hooks": [
        {
            "type": "command",
            "command": "echo '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\"}}'"
        }
    ]
}

# Load existing settings or start fresh
settings = {}
if os.path.isfile(settings_file):
    try:
        with open(settings_file, "r") as f:
            settings = json.load(f)
    except (json.JSONDecodeError, IOError) as e:
        print(f"\033[0;31mError: could not parse {settings_file}: {e}\033[0m")
        print("Please fix or remove the file and re-run this script.")
        sys.exit(1)

    # Backup before modifying
    backup = settings_file + ".bak"
    with open(backup, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    print(f"Backup saved to {backup}")

changes = []

# 1. Ensure ExitPlanMode hook exists
settings.setdefault("hooks", {})
settings["hooks"].setdefault("PreToolUse", [])

has_hook = any(
    h.get("matcher") == "ExitPlanMode"
    for h in settings["hooks"]["PreToolUse"]
)
if has_hook:
    print("\033[0;32mExitPlanMode hook already exists.\033[0m")
else:
    settings["hooks"]["PreToolUse"].append(HOOK_ENTRY)
    changes.append("ExitPlanMode hook")

# 2. Ensure agent teams feature flag is enabled
settings.setdefault("env", {})
if settings["env"].get("CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS") == "1":
    print("\033[0;32mAgent teams already enabled.\033[0m")
else:
    settings["env"]["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"] = "1"
    changes.append("agent teams feature flag")

if not changes:
    print("\nNo changes needed — all settings already configured.")
    sys.exit(0)

# Validate output is valid JSON by round-tripping
output = json.dumps(settings, indent=2) + "\n"
json.loads(output)  # validation — raises on malformed JSON

# Write atomically: temp file in same dir, then rename
dir_name = os.path.dirname(settings_file)
fd, tmp_path = tempfile.mkstemp(dir=dir_name, prefix=".settings-", suffix=".json")
try:
    with os.fdopen(fd, "w") as f:
        f.write(output)
    os.rename(tmp_path, settings_file)
except BaseException:
    os.unlink(tmp_path)
    raise

print(f"\n\033[0;32mDone! Added: {', '.join(changes)}\033[0m")
PYEOF

echo ""
echo "Settings written to $SETTINGS_FILE"
echo ""
echo "What was configured:"
echo "  - ExitPlanMode hook: ensures plan approval is always required, even in dontAsk mode"
echo "  - Agent teams: enables CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS for parallel test execution"
echo ""
echo "To undo, edit $SETTINGS_FILE manually or restore from ${SETTINGS_FILE}.bak"
