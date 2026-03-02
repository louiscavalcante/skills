# autonomous-tests

Project-agnostic autonomous E2E test runner for Claude Code.

Analyzes your code changes, generates a test plan for your approval, then executes end-to-end tests in parallel using Agent Teams — all against your local stack. Produces structured markdown reports and cleans up after itself.

## What It Does

- **Analyzes git diffs** to identify features, endpoints, and database operations touched
- **Traces dependency graphs** across files and related projects to understand blast radius
- **Generates a test plan** covering happy paths, edge cases, race conditions, security, and more — with mandatory human approval before execution
- **Executes test suites in parallel** via Agent Teams (one agent per suite)
- **Produces structured markdown reports**: test results, pending fixes, guided tests, and queued autonomous tests
- **Cleans up test data** using a configurable prefix, verifying a clean state before finishing

## Prerequisites

| Requirement | Purpose | Check |
|---|---|---|
| Claude Code CLI | Runtime | `claude --version` |
| python3 | Config hashing, validation | `python3 --version` |
| Docker + Compose | Service orchestration (typical) | `docker --version` |
| git | Diff analysis | `git --version` |
| Agent Teams flag | Parallel test execution | Setup script handles this |

## Installation

### Quick Install

```bash
npx skills add louiscavalcante/skills --skill autonomous-tests
```

Then run the setup script to configure required settings:

```bash
bash ~/.claude/skills/louiscavalcante-skills/autonomous-tests/scripts/setup-hook.sh
```

The setup script configures two things in `~/.claude/settings.json`:
1. **ExitPlanMode hook** — forces plan approval even in `dontAsk` mode
2. **Agent Teams flag** — enables `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` for parallel execution

### Manual Install

If you prefer not to use [skills.sh](https://skills.sh/):

1. Clone the repo and copy the `autonomous-tests/` directory into your Claude Code skills directory
2. Enable Agent Teams — add to `~/.claude/settings.json`:
   ```json
   {
     "env": {
       "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
     }
   }
   ```
3. (Optional) Add the global ExitPlanMode hook — add to `~/.claude/settings.json` under `hooks.PreToolUse`:
   ```json
   {
     "matcher": "ExitPlanMode",
     "hooks": [{
       "type": "command",
       "command": "echo '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\"}}'"
     }]
   }
   ```
   The skill already includes this as a skill-scoped hook, so the global version is optional.

## Quick Start

1. **Install the skill** and run the setup script (see above)
2. **Navigate to your project** that has code changes (staged, unstaged, or recent commits)
3. **Invoke the skill**:
   ```
   /autonomous-tests
   ```
4. **Answer first-run questions** — the skill auto-detects your project topology, services, and database, then asks about flaky areas, test credentials, and priorities
5. **Review the proposed config** and approve it
6. **Review the test plan** — the skill enters plan mode and waits for your approval before running anything
7. **Tests execute** via Agent Teams, one agent per suite
8. **Find results** in `docs/_autonomous/` (or your configured output paths)

## Usage

```
/autonomous-tests [argument]
```

| Argument | Meaning |
|---|---|
| _(empty)_ | Default: working-tree (staged + unstaged) with smart doc analysis |
| `staged` | Staged changes only |
| `unstaged` | Unstaged changes only |
| `N` (number) | Last N commits (e.g., `1` = last commit, `3` = last 3) |
| `working-tree` | Staged + unstaged changes (same as default) |

Smart doc analysis is always active — the skill identifies which `docs/` files are relevant to changed code and reads only those.

## Configuration

On first run, the skill creates `.claude/autonomous-tests.json` in your project root. It auto-detects most settings and asks you to confirm.

| Section | What It Contains |
|---|---|
| `project` | Root path, name, topology, services with start/health/log commands |
| `relatedProjects` | Sibling repos that are part of the same system |
| `database` | Type, connection command, test DB name |
| `externalServices` | Third-party integrations with sandbox checks and production indicators |
| `testing` | Unit test command, test data prefix, context files |
| `documentation` | Output paths for each report type |
| `userContext` | Flaky areas, test credentials, priorities, notes |

See [`references/config-schema.json`](references/config-schema.json) for the full schema.

### Credential Safety

Always use environment variable references for credentials — never raw secrets:

```json
"testCredentials": {
  "admin": "$ADMIN_TEST_PASSWORD",
  "member": "$MEMBER_TEST_PASSWORD"
}
```

Never do this:

```json
"testCredentials": {
  "admin": "actualPassword123"
}
```

The skill redacts credential values when displaying configs for review.

### Config Trust Store

Configs are verified against a trust store at `~/.claude/trusted-configs/`. When a config is created or approved, its hash is saved outside the repo. If the config is modified (e.g., by a commit from another contributor), you'll be prompted to re-approve before tests run. This prevents a malicious config from bypassing approval.

## Output

The skill generates up to four document types in `docs/_autonomous/`:

| Document | When Generated | Location |
|---|---|---|
| Test Results | Always | `test-results/` |
| Pending Fixes | When bugs or infra issues are found | `pending-fixes/` |
| Guided Tests | When tests need browser/visual/physical interaction | `pending-guided-tests/` |
| Pending Autonomous Tests | When automatable tests were deferred | `pending-autonomous-tests/` |

Files follow the naming pattern: `{YYYY-MM-DD-HH-MM-SS}_{feature-name}.md`

See [`references/templates.md`](references/templates.md) for exact output formats.

## How It Works

```
Phase 0: Config    → Setup or validate project configuration
Phase 1: Safety    → Block if production indicators found
Phase 2: Startup   → Health-check and start services
Phase 3: Discovery → Analyze diff, trace dependencies
Phase 4: Plan      → Generate test plan (you approve this)
Phase 5: Execute   → Agent Teams run suites in parallel
Phase 6: Fix       → Auto-fix runtime issues, document bugs
Phase 7: Docs      → Generate markdown reports
Phase 8: Cleanup   → Remove test data, verify clean state
```

- **Phase 0** loads your config or walks you through first-run setup. Returning runs validate the config and check trust.
- **Phase 1** scans `.env` files for production indicators (`sk_live_`, `NODE_ENV=production`, etc.) and aborts if any are found.
- **Phase 2** health-checks each service and starts any that are down, including related projects.
- **Phase 3** reads every changed file, builds a feature map (endpoints, DB ops, auth flows), and traces the full dependency graph across project boundaries.
- **Phase 4** enters plan mode with test suites covering happy paths, validation, idempotency, error handling, race conditions, security, and edge cases. You approve before anything executes.
- **Phase 5** spawns one Agent Team member per suite. Each agent gets the full feature context and a distinct test credential to avoid session conflicts.
- **Phase 6** auto-fixes runtime issues (env vars, containers) up to 3 times. Code bugs are documented and shown to you.
- **Phase 7** generates timestamped markdown reports from templates.
- **Phase 8** removes test data by prefix, verifies cleanup with DB queries, and logs every action.

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| "Agent teams not enabled" | Missing feature flag | Run `bash scripts/setup-hook.sh` |
| Config validation fails | Schema version mismatch | Delete `.claude/autonomous-tests.json`, re-run |
| Services won't start | Docker not running | Check `docker info` |
| Tests fail with auth errors | Shared credentials between agents | Add distinct test users per agent in config |
| Trust verification fails | Config modified externally | Re-approve when prompted |

### Resetting Configuration

To start fresh, delete the config and its trust store entry:

```bash
# Remove project config
rm .claude/autonomous-tests.json

# Remove trust entry (find your project hash first)
python3 -c "import hashlib,os;print(hashlib.sha256(os.path.realpath('.').encode()).hexdigest()[:16])"
# Then delete ~/.claude/trusted-configs/{hash}.sha256
```

The next `/autonomous-tests` run will re-trigger first-run setup.

## Project Structure

```
autonomous-tests/
├── README.md               ← You are here
├── SKILL.md                ← Claude-facing skill definition
├── references/
│   ├── config-schema.json  ← Config file schema
│   └── templates.md        ← Output document templates
└── scripts/
    └── setup-hook.sh       ← Settings installer
```
