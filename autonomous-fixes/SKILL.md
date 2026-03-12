---
name: autonomous-fixes
description: 'Fix findings from autonomous-tests. Args: all | critical | high | vulnerability
  | file:<path> (default: interactive selection). Example: /autonomous-fixes vulnerability'
argument-hint: 'all | critical | high | vulnerability | file:<path>'
disable-model-invocation: true
allowed-tools: Bash(*), Read(*), Write(*), Edit(*), Glob(*), Grep(*), Agent(*),
  EnterPlanMode(*), ExitPlanMode(*), AskUserQuestion(*)
---

## Dynamic Context

- Args: $ARGUMENTS
- Branch: !`git branch --show-current`
- Config: !`test -f .claude/autonomous-tests.json && echo "YES" || echo "NO — requires autonomous-tests config"`
- Pending fixes: !`find docs/_autonomous/pending-fixes -name '*.md' 2>/dev/null | wc -l | tr -d ' '`
- Fix results: !`find docs/_autonomous/fix-results -name '*.md' 2>/dev/null | wc -l | tr -d ' '`
- Test results: !`find docs/_autonomous/test-results -name '*.md' 2>/dev/null | wc -l | tr -d ' '`

## Role

Project-agnostic autonomous fix runner. Reads findings from `autonomous-tests` output, lets the user select items to fix, plans and executes fixes via subagents, verifies results, and updates documentation to enable re-testing — creating a bidirectional test-fix loop.

## Orchestrator Protocol

The main agent is the Orchestrator. It coordinates phases but NEVER executes operational work.

**Orchestrator MUST delegate to agents:**
- Bash commands (capabilities scan, health checks, port scanning, cleanup)
- Source code reading (only agents read application source)
- File generation (docs, reports)
- Test execution, fix application, verification

**Orchestrator MAY directly:**
- Read config, SKILL.md, and reference files
- Run `date -u` for timestamps, `test -f` for file checks
- Enter/exit plan mode
- Use AskUserQuestion for user interaction
- Use Agent() to spawn subagents for delegation
- Compile summaries from agent reports
- Make phase-gating decisions (proceed/stop/abort)

**Reporting hierarchy:** Agent → Orchestrator → Plan

## Arguments: $ARGUMENTS

| Arg | Meaning |
|---|---|
| _(empty)_ | Default: interactive selection via AskUserQuestion |
| `all` | Select all fixable items (V, F, T prefixes) |
| `critical` | Pre-select items with Severity = Critical |
| `high` | Pre-select items with Severity = Critical or High |
| `vulnerability` | Pre-select all security/vulnerability items (V-prefix) |
| `file:<path>` | Target a specific pending-fixes or test-results file |

Print resolved scope, then proceed without waiting.

---

## Phase 0 — Bootstrap

**Config hash method**: `python3 -c "import json,hashlib;d=json.load(open('.claude/autonomous-tests.json'));[d.pop(k,None) for k in ('_configHash','lastRun','capabilities')];print(hashlib.sha256(json.dumps(d,sort_keys=True).encode()).hexdigest())"`

**Step 1 — Config Validation**: This skill reuses `.claude/autonomous-tests.json`.
1. `test -f .claude/autonomous-tests.json` → if missing, **STOP**: "Run `/autonomous-tests` first."
2. Read config. Validate `version` equals `6`. If `version` < `6` -> **STOP**: "Config is v{version}. Run `/autonomous-tests` first to auto-migrate to v6."
3. Verify config trust: compute hash via **Config hash method**, check against `~/.claude/trusted-configs/`. If untrusted → show config (redact `testCredentials` and credential-sensitive command fields: `database.connectionCommand`, `database.seedCommand`, `database.cleanupCommand`, `database.migrationCommand`, `testing.unitTestCommand`, `project.services[].startCommand`, `relatedProjects[].startCommand`, `sandbox.sandboxCheck`, `sandbox.webhookListener` — show command structure but replace passwords/tokens/connection strings with `<REDACTED>`), confirm via `AskUserQuestion`.
4. Ensure `documentation.fixResults` exists → if missing, add `"fixResults": "docs/_autonomous/fix-results"`, save.
5. **Extract log file paths**: Collect log file paths from `project.services[].logFile` and log commands from `relatedProjects[].logCommand` (these are config values — extract regardless of service status). Store as **Log Path Inventory** for Phase 3 fix agents.
6. If config modified in step 4 or 5 → re-stamp trust using **Config hash method**.

**Step 2 — CLAUDE.md Deep Scan**: Delegate to Explore agent. Scan CLAUDE.md files up to 3 levels deep, plus `~/.claude/CLAUDE.md` and `.claude/CLAUDE.md`. Return discovered file list. Cache for Phase 2.

**Step 2.5 — Tool Inventory** — ALWAYS runs (no caching — tools change between sessions):

- **Orchestrator directly** (no agent spawn needed):
  1. **Skills**: Extract available skills from system-reminder context (name, trigger description)
  2. **Agents**: Extract available agent types from Agent tool description (type, capabilities summary)
- **Delegate to Explore agent** (combine with Step 3 findings scan, or spawn separately):
  3. **MCP servers**: Run `mcp-find` for available MCPs + scan `~/.claude/settings.json` for `mcpServers` key
  4. **CLIs**: Probe common tools (`which curl`, `which jq`, `which ngrok`, `which uvx`) + external service CLIs from config
- **Compile Tool Inventory**: Structured inventory with per-phase recommendations:
  - Phase 1 (Findings): document parsing tools
  - Phase 2 (Plan): skills and agents available for fix execution
  - Phase 3 (Execution): service-specific MCPs, CLI tools, DB tools, testing tools
  - Phase 4 (Results): documentation tools, verification tools

**Step 3 — Findings Scan**: Delegate to Explore agent. Scan configured `_autonomous/` directories (`documentation.pendingFixes`, `documentation.testResults`, `documentation.fixResults`). Report: pending-fixes count, test-results with `### Requires Fix` or `### Vulnerabilities`, prior fix-results. If no actionable findings → **STOP**: "No findings. Run `/autonomous-tests` first."

**Step 4 — Resume Detection**: Delegate to agent. Run `git diff --name-only` and cross-reference modified files against finding source files from Step 3. If fixes appear already applied (modified files overlap with files referenced in findings):
- Print: "Fixes detected in working tree. Skipping to Phase 4 (Verification & Documentation)."
- Execute ALL Phase 4 substeps (4a → 4b → 4c) — no shortcuts.

---

## Phase 1 — Findings (User Selection Gate)

Delegate document parsing to Explore agent. Agent parses all `_autonomous/` documents per `references/finding-parser.md` rules, returns structured findings:

1. **Vulnerabilities** (V-prefix): Category = `Security Gap`/`Data Leak`/`Privacy Violation` or from `### Vulnerabilities`/`### API Response Security`. Each includes: OWASP category, Severity, Regulatory impact (LGPD/GDPR/CCPA/HIPAA), Exploitability, Compliance risk.
2. **Bugs** (F-prefix): Pending-fixes, non-security categories.
3. **Failed Tests** (T-prefix): Test-results `### Requires Fix`.
4. **Informational**: Guided (G) and autonomous (A) — counts only, not selectable.

Orchestrator receives findings, applies pre-selection: `all` → V+F+T | `critical` → Severity=Critical | `high` → Critical+High | `vulnerability` → V-prefix | `file:<path>` → specified file only. No argument → present via `AskUserQuestion`.

Do NOT read any source code during this phase. Source reading happens in Phase 2.

---

## Phase 2 — Plan

**Enter plan mode (Use /plan).**

**Step 0 — Context Reload** (for post-approval reconstruction): Re-read SKILL.md, config, templates. Record: resolved arguments (`$ARGUMENTS`), branch, selected items (IDs, titles, sources), key finding context, user notes.

**Self-containment mandate** — the plan MUST embed directly (not reference "above" or prior phases):
1. All selected items (ID, title, source file, severity, category, OWASP for V-prefix)
2. Fix Context Documents — condensed per item (root cause, affected files, code path, fix design)
3. Concrete per-item agent spawn instructions (source paths, fix steps, verification commands, expected outcomes)
4. Full Phase 3/4 instructions with resolved values — no "see above"
5. Config key references (NOT resolved values): `documentation.fixResults`, `documentation.pendingFixes`, `documentation.testResults`, `database.connectionCommand`, `testing.unitTestCommand` — fix agents read resolved values from config file at runtime. Never embed resolved command strings containing credentials into plan text.
6. CLAUDE.md file list from Phase 0 Step 2
7. Tool Inventory from Phase 0 — full inventory with per-phase recommendations so fix agents know which tools are available without re-scanning.
8. DB Consistency Check Protocol (POST_FIX section only) from `autonomous-tests/references/db-consistency-protocol.md` — embedded verbatim so fix agents execute inline checks without needing the reference file post-reset.
9. Log Path Inventory from Phase 0 Step 5 — service log file paths and related project log commands so fix agents can check logs after fix verification.
10. Security checklist items (from `../autonomous-tests/references/security-checklist.md`) applicable to V-prefix items — embed only the subset of items the vulnerability violates and the fix must satisfy (typically 2-5 of 17, not the full list) so fix agents verify security compliance without needing the reference file post-reset.
11. Service startup config references for all project + relatedProject services (service names + config key paths, e.g. `project.services[0].startCommand`) — fix agents read resolved commands from config at runtime. Never embed resolved command strings in plan text.

- Execution Protocol (embed verbatim — orchestrator uses this after context reset):
  ```
  SETUP: Spawn general-purpose subagent (foreground). Reads source files referenced by findings, compiles Fix Context Documents, reads CLAUDE.md files, returns results.
  TOOL CONTEXT: Fix agents receive relevant Tool Inventory subset (service MCPs, CLI tools, DB tools, testing tools) in their prompts.
  LOG CONTEXT: Fix agents receive Log Path Inventory (service log files, related project log commands) and service startup commands.
  SECURITY CONTEXT: V-prefix fix agents receive applicable security checklist items (from 17-item checklist) embedded in their Fix Context Document.
  DB CONSISTENCY: Fix agents that modify DB-interacting code capture pre-fix record counts, then run POST_FIX check after fix application. Non-DB fixes skip this step.
  FLOW: STRICTLY SEQUENTIAL — one subagent at a time:
    1. For each selected item (in order):
       a. Spawn ONE general-purpose subagent (foreground)
       b. Provide in prompt: Fix Context Document, source paths, fix instructions, verification steps
       c. BLOCK — foreground = automatic blocking
       d. Receive results directly
       e. Next item
  PROHIBITED: multiple concurrent subagents, parallel execution, main-conversation fixes
  ```

- Post-Fix Checklist (embed verbatim in every plan):
  ```
  ## Post-Fix Checklist
  1. [ ] 4a: Verification agent confirms tests pass
  2. [ ] 4a: DB consistency POST_FIX check passed (if applicable)
  3. [ ] 4b: Fix-results doc created at `documentation.fixResults`
  3. [ ] 4b: Resolution blocks appended to pending-fixes
  4. [ ] 4b: Test-results updated for T-prefix items (if applicable)
  5. [ ] 4c: Loop signal printed
  6. [ ] 4c: Source cleanup eligibility checked -> AskUserQuestion if all resolved
  7. [ ] 4c: Unresolved V-prefix warnings printed (if applicable)
  8. [ ] 4c: `/clear` reminder printed
  ```

**Setup agent** (MANDATORY): Spawn setup subagent (general-purpose, foreground) to read all source files referenced by findings, compile Fix Context Documents, read discovered CLAUDE.md files for architecture context, return results. **Orchestrator MUST embed the setup agent's Fix Context Documents into the plan text** — condensed for token efficiency but complete enough for post-reset reconstruction.

**Fix Context Document per item**:
1. **Verify finding is real and still reproduces** (MANDATORY gate — do NOT skip): Re-read the source code at the reported location. Check if the code has changed since the finding was reported. Run the failing scenario or check the vulnerable path. If code changed and issue gone → `Status: ALREADY_RESOLVED`, exclude from plan. If the finding was based on a misunderstanding of the code logic (reported code path is unreachable, vulnerability requires conditions prevented by upstream middleware, or behavior is by design per CLAUDE.md/inline comments) → `Status: FALSE_POSITIVE`, exclude from plan. Report excluded items to Orchestrator with status and reason — do not generate Fix Context Documents for them. Only proceed to fix design after confirming the issue genuinely exists and requires intervention.
2. Read referenced files (endpoint, model, test) — record file paths
3. Trace code path: input → processing → output — summarize path
4. Identify root cause — state explicitly
5. Design fix — concrete steps with file:line references

**V-prefix enhanced context**: Trace full I/O path for affected handler. Identify ALL user-controlled inputs reaching vulnerable code. Check related patterns in same file/module. Assess regulatory exposure. Design security-aware remediation: DTO filtering, validation/sanitization layers, rate limiting, protective guards. Read `../autonomous-tests/references/security-checklist.md` (17-item checklist) and embed the items relevant to each V-prefix finding into its Fix Context Document — highlight which items the vulnerability violates and which the fix must satisfy.

Execution is **STRICTLY SEQUENTIAL** — one agent at a time.

**Wait for user approval.**

---

## Phase 3 — Execution

Spawn general-purpose subagents sequentially (foreground). For each selected item (in order):
1. Spawn ONE general-purpose subagent (foreground)
2. Provide in prompt: Fix Context Document, source paths, fix instructions, verification steps, config file path and service config key references (so agent reads startup commands and log paths from config at runtime — never embed resolved command strings in prompts), Log Path Inventory from Phase 0. For V-prefix items: include applicable security checklist items from `../autonomous-tests/references/security-checklist.md` (the items the vulnerability violates and the fix must satisfy).
3. BLOCK — foreground = automatic blocking
4. Receive results directly
5. Next item

**Standard fix agent instructions**:
1. Read Fix Context Document → re-read source at reported location
2. **Double-check**: Verify the issue still exists in the current code before writing any fix. If the code has changed or the issue no longer reproduces → report `ALREADY_RESOLVED` without modifying files
3. Implement fix targeting root cause
4. Run unit tests if configured (`testing.unitTestCommand`)
5. Verify with targeted checks (API calls, DB queries, log inspection)
6. **Log check**: After fix verification, check log files from Log Path Inventory for new errors or warnings introduced by the fix. If service requires restart, use startup commands from config.
7. **DB consistency: POST_FIX** — if fix touched DB-interacting code, capture pre-fix record counts, apply fix, then verify no unintended writes, schema intact, no orphans introduced. Skip for non-DB fixes.
8. Report: RESOLVED / PARTIAL / UNABLE with details (include log check results)
9. Record `Original Test IDs` from source finding's `Test ID` field into fix-results documentation

**V-prefix additional instructions**:
1. Enforce DTO/serializer filtering — remove sensitive data from responses
2. Add input validation/sanitization at boundary
3. Rate limiting, file size validation, content-type validation where applicable
4. Circuit breakers for external service interactions
5. Harden error responses (no stack traces, internal metadata, debug info)
6. Verify no new attack vectors introduced
7. Check same pattern in related files/endpoints
8. Test with variant attack payloads
9. **Security checklist verification**: Confirm all applicable security checklist items (from Fix Context Document) are satisfied by the fix. Report per-item pass/fail in results.

Never fix in main conversation — always delegate.

---

## Phase 4 — Results & Docs

Verify fixes, generate documentation, offer source cleanup.

### 4a. Verification

Delegate to general-purpose subagent (foreground).

**Standard**: confirm modified files, run unit tests, re-execute failing scenario. If fix modified DB-interacting code, verify POST_FIX check passed. Include result in fix-results.

**V-prefix**: re-test original attack vector (must block), test variant payloads, verify no auth bypass/privilege escalation, verify hardened error responses, verify sensitive data removal, check rate limiting.

Mark each: **RESOLVED** (root cause fixed, all verification passes) / **PARTIAL** (symptom mitigated but root cause remains or side effects exist) / **UNABLE** (requires architectural changes, missing access, or manual intervention beyond agent capability).

### 4b. Documentation

Delegate to general-purpose subagent (foreground). Timestamp via `date -u +"%Y-%m-%d-%H-%M-%S"`. Read `references/templates.md`.

- **Fix-results**: always generated at `documentation.fixResults` path (metadata, per-item results, next steps)
- **Resolution blocks**: append `### Resolution` to pending-fixes entries
- **Test-results updates**: append fix-applied status to T-prefix entries
- **V-prefix**: include `### Security Impact` (OWASP, attack vector, regulatory impact, mitigation, related patterns, residual risk)

### 4c. Loop Signal & Finalize

Print fix cycle summary:
```
## Fix Cycle Complete
- Items attempted: {N} | Resolved: {N} | Partial: {N} | Unable: {N}
Re-run autonomous-tests to verify: `/autonomous-tests`
```

If `Ready for Re-test: YES` → inform user re-testing will be prioritized.

**Source Document Cleanup**: Check resolution status per source document:
- Pending-fixes: every `## Fix N:` has `### Resolution` with `Status: RESOLVED` + `Verification: PASS`
- Test-results `### Requires Fix`: every entry has fix-applied annotation
- Test-results `### Vulnerabilities`/`### API Response Security`: every entry `Status: RESOLVED`

All resolved → offer removal via `AskUserQuestion` ("Fix-results preserved as permanent record"). Any unresolved → keep, inform user. Never remove fix-results.

**Vulnerability warning** (unresolved V-prefix):
```
WARNING: UNRESOLVED SECURITY FINDINGS — manual attention required:
1. Data leaks — {V-prefix items}
2. Credential exposure — {V-prefix items}
3. Privilege escalation — {V-prefix items}
4. Denial-of-service — {V-prefix items}
5. Compliance violations — {V-prefix items}
```

> **Important**: Run `/clear` before invoking another skill to free context tokens and prevent stale state.

Phase 4c is the LAST step. There is no Phase 5.

---

## Rules

- No production data/connections; no credentials in plan text, subagent prompts, or documentation output
- **Credential-sensitive config fields**: `database.connectionCommand`, `database.seedCommand`, `database.cleanupCommand`, `database.migrationCommand`, `testing.unitTestCommand`, `project.services[].startCommand`, `relatedProjects[].startCommand`, `sandbox.sandboxCheck`, `sandbox.webhookListener`. Embed config key paths only; agents read resolved values from config at runtime. Redact passwords/tokens/connection strings on display.
- **No dynamic commands**: only execute verbatim commands from config fields — no generation, concatenation, or interpolation of command strings at runtime
- Plan mode before execution (Phase 2)
- Delegate via subagents — never fix in main conversation; all execution via Agent(subagent_type: "general-purpose")
- Model inheritance — subagents inherit from main conversation, ensure Opus is set
- **STRICTLY SEQUENTIAL** — one agent at a time, block until shutdown before next
- Present findings before source reading (Phase 1 before Phase 2)
- Security fixes address root causes, not symptoms
- UTC timestamps via `date -u` — never guess
- Reuse `.claude/autonomous-tests.json` — no separate config
- No Docker MCPs where `safe: false`
- V-prefix: always enhanced context + verification + documentation
- Documentation (4b) is NOT the end — 4c (loop signal + cleanup + finalize) is MANDATORY. Never stop after generating docs.
