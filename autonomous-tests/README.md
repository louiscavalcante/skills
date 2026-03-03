# autonomous-tests

Project-agnostic autonomous E2E test runner for Claude Code.

Analyzes your code changes (and optional doc file references), auto-detects available testing tools, learns from previous test runs, generates a test plan for your approval, then executes end-to-end tests in parallel using Agent Teams — all against your local stack. Produces structured markdown reports and cleans up after itself.

## Table of Contents

- [Token Usage](#token-usage)
- [What It Does](#what-it-does)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Configuration](#configuration)
- [Output](#output)
- [How It Works](#how-it-works)
- [Troubleshooting](#troubleshooting)
- [Project Structure](#project-structure)

## Token Usage

> **Note:** This skill is **token-intensive by design**. It uses **Claude Opus 4.6** — the most advanced model available — for both the main orchestrator and every spawned agent teammate. Opus has adaptive reasoning/thinking built-in that scales with problem complexity, which means test agents think as deeply as needed to catch subtle bugs, race conditions, and edge cases. The tradeoff is higher token consumption per run compared to skills that use lighter models. Each test suite spawns a dedicated Opus agent, so runs with many suites will consume tokens proportionally.

## What It Does

- **Analyzes git diffs** to identify features, endpoints, and database operations touched
- **Accepts `.md` doc references** as additional test context via `file:<path>`
- **Auto-detects capabilities** — Docker MCPs, agent-browser, Playwright, Stripe CLI — and caches them
- **Learns from past runs** by scanning `_autonomous/` history for related test results and known issues
- **Traces dependency graphs** across files and related projects to understand blast radius
- **Generates a test plan** covering happy paths, edge cases, race conditions, security, and more — with mandatory human approval before execution
- **Executes test suites in parallel** via Agent Teams with capability-aware agents (one agent per suite)
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

The setup script configures four things in `~/.claude/settings.json`:
1. **ExitPlanMode hook** — forces plan approval even in `dontAsk` mode
2. **AskUserQuestion hook** — forces user prompts even in `dontAsk`/bypass mode
3. **Agent Teams flag** — enables `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` for parallel execution
4. **Model** — sets `claude-opus-4-6` as the default model (required for agent team reasoning capabilities)

### Manual Install

If you prefer not to use [skills.sh](https://skills.sh/):

1. Clone the repo and copy the `autonomous-tests/` directory into your Claude Code skills directory
2. Enable Agent Teams and set the model — add to `~/.claude/settings.json`:
   ```json
   {
     "env": {
       "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
     },
     "model": "claude-opus-4-6"
   }
   ```
3. (Optional) Add the global hooks — add to `~/.claude/settings.json` under `hooks.PreToolUse`:
   ```json
   [
     {
       "matcher": "ExitPlanMode",
       "hooks": [{
         "type": "command",
         "command": "echo '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\"}}'"
       }]
     },
     {
       "matcher": "AskUserQuestion",
       "hooks": [{
         "type": "command",
         "command": "echo '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\"}}'"
       }]
     }
   ]
   ```
   The skill already includes these as skill-scoped hooks, so the global version is optional.

### Verify Installation

Run `/autonomous-tests` in any project with code changes. The skill will walk you through first-run configuration.

## Quick Start

### 1. Install & Setup

Install the skill and run the setup script (see [Installation](#installation) above).

### 2. Run the Skill

Navigate to your project that has code changes (staged, unstaged, or recent commits), then invoke:

```
/autonomous-tests
```

### 3. Configure Your Project

On first run, the skill auto-detects your project topology, services, and database, then asks about flaky areas, test credentials, and priorities. Review the proposed config and approve it.

### 4. Review & Execute

The skill enters plan mode with a full test plan — review it and approve before anything executes. Tests run via Agent Teams (one agent per suite), and results land in `docs/_autonomous/`.

[Back to top](#autonomous-tests)

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
| `file:<path>` | Use a `.md` doc as additional test context (path relative to project root) |
| `rescan` | Force re-scan of capabilities regardless of cache |

> **Note:** The default scope (`working-tree`) requires staged or unstaged changes to exist. If your working tree is clean, the skill will stop and ask you to either specify a commit range (e.g., `/autonomous-tests 3` for the last 3 commits) or make changes first.

Arguments are combinable. Examples:
```
/autonomous-tests staged file:docs/payments.md
/autonomous-tests 3 rescan
/autonomous-tests file:docs/feature-spec.md rescan
```

Smart doc analysis is always active — the skill identifies which `docs/` files are relevant to changed code and reads only those.

## Configuration

On first run, the skill creates `.claude/autonomous-tests.json` in your project root. It auto-detects most settings and asks you to confirm.

| Section | What It Contains |
|---|---|
| `project` | Root path, name, topology, services with start/health/log commands |
| `relatedProjects` | Sibling repos that are part of the same system |
| `database` | Type, seed strategy, connection command, test DB name, seed/migration/cleanup commands |
| `externalServices` | Third-party integrations with sandbox checks and production indicators |
| `testing` | Unit test command, test data prefix, context files |
| `documentation` | Output paths for each report type |
| `userContext` | Flaky areas, test credentials, priorities, notes |
| `capabilities` | Auto-detected testing tools (Docker MCPs, agent-browser, Playwright, Stripe CLI) |

See [`references/config-schema.json`](references/config-schema.json) for the full schema.

### Database Seeding

The skill supports two seeding strategies, configured via `database.seedStrategy`:

| Strategy | How It Works | Best For |
|---|---|---|
| `autonomous` (recommended) | Each agent creates the test data it needs for its suite via API calls, direct DB inserts, or application endpoints. Data is prefixed with `testDataPrefix`. | Most projects — isolated, parallel-safe, no shared seed state |
| `command` | Runs `database.seedCommand` globally before tests start. | Projects with complex seed data that must exist before any test runs |

On first run, the skill presents both options and recommends `autonomous`. Existing configs without `seedStrategy` default to `autonomous`.

### Credential Safety

> **Warning:** Always use environment variable references for credentials — never raw secrets.

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

### Security Posture

The skill enforces explicit operational bounds to constrain resource usage and prevent unsafe operations:

| Bound | Limit |
|---|---|
| Max agents | Equal to approved test suites |
| Max fix cycles | 3 per suite |
| Health check timeout | 30 seconds per service |
| Command execution | Only commands from user-approved config — no dynamic shell generation |
| Docker scope | Local containers only — aborts on production indicators |
| Credential handling | Env var references only — raw values forbidden, redacted on display |
| MCP activation | Only `safe: true` MCPs — `safe: false` are never activated |
| Agent lifecycle | One suite per agent — spawned, executes, shut down |

### Capabilities Detection

The skill auto-detects available testing tools and caches results in the `capabilities` config section. No manual configuration needed.

| Capability | How Detected | How Used | Safety |
|---|---|---|---|
| Docker MCPs | `mcp-find` search | Agents `mcp-add` safe MCPs at runtime for relevant tests | Only `safe: true` MCPs are activated |
| agent-browser | `which agent-browser` | UI testing, browser-based verification | Read-only by default |
| Playwright | `which playwright` / `npx playwright --version` | Frontend component and integration tests | Local only |
| Stripe CLI | `which stripe` + `stripe config --list` | Webhook forwarding, payment testing | **Blocked if live keys detected** |

Capabilities are cached with a `lastScanned` timestamp and re-scanned when older than `rescanThresholdDays` (default: 7). Use the `rescan` argument to force a fresh scan:

```
/autonomous-tests rescan
```

### File Reference

Use `file:<path>` to provide a `.md` document as additional test context:

```
/autonomous-tests file:docs/payments-feature.md
```

The file is read during Phase 3 (Discovery) and its content — feature descriptions, acceptance criteria, endpoints, edge cases — is merged with diff-based discovery. This is useful when:
- A spec document describes behavior not yet visible in the diff
- Acceptance criteria from a ticket are captured in a markdown file
- You want to test against a specific feature doc rather than just code changes

The path must be relative to the project root and point to an existing `.md` file.

### Test History

The skill scans your `_autonomous/` output folders for previous test results related to the current changes. It matches filenames (which contain feature names) against the current feature map, then reads only Summary and Issues Found sections from matching docs.

This helps agents by providing:
- **Previously failing tests** — agents know what broke before and can verify fixes
- **Known bugs and pending fixes** — agents avoid re-reporting known issues
- **Guided tests** — if capabilities like agent-browser are now available, previously guided tests may be automatable
- **Queued autonomous tests** — pending tests from earlier runs targeting the same features are picked up

History is fed as "Prior Test History" in the Feature Context Document that every agent receives.

[Back to top](#autonomous-tests)

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

### Re-running Pending Fixes

After fixing a bug documented in `pending-fixes/`, re-test it by targeting the pending-fix doc directly:

```
/autonomous-tests file:docs/_autonomous/pending-fixes/<the-file-name>.md
```

> **Tip:** Run `/clear` first to start with a clean context — this reduces token usage and avoids carrying over stale conversation state.

[Back to top](#autonomous-tests)

## How It Works

```
Phase 0: Config     ← Setup, validate, scan capabilities
Phase 1: Safety     ← Block if production detected
Phase 2: Startup    ← Health-check and start services
Phase 3: Discovery  ← Analyze diff, file refs, history
Phase 4: Plan       ← Generate test plan (you approve)
Phase 5: Execute    ← Agent Teams run suites in parallel
Phase 6: Fix        ← Auto-fix runtime issues, document bugs
Phase 7: Docs       ← Generate markdown reports
Phase 8: Cleanup    ← Remove test data, verify clean state
Phase 9: Advisory   ← Remind user to /clear before next skill
```

- **Phase 0** loads your config or walks you through first-run setup. Scans for available capabilities (Docker MCPs, agent-browser, Playwright, Stripe CLI) and caches results. Returning runs validate the config, check trust, and refresh stale capabilities.
- **Phase 1** scans `.env` files for production indicators (`sk_live_`, `NODE_ENV=production`, etc.) and aborts if any are found.
- **Phase 2** health-checks each service and starts any that are down, including related projects.
- **Phase 3** reads every changed file, processes `file:<path>` references if provided, builds a feature map (endpoints, DB ops, auth flows), traces the full dependency graph across project boundaries, and scans `_autonomous/` folders for prior test history related to current changes.
- **Phase 4** enters plan mode with test suites covering happy paths, validation, idempotency, error handling, race conditions, security, and edge cases. You approve before anything executes.
- **Phase 5** spawns one Agent Team member per suite. Each agent gets the full feature context (including prior history and available capabilities) and a distinct test credential. Agents leverage detected capabilities — agent-browser for UI tests, Playwright for frontend tests, safe Docker MCPs, and Stripe CLI when not blocked.
- **Phase 6** auto-fixes runtime issues (env vars, containers) up to 3 times. Code bugs are documented and shown to you.
- **Phase 7** generates timestamped markdown reports from templates.
- **Phase 8** removes test data by prefix, verifies cleanup with DB queries, and logs every action.
- **Phase 9** displays a context reset advisory reminding you to run `/clear` before invoking another skill.

[Back to top](#autonomous-tests)

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| "Working tree is clean" | No staged/unstaged changes with default scope | Use `/autonomous-tests N` for last N commits, or make changes first |
| "Agent teams not enabled" | Missing feature flag | Run `bash scripts/setup-hook.sh` |
| Config validation fails | Schema version mismatch | Delete `.claude/autonomous-tests.json`, re-run |
| Services won't start | Docker not running | Check `docker info` |
| Tests fail with auth errors | Shared credentials between agents | Add distinct test users per agent in config |
| Trust verification fails | Config modified externally | Re-approve when prompted |
| "Stripe CLI blocked" warning | Live keys detected in Stripe config | Switch to test keys: `stripe config --set test_mode_api_key sk_test_...` |
| Capabilities seem stale | Cache older than threshold | Run `/autonomous-tests rescan` to force re-scan |
| "File reference not found" | `file:<path>` points to missing file | Check path is relative to project root and file exists |

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

[Back to top](#autonomous-tests)

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
