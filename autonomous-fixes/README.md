# autonomous-fixes

Project-agnostic autonomous fix runner for Claude Code.

Reads findings from `autonomous-tests` output (bugs, failed tests, security vulnerabilities), lets you select what to fix, plans and executes fixes via subagents, verifies results, and updates documentation so `autonomous-tests` can re-test — creating a bidirectional test-fix loop.

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
- [Vulnerability Handling](#vulnerability-handling)
- [The Test-Fix Loop](#the-test-fix-loop)
- [Troubleshooting](#troubleshooting)
- [Project Structure](#project-structure)

## Token Usage

> **Note:** This skill is **token-intensive by design**. It uses **Claude Opus 4.6** — the most advanced model available — for both the main orchestrator and every spawned agent teammate. Opus has adaptive reasoning/thinking built-in that scales with problem complexity, which means fix agents reason deeply about root causes, security implications, and cross-file dependencies. The tradeoff is higher token consumption per run compared to skills that use lighter models.

## What It Does

- **Parses findings** from `autonomous-tests` output (pending-fixes, test-results, fix-results) — supports integration test, E2E test, and regression test findings
- **Categorizes findings** into Vulnerabilities (V-prefix), Bugs (F-prefix), Failed Tests (T-prefix), and Informational (G/A)
- **17-item security checklist awareness** — V-prefix fixes reference the security observation checklist for comprehensive remediation
- **Service log monitoring awareness** — incorporates log-based findings from test results
- **Presents findings** for user selection — always prompts even in dontAsk/bypass mode
- **Supports pre-selection** via arguments: `vulnerability`, `critical`, `high`, `all`, `file:<path>`
- **Plans fixes** in plan mode with mandatory human approval
- **Executes fixes** via subagents with security-aware remediation for vulnerability items
- **Verifies results** including security-specific checks (variant payloads, auth bypass, data leakage)
- **Updates documentation** with resolution blocks, fix-results, and test-results annotations
- **Signals re-test readiness** so `autonomous-tests` can verify fixes on next run

## Prerequisites

| Requirement | Purpose | Check |
|---|---|---|
| Claude Code CLI | Runtime | `claude --version` |
| python3 | Config hashing, validation | `python3 --version` |
| autonomous-tests config | Project setup + findings | `.claude/autonomous-tests.json` must exist |
| Test findings | Something to fix | `docs/_autonomous/` must contain findings |

## Installation

### Quick Install

```bash
npx skills add louiscavalcante/skills --skill autonomous-fixes
```

### Verify Installation

Run `/autonomous-fixes` in a project that has `autonomous-tests` findings in `docs/_autonomous/`.

## Quick Start

### 1. Run autonomous-tests first

Generate findings by running `/autonomous-tests` on your project. This creates the config and findings in `docs/_autonomous/`.

### 2. Fix findings

```
/autonomous-fixes
```

### 3. Select items

Choose which findings to fix from the interactive selection prompt. Or use arguments to pre-select:

```
/autonomous-fixes vulnerability    # Fix all security findings
/autonomous-fixes critical         # Fix critical-severity items
/autonomous-fixes all              # Fix everything
```

### 4. Review & Execute

The skill enters plan mode with a fix plan — review and approve before anything executes. Fixes run via subagents, and results land in `docs/_autonomous/fix-results/`.

### 5. Re-test

After fixes are applied, re-run autonomous-tests to verify:

```
/autonomous-tests
```

[Back to top](#autonomous-fixes)

## Usage

```
/autonomous-fixes [argument]
```

| Argument | Meaning |
|---|---|
| _(empty)_ | Default: interactive selection via prompt |
| `all` | Select all fixable items (V, F, T prefixes) |
| `critical` | Pre-select items with Severity = Critical |
| `high` | Pre-select items with Severity = Critical or High |
| `vulnerability` | Pre-select all security/vulnerability items (V-prefix) |
| `file:<path>` | Target a specific pending-fixes or test-results file |

Examples:
```
/autonomous-fixes vulnerability
/autonomous-fixes critical
/autonomous-fixes file:docs/_autonomous/pending-fixes/2026-03-01-14-30-00_payments-fixes.md
```

[Back to top](#autonomous-fixes)

## Configuration

This skill reuses `.claude/autonomous-tests.json` — no separate configuration needed. It adds one field if missing:

| Field | Default | Purpose |
|---|---|---|
| `documentation.fixResults` | `docs/_autonomous/fix-results` | Output path for fix-results documents |

See the [autonomous-tests configuration docs](../autonomous-tests/README.md#configuration) for full config details (v6).

[Back to top](#autonomous-fixes)

## Output

The skill generates and updates documents in `docs/_autonomous/`:

| Document | When Generated | Location |
|---|---|---|
| Fix Results | Always | `fix-results/` |
| Resolution Blocks | When fixing pending-fixes items | Appended to existing pending-fixes docs |
| Test-Results Updates | When fixing failed tests | Appended to existing test-results docs |

Files follow the naming pattern: `{YYYY-MM-DD-HH-MM-SS}_{feature-name}-fix-results.md`

See [`references/templates.md`](references/templates.md) for exact output formats.

[Back to top](#autonomous-fixes)

## How It Works

```
Phase 0: Bootstrap    ← Validate config, scan for findings, tool inventory
Phase 1: Selection    ← Parse findings, present for user selection
Phase 2: Plan         ← Read source code, design fixes (you approve)
Phase 3: Execution    ← Subagents apply fixes sequentially
Phase 4: Results      ← 4a: Verify | 4b: Document | 4c: Loop signal + cleanup
```

- **Phase 0** validates the shared config (version 6 required), scans available tools (skills, agents, MCPs, CLIs), and scans `_autonomous/` directories for findings. If previously applied fixes are detected in the working tree (via git diff), the skill skips directly to Phase 4 (verification and documentation).
- **Phase 1** parses all findings, assigns IDs (V/F/T/G/A prefixes), deduplicates, and presents for selection. No source code is read until after selection.
- **Phase 2** reads source code for selected items, traces code paths, performs dependency analysis, and designs fixes. Vulnerability items get enhanced context with full input-output tracing, regulatory assessment, and security-aware remediation design.
- **Phase 3** spawns subagents to execute fixes. Fixes run strictly sequentially — one subagent at a time.
- **Phase 4a** verifies each fix. V-prefix items get additional security verification with variant payloads and hardening checks.
- **Phase 4b** generates fix-results document, appends resolution blocks to pending-fixes, and annotates test-results.
- **Phase 4c** summarizes results, signals re-test readiness, offers to remove fully-resolved source documents (fix-results are never removed — they're the permanent record), and displays a `/clear` reminder.

[Back to top](#autonomous-fixes)

## Vulnerability Handling

Security findings receive special treatment throughout the fix lifecycle:

### V-prefix Assignment

Items are assigned V-prefix when:
- Category is `Security Gap`, `Data Leak`, or `Privacy Violation`
- They appear in the `### Vulnerabilities` subsection of test-results
- They appear in the `### API Response Security` subsection of test-results
- They contain security-related keywords (injection, XSS, CSRF, auth bypass, etc.)

### OWASP Categorization

Each vulnerability is mapped to an OWASP Top 10 category (e.g., A03:2021 - Injection).

### Multi-Regulation Compliance

Regulatory impact is assessed against:
- **LGPD** (Brazil) — all personal data of Brazilian data subjects
- **GDPR** (EU) — personal data of EU residents
- **CCPA/CPRA** (California) — personal information of California consumers
- **HIPAA** (US) — protected health information

### Security Verification

V-prefix fixes are verified with:
- Original attack vector re-testing (must be blocked)
- Variant payload testing (encoding bypasses, alternative injection strings)
- Auth bypass and privilege escalation checks
- Error response hardening verification
- Sensitive data removal confirmation
- Rate limiting verification (if applicable)

### Priority Ranking

Unresolved security items are ranked by risk:
1. Data leaks
2. Credential exposure
3. Privilege escalation
4. Denial-of-service risks
5. Compliance violations

[Back to top](#autonomous-fixes)

## The Test-Fix Loop

```
┌──────────────────┐         ┌──────────────────┐
│ autonomous-tests │ ──────> │ autonomous-fixes  │
│                  │         │                   │
│  Generates:      │         │  Reads:           │
│  - test-results  │         │  - pending-fixes  │
│  - pending-fixes │         │  - test-results   │
│  - guided-tests  │         │                   │
│  - auto-tests    │         │  Writes:          │
│                  │         │  - fix-results    │
│  Reads:          │         │  - Resolution     │
│  - fix-results   │ <────── │    blocks         │
│  - Resolution    │         │  - Test-results   │
│    blocks        │         │    annotations    │
└──────────────────┘         └──────────────────┘
```

1. Run `/autonomous-tests` → generates findings in `docs/_autonomous/`
2. Run `/autonomous-fixes` → reads findings, applies fixes, writes fix-results + resolution blocks
3. Run `/autonomous-tests` again → reads fix-results (`Ready for Re-test: YES`) and resolution blocks (`RESOLVED + PASS`), prioritizes re-testing fixed items as regression targets

The loop continues until all findings are resolved or marked as needing manual intervention.

[Back to top](#autonomous-fixes)

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| "No autonomous-tests config found" | Haven't run autonomous-tests yet | Run `/autonomous-tests` first |
| "No findings to fix" | No pending-fixes or test failures | Run `/autonomous-tests` to generate findings |
| Config validation fails | Schema version mismatch | Delete `.claude/autonomous-tests.json`, re-run `/autonomous-tests` |
| Trust verification fails | Config modified externally | Re-approve when prompted |
| Fix marked UNABLE | Autonomous fix not possible | Review the item manually |

[Back to top](#autonomous-fixes)

## Project Structure

```
autonomous-fixes/
├── README.md               ← You are here
├── SKILL.md                ← Claude-facing skill definition
└── references/
    ├── finding-parser.md   ← Parsing rules for _autonomous/ documents
    └── templates.md        ← Output document templates
```
