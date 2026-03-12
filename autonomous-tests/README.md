# autonomous-tests

Project-agnostic autonomous test runner for Claude Code.

Analyzes your code changes (and optional doc file references), auto-detects available testing tools, learns from previous test runs, generates a test plan for your approval, then executes integration tests (curl), E2E tests (browser), and regression tests (unit) sequentially using subagents — all against your local stack. Produces structured markdown reports and cleans up after itself.

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
- **Three test types** — integration tests (curl-based API testing), E2E tests (browser-based via agent-browser/Playwright), and regression tests (unit tests run once at end)
- **Chrome DevTools MCP integration** — monitors network issues, console errors, and DOM state during E2E browser tests
- **Service log monitoring** — captures and analyzes service logs during all test phases, checks for errors between suites
- **Project type auto-detection** — detects mobile, webapp, or API-only projects to generate appropriate test types
- **17-item security observation checklist** — comprehensive security analysis applied to each test suite
- **Guided mode** — test existing features without code changes via `guided "description"` or `guided file:<path>`
- **Accepts `.md` doc references** as additional test context via `file:<path>`
- **Auto-detects capabilities** — Docker MCPs, agent-browser, Playwright, chrome-devtools-mcp, external service CLIs — and caches them
- **Learns from past runs** by scanning `_autonomous/` history for related test results and known issues
- **Traces dependency graphs** across files and related projects to understand blast radius
- **Generates a test plan** covering happy paths, edge cases, race conditions, security, and more — with mandatory human approval before execution
- **Executes test suites sequentially** via subagents with capability-aware agents (one at a time)
- **Produces structured markdown reports**: test results, pending fixes, guided tests, and queued autonomous tests
- **Cleans up test data** using a configurable prefix, verifying a clean state before finishing

## Prerequisites

| Requirement | Purpose | Check |
|---|---|---|
| Claude Code CLI | Runtime | `claude --version` |
| python3 | Config hashing, validation | `python3 --version` |
| Docker + Compose | Service orchestration (typical) | `docker --version` |
| git | Diff analysis | `git --version` |

## Installation

### Quick Install

```bash
npx skills add louiscavalcante/skills --skill autonomous-tests
```

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

The skill enters plan mode with a full test plan — review it and approve before anything executes. Tests run sequentially via subagents (one agent at a time), and results land in `docs/_autonomous/`.

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
| `guided` | Feature/workflow-centric mode — prompts to pick a doc or describe a feature |
| `guided "description"` | Test a feature by description — happy path + security only |
| `guided file:<path>` | Test a feature from a spec doc — full 9-category coverage |

> **Note:** The default scope (`working-tree`) requires staged or unstaged changes to exist. If your working tree is clean, the skill will stop and ask you to either specify a commit range (e.g., `/autonomous-tests 3` for the last 3 commits) or make changes first.

Arguments are combinable. Examples:
```
/autonomous-tests staged file:docs/payments.md
/autonomous-tests 3 rescan
/autonomous-tests file:docs/feature-spec.md rescan
/autonomous-tests guided "payment checkout flow"
/autonomous-tests guided file:docs/payments.md
/autonomous-tests guided rescan
```

Smart doc analysis is always active in standard mode — the skill identifies which `docs/` files are relevant to changed code and reads only those.

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
| `capabilities` | Auto-detected testing tools (Docker MCPs, agent-browser, Playwright, external service CLIs) |

See [`references/config-schema.json`](references/config-schema.json) for the full schema (v6).

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
| External service CLIs | Sandbox only — blocked on production keys, per-run confirmation, catalog-defined allowlist |
| System commands | Explicit allowlist — only read-only/idempotent commands beyond user config |
| External downloads | Docker images from user's compose files only — no arbitrary downloads |
| Data access | `settings.json` and `.env` for safety checks only — values never logged or output |
| Trust boundaries | Untrusted inputs (diffs, docs) gated by mandatory plan approval before execution |

### Capabilities Detection

The skill auto-detects available testing tools and caches results in the `capabilities` config section. No manual configuration needed.

| Capability | How Detected | How Used | Safety |
|---|---|---|---|
| Docker MCPs | `mcp-find` search | Agents `mcp-add` safe MCPs at runtime for relevant tests | Only `safe: true` MCPs are activated |
| agent-browser | `which agent-browser` | E2E browser-based user flow testing | Read-only by default |
| chrome-devtools-mcp | `mcp-find` + settings scan | Network/console/DOM monitoring during E2E tests | Read-only |
| Playwright | `which playwright` / `npx playwright --version` | E2E fallback when agent-browser unavailable | Local only |
| External Service CLIs | Catalog-based detection + CLAUDE.md scanning | Per catalog `allowedOperations` | **Blocked if production keys detected** |

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

### Guided Mode

Use `guided` to test existing features or workflows without needing code changes. This bypasses git diff analysis and instead traces a described feature through the codebase.

| Sub-mode | Trigger | Test Coverage |
|---|---|---|
| Doc-based | `guided file:docs/spec.md` or pick from `docs/`/`_autonomous/pending-guided-tests/` when prompted | Full 9-category coverage |
| Description-based | `guided "payment checkout flow"` or describe when prompted | Happy path + security analysis |

**How it works:**
- `guided` alone prompts you to pick a doc or describe a feature
- `guided "description"` uses the description to search the codebase for related files, endpoints, models, and services
- `guided file:<path>` reads the spec doc and extracts features, endpoints, and acceptance criteria

**Combinability:**
- Combinable with `rescan`: `/autonomous-tests guided rescan`
- **NOT** combinable with `staged`, `unstaged`, `N`, or `working-tree` — guided mode bypasses git diff analysis

**Examples:**
```
/autonomous-tests guided
/autonomous-tests guided "user registration and onboarding"
/autonomous-tests guided file:docs/payments-feature.md
/autonomous-tests guided file:docs/_autonomous/pending-guided-tests/checkout-flow.md rescan
```

### Targeted Regression Mode

When re-running after `autonomous-fixes` has applied fixes (fix-results with `Ready for Re-test: YES`), the skill automatically activates **regression mode**. Instead of re-testing the entire feature blast radius, it:

1. Reads the fix manifest (files modified, what was done, original test IDs)
2. Computes a 1-hop impact zone (direct callers/callees of modified files only)
3. Cross-references prior test results to identify what already passed
4. Generates only 2 targeted suites: **Fix Verification** (re-run the exact failing scenarios) and **Impact Zone** (test direct dependencies for side-effects)

Previously validated areas unaffected by the fix are excluded, significantly reducing token usage on re-test runs. If the fix's blast radius exceeds 60% of the feature map (e.g., a core utility was changed), the skill falls back to full-scope testing automatically.

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
Phase 3: Discovery  ← Analyze diff (or guided feature), file refs, history
Phase 4: Plan       ← Generate test plan (you approve)
Phase 5: Execute    ← subagents run suites sequentially
Phase 6: Fix        ← Auto-fix runtime issues, document bugs
Phase 7: Docs       ← Generate markdown reports
Phase 8: Cleanup    ← Remove test data, verify clean state
Phase 9: Advisory   ← Remind user to /clear before next skill
```

- **Phase 0** loads your config or walks you through first-run setup. Scans for available capabilities (Docker MCPs, agent-browser, Playwright, external service CLIs) and caches results. Returning runs validate the config, check trust, and refresh stale capabilities.
- **Phase 1** scans `.env` files for production indicators (`sk_live_`, `NODE_ENV=production`, etc.) and aborts if any are found.
- **Phase 2** health-checks each service and starts any that are down, including related projects.
- **Phase 3** reads every changed file (or traces a guided feature through the codebase), processes `file:<path>` references if provided, builds a feature map (endpoints, DB ops, auth flows), traces the full dependency graph across project boundaries, and scans `_autonomous/` folders for prior test history related to current changes.
- **Phase 4** enters plan mode with test suites covering happy paths, validation, idempotency, error handling, race conditions, security, and edge cases. You approve before anything executes.
- **Phase 5** executes one suite at a time: spawns a subagent, assigns it a suite, waits for completion, shuts it down, then spawns the next. Each agent gets the full feature context (including prior history and available capabilities) and an assigned test credential role. Sequential execution prevents credential conflicts and log cross-contamination. Integration tests use curl, E2E tests use agent-browser (primary) or Playwright (fallback) with chrome-devtools-mcp monitoring, and unit tests run once at the end as regression. Agents leverage detected capabilities — safe Docker MCPs and external service CLIs when not blocked.
- **Phase 6** auto-fixes runtime issues (env vars, containers) up to 3 times. Code bugs are documented and shown to you.
- **Phase 7** generates timestamped markdown reports from templates.
- **Phase 8** removes test data by prefix, verifies cleanup with DB queries, and logs every action.
- **Phase 9** displays a context reset advisory reminding you to run `/clear` before invoking another skill.

[Back to top](#autonomous-tests)

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| "Working tree is clean" | No staged/unstaged changes with default scope | Use `/autonomous-tests N` for last N commits, or make changes first |
| Config validation fails | Schema version mismatch | Delete `.claude/autonomous-tests.json`, re-run |
| Services won't start | Docker not running | Check `docker info` |
| Tests fail with auth errors | Credential misconfiguration | Verify test credentials in config reference valid env vars |
| Trust verification fails | Config modified externally | Re-approve when prompted |
| "External service CLI blocked" | Production keys detected | Switch to sandbox/test keys for the affected service |
| Capabilities seem stale | Cache older than threshold | Run `/autonomous-tests rescan` to force re-scan |
| "File reference not found" | `file:<path>` points to missing file | Check path is relative to project root and file exists |
| "guided cannot be combined with git-scope args" | `guided` used with `staged`/`unstaged`/`N`/`working-tree` | Use `guided` alone or with `rescan` only — guided bypasses git diffs |

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
└── references/
    ├── config-schema.json  ← Config file schema
    └── templates.md        ← Output document templates
```
