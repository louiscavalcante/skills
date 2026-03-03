# autonomous-fixes

Project-agnostic autonomous fix runner for Claude Code.

Reads findings from `autonomous-tests` output (bugs, failed tests, security vulnerabilities), lets you select what to fix, plans and executes fixes via Agent Teams, verifies results, and updates documentation so `autonomous-tests` can re-test — creating a bidirectional test-fix loop.

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

- **Parses findings** from `autonomous-tests` output (pending-fixes, test-results, fix-results)
- **Categorizes findings** into Vulnerabilities (V-prefix), Bugs (F-prefix), Failed Tests (T-prefix), and Informational (G/A)
- **Presents findings** for user selection — always prompts even in dontAsk/bypass mode
- **Supports pre-selection** via arguments: `vulnerability`, `critical`, `high`, `all`, `file:<path>`
- **Plans fixes** in plan mode with mandatory human approval
- **Executes fixes** via Agent Teams with security-aware remediation for vulnerability items
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
| Agent Teams flag | Parallel fix execution | Setup script handles this |

## Installation

### Quick Install

```bash
npx skills add louiscavalcante/skills --skill autonomous-fixes
```

Then run the setup script to configure required settings:

```bash
bash ~/.claude/skills/louiscavalcante-skills/autonomous-fixes/scripts/setup-hook.sh
```

The setup script configures four things in `~/.claude/settings.json`:
1. **ExitPlanMode hook** — forces plan approval even in `dontAsk` mode
2. **AskUserQuestion hook** — forces user selection prompt even in `dontAsk`/bypass mode
3. **Agent Teams flag** — enables `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` for parallel execution
4. **Model** — sets `claude-opus-4-6` as the default model

### Manual Install

If you prefer not to use [skills.sh](https://skills.sh/):

1. Clone the repo and copy the `autonomous-fixes/` directory into your Claude Code skills directory
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

The skill enters plan mode with a fix plan — review and approve before anything executes. Fixes run via Agent Teams, and results land in `docs/_autonomous/fix-results/`.

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

See the [autonomous-tests configuration docs](../autonomous-tests/README.md#configuration) for full config details.

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
Phase 0: Config       ← Validate autonomous-tests config, scan for findings
Phase 1: Selection    ← Parse findings, present for user selection
Phase 2: Plan         ← Read source code, design fixes (you approve)
Phase 3: Execute      ← Agent Teams apply fixes
Phase 4: Verify       ← Confirm fixes work, security checks for V-prefix
Phase 5: Document     ← Generate fix-results, update pending-fixes/test-results
Phase 6: Loop Signal  ← Signal readiness for re-testing
Phase 7: Doc Cleanup  ← Offer removal of fully-resolved source docs
Phase 8: Advisory     ← Remind user to /clear before next skill
```

- **Phase 0** validates the shared config and scans `_autonomous/` directories for findings.
- **Phase 1** parses all findings, assigns IDs (V/F/T/G/A prefixes), deduplicates, and presents for selection. No source code is read until after selection.
- **Phase 2** reads source code for selected items, traces code paths, performs dependency analysis, and designs fixes. Vulnerability items get enhanced context with full input-output tracing, regulatory assessment, and security-aware remediation design.
- **Phase 3** spawns Agent Teams to execute fixes. Independent items run in parallel; dependent chains run sequentially.
- **Phase 4** verifies each fix. V-prefix items get additional security verification with variant payloads and hardening checks.
- **Phase 5** generates fix-results document, appends resolution blocks to pending-fixes, and annotates test-results.
- **Phase 6** summarizes results and signals re-test readiness for the autonomous-tests loop.
- **Phase 7** offers to remove source documents (pending-fixes, test-results) when all their findings are fully resolved. Fix-results are never removed — they're the permanent record.
- **Phase 8** displays a context reset advisory reminding you to run `/clear` before invoking another skill.

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
| "Agent teams not enabled" | Missing feature flag | Run `bash scripts/setup-hook.sh` |
| Config validation fails | Schema version mismatch | Delete `.claude/autonomous-tests.json`, re-run `/autonomous-tests` |
| Trust verification fails | Config modified externally | Re-approve when prompted |
| Fix marked UNABLE | Autonomous fix not possible | Review the item manually |

[Back to top](#autonomous-fixes)

## Project Structure

```
autonomous-fixes/
├── README.md               ← You are here
├── SKILL.md                ← Claude-facing skill definition
├── references/
│   ├── finding-parser.md   ← Parsing rules for _autonomous/ documents
│   └── templates.md        ← Output document templates
└── scripts/
    └── setup-hook.sh       ← Settings installer
```
