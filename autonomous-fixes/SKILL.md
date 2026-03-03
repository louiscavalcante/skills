---
name: autonomous-fixes
description: 'Fix findings from autonomous-tests. Args: all | critical | high | vulnerability
  | file:<path> (default: interactive selection). Example: /autonomous-fixes vulnerability'
argument-hint: 'all | critical | high | vulnerability | file:<path>'
disable-model-invocation: true
allowed-tools: Bash(*), Read(*), Write(*), Edit(*), Glob(*), Grep(*), Agent(*),
  EnterPlanMode(*), ExitPlanMode(*), TaskCreate(*),
  TaskUpdate(*), TaskList(*), TaskGet(*), TeamCreate(*),
  SendMessage(*), TeamDelete(*), AskUserQuestion(*)
hooks:
  PreToolUse:
    - matcher: ExitPlanMode
      hooks:
        - type: command
          command: "echo '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\"}}'"
    - matcher: AskUserQuestion
      hooks:
        - type: command
          command: "echo '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\"}}'"
---

## Dynamic Context

- Args: $ARGUMENTS
- Branch: !`git branch --show-current`
- Config: !`test -f .claude/autonomous-tests.json && echo "YES" || echo "NO — requires autonomous-tests config"`
- Pending fixes: !`find docs/_autonomous/pending-fixes -name '*.md' 2>/dev/null | wc -l | tr -d ' '`
- Fix results: !`find docs/_autonomous/fix-results -name '*.md' 2>/dev/null | wc -l | tr -d ' '`
- Test results: !`find docs/_autonomous/test-results -name '*.md' 2>/dev/null | wc -l | tr -d ' '`
- Agent Teams: !`python3 -c "import json;s=json.load(open('$HOME/.claude/settings.json'));print('ENABLED' if s.get('env',{}).get('CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS')=='1' else 'DISABLED')" 2>/dev/null || echo "DISABLED — settings not found"`

## Role

Project-agnostic autonomous fix runner. Reads findings from `autonomous-tests` output, lets the user select items to fix, plans and executes fixes via Agent Teams, verifies results, and updates documentation to enable re-testing — creating a bidirectional test-fix loop.

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

## Phase 0 — Configuration

**Step 0: Prerequisites Check**

Read `~/.claude/settings.json` and check two things:

1. **Agent teams feature flag**: verify `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is `"1"`. If missing or not `"1"`, **STOP** and tell the user:
   > Agent teams are required for this skill but not enabled. Run: `bash <skill-dir>/scripts/setup-hook.sh`
   > This enables the `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` flag and the required hooks in your settings.
   Do not proceed until the flag is confirmed enabled.

2. **Hooks** (informational): if the `PreToolUse` → `ExitPlanMode` or `AskUserQuestion` hooks are not present in global settings, inform the user:
   > This skill includes ExitPlanMode and AskUserQuestion as skill-scoped hooks, so they work automatically during `/autonomous-fixes` runs. To also enable them globally, run the setup script above.
   Then continue — do not block on this.

**Step 1: Config Validation**

This skill reuses `.claude/autonomous-tests.json` — no separate config file.

1. Run `test -f .claude/autonomous-tests.json && echo "CONFIG_EXISTS" || echo "CONFIG_MISSING"` in Bash.
2. If `CONFIG_MISSING`, **STOP**: "No autonomous-tests config found. Run `/autonomous-tests` first to set up your project and generate test findings."
3. Read the config. Validate `version` equals `4`.
4. **Verify config trust**: compute SHA-256 hash (same method as autonomous-tests) and check against `~/.claude/trusted-configs/`. If untrusted, show config for confirmation (redact `testCredentials` values). Use `AskUserQuestion` to prompt for approval — the hook ensures this prompt is always shown even in `dontAsk` or bypass mode.
5. **Ensure `documentation.fixResults`**: if missing, add `"fixResults": "docs/_autonomous/fix-results"` to the config and save.
6. **Ensure `userContext.credentialType`**: if `userContext.testCredentials` exists but `userContext.credentialType` is missing or empty, prompt the user for each credential role: "Is `{role-name}` **token-based** (API key, JWT — stateless, parallel-safe) or **session-based** (cookie, login — stateful, sequential-only)?" Save answers to `userContext.credentialType`. This determines whether fix agents can run in parallel with a single credential. Only prompt once — skip if `credentialType` already has entries for all credential roles.
7. **Re-stamp config trust**: if the config was modified during steps 5 or 6 (e.g., added `fixResults` or `credentialType`), re-compute the SHA-256 hash and write it to the trust store. This prevents false "config changed" warnings on the next run of any skill. Use the same hash computation as step 4.
8. **CLAUDE.md deep scan**: Discover all CLAUDE.md files up to 3 directory levels deep from the project root (`find . -maxdepth 3 -name "CLAUDE.md" -type f 2>/dev/null`), plus `~/.claude/CLAUDE.md` (global) and `.claude/CLAUDE.md` (local). Cache the discovered file list for use in Phase 2 (Fix Context Document enrichment). These files provide service-specific architecture context (e.g., `backend/CLAUDE.md` may document model definitions, API patterns, or serialization conventions relevant to the fix).

**Step 2: Findings Scan**

Scan the configured `_autonomous/` directories:
- `documentation.pendingFixes` → pending-fixes documents
- `documentation.testResults` → test-results documents
- `documentation.fixResults` → prior fix-results (for context)

If no pending-fixes and no test-results with `### Requires Fix` or `### Vulnerabilities` entries exist, **STOP**: "No findings to fix. Run `/autonomous-tests` first to generate test results."

---

## Phase 1 — Finding Presentation (User Selection Gate)

Parse all `_autonomous/` documents following the rules in `references/finding-parser.md`. Build a structured summary with four categories:

1. **Vulnerabilities** (V-prefix): Items with Category = `Security Gap`, `Data Leak`, `Privacy Violation`, or from `### Vulnerabilities` / `### API Response Security` subsections. Each shows:
   - OWASP category
   - Severity
   - Regulatory impact (LGPD/GDPR/CCPA/HIPAA)
   - Exploitability assessment
   - Compliance risk level

2. **Bugs** (F-prefix): From pending-fixes, non-security categories.

3. **Failed Tests** (T-prefix): From test-results `### Requires Fix`.

4. **Informational**: Guided tests (G), autonomous tests (A) — counts only, not selectable.

**Argument-based pre-selection**:
- `all` → select all V, F, T items
- `critical` → select items with Severity = Critical
- `high` → select items with Severity = Critical or High
- `vulnerability` → select all V-prefix items
- `file:<path>` → select items from the specified file only

If no argument pre-selects items (empty args or default), present findings via `AskUserQuestion` (forced by hook — works even in dontAsk/bypass mode). Let the user choose which items to fix.

**CRITICAL**: Do NOT read any source code during this phase. No file reads, no grepping, no code exploration. Only parse `_autonomous/` documents. Source code reading happens in Phase 2 after the user has selected items.

---

## Phase 2 — Plan Mode

**Enter plan mode (Use /plan).** The plan MUST start with a "Context Reload" section as **Step 0** containing:
- Instruction to re-read this skill file (the SKILL.md that launched this session)
- Instruction to read the config: `.claude/autonomous-tests.json`
- Instruction to read the templates: the `references/templates.md` file from this skill
- The resolved scope arguments: `$ARGUMENTS`
- The current branch name
- The selected items (IDs, titles, sources)
- Key context from the finding documents

This ensures that when context is cleared after plan approval, the executing agent can fully reconstruct the session state.

**Setup delegation**: When 3+ items are selected for fixing, the orchestrator SHOULD spawn a setup agent (a `general-purpose` agent with `model: "opus"` and `team_name`) to read all source files referenced by the selected findings, compile the Fix Context Documents, and report them back via `SendMessage`. This frees the main agent's context window for orchestration. The setup agent also reads all discovered CLAUDE.md files (deep scan) for architecture context. The setup agent is shut down after reporting. For 1-2 items, the orchestrator may prepare context directly.

**For each selected item**, read the relevant source code and build a **Fix Context Document**:

1. **Verify the finding still reproduces**: re-read the source files referenced in the finding and confirm the reported issue is present in the current code. If the code has changed since the finding was reported (e.g., another developer fixed it, or a prior fix cycle addressed it), mark the item as `Status: ALREADY_RESOLVED` and skip it
2. Read the files referenced in the finding (endpoint files, model files, test files)
3. Trace the code path: input → processing → output
4. Identify the root cause (not just the symptom)
5. Design the fix

**Vulnerability items (V-prefix) get enhanced context**:
- Trace full input → processing → output path for the affected endpoint/handler
- Identify ALL user-controlled inputs reaching the vulnerable code
- Check for related vulnerability patterns in same file/module (e.g., if SQL injection found, check all query construction in the file)
- Assess regulatory exposure (which data protection laws apply to the exposed data)
- **Security-aware remediation design**: fixes must address root causes, not mask symptoms — enforce proper serialization/DTO filtering, add validation/sanitization layers, introduce rate limiting or protective guards where needed

**Dependency analysis**: Determine which items can be fixed independently vs. which form dependent chains:
- **Independent**: Items that affect different files, modules, DB collections, or endpoints with no overlap
- **Dependent**: Items that share files, modify the same function, or where one fix might affect another

**Execution strategy**:
- Independent groups → parallel (one agent per group via Agent Teams)
- Dependent chains → sequential (single agent handles the chain in order)
- Always use `model: "opus"` for agents

**Wait for user approval.**

---

## Phase 3 — Execution

Use `TeamCreate` to create a fix team. Spawn `general-purpose` agents as teammates with `model: "opus"`.

**Standard fix agent instructions** (all items):
1. Read the Fix Context Document for your assigned items
2. Re-read the source files to confirm current state
3. Implement the fix addressing the root cause
4. Run existing unit tests if configured (`testing.unitTestCommand` from config)
5. Verify the fix with targeted checks (API calls, DB queries, log inspection)
6. Report results (RESOLVED/PARTIAL/UNABLE with details)

**Vulnerability fix agent instructions** (V-prefix items — in addition to standard):
1. Remove or redact sensitive data from API responses (enforce DTO/serializer filtering)
2. Add input validation and sanitization at the boundary
3. Implement rate limiting, file size validation, content-type validation where applicable
4. Add circuit breakers for external service interactions
5. Harden error responses (no stack traces, internal metadata, or debug info in responses)
6. Verify the fix doesn't introduce new attack vectors
7. Check for the same vulnerability pattern in related files/endpoints
8. Test with variant attack payloads (not just the original vector)

**Execution flow**:
1. Create tasks for each item/group via `TaskCreate` — include: Fix Context Document, source file paths, fix instructions, verification steps
2. Assign tasks to agents via `TaskUpdate` with `owner`
3. Independent groups run in parallel; dependent chains run sequentially through a single agent
4. Never fix in the main conversation — always delegate to agents
5. After all agents complete, shut down teammates via `SendMessage` with `type: "shutdown_request"`

---

## Phase 4 — Verification

After all agents report, verify results:

**Standard verification** (all items):
- Confirm files were modified as expected
- Run unit tests if configured
- Check that the original issue is resolved (re-execute the failing scenario)

**Security-specific verification** (V-prefix items):
- Re-test the original attack vector (must be blocked)
- Test variant payloads (different injection strings, encoding bypasses, alternative file types)
- Verify no auth bypass or privilege escalation introduced
- Verify error responses are hardened (no internal metadata leakage)
- Verify sensitive data removal from API responses
- Check rate limiting is enforced (if added)

Mark each item as: **RESOLVED** (fix works, verified), **PARTIAL** (partially addressed, needs more work), or **UNABLE** (cannot fix autonomously, needs human intervention).

---

## Phase 5 — Documentation Update

Generate docs in dirs from config (create dirs if needed). Get filename timestamp by running `date -u +"%Y-%m-%d-%H-%M-%S"` in Bash (never guess the time). **Read `references/templates.md` for the exact output structure** before writing.

**Fix-results document**: Always generated. Write to `documentation.fixResults` path. Contains Fix Cycle Metadata, per-item results, and next steps.

**Resolution blocks**: For each item sourced from pending-fixes, append a `### Resolution` block to the corresponding fix entry in the original pending-fixes document.

**Test-results updates**: For each T-prefix item, append a fix-applied status line to the corresponding entry in the test-results document.

**V-prefix items get a `### Security Impact` subsection** in the fix-results document containing:
- OWASP category
- Attack vector (realistic exploitation scenario)
- Regulatory/compliance impact (which laws, what penalties)
- Mitigation description (what the fix does and why it works)
- Related patterns checked (other files/endpoints verified)
- Residual risk (if any)

---

## Phase 6 — Loop Signal

Summarize the fix cycle and signal readiness for re-testing:

```
## Fix Cycle Complete

- Items attempted: {N}
- Resolved: {N}
- Partial: {N}
- Unable: {N}

Re-run autonomous-tests to verify: `/autonomous-tests`
```

If `Ready for Re-test: YES` in the fix-results document, inform the user that autonomous-tests will prioritize re-testing these items on next run.

## Phase 7 — Source Document Cleanup

After the Loop Signal, evaluate whether source documentation files can be removed:

1. **Check resolution status**: For each source document targeted in this fix cycle:
   - Pending-fixes: every `## Fix N:` must have `### Resolution` with `Status: RESOLVED` and `Verification: PASS`
   - Test-results `### Requires Fix`: every entry must have a fix-applied annotation
   - Test-results `### Vulnerabilities` / `### API Response Security`: every entry must be addressed with `Status: RESOLVED`

2. **All resolved — offer removal**: If ALL items are RESOLVED (none skipped, PARTIAL, or UNABLE), prompt via `AskUserQuestion`:
   > "All findings in `{filename}` have been resolved. Remove this source document? Fix-results are preserved as the permanent record."
   If confirmed, delete the source file. If declined, keep it.

3. **Any unresolved — keep files**: If ANY items were skipped, PARTIAL, or UNABLE, do NOT offer removal. Inform the user: "Source document `{filename}` retained — {N} items remain unresolved: {list IDs}."

4. **Never remove fix-results**: Fix-results documents are the permanent record and are needed by autonomous-tests for re-test prioritization.

**Vulnerability warning**: If any V-prefix items remain PARTIAL or UNABLE, emit a prominent warning with security priority ranking:

```
⚠️ UNRESOLVED SECURITY FINDINGS

The following security items could not be fully resolved and require manual attention:

Priority order (highest risk first):
1. Data leaks — {list V-prefix items if any}
2. Credential exposure — {list V-prefix items if any}
3. Privilege escalation — {list V-prefix items if any}
4. Denial-of-service risks — {list V-prefix items if any}
5. Compliance violations — {list V-prefix items if any}
```

## Phase 8 — Context Reset Advisory

After all phases complete, display this message prominently:

> **Important**: Run `/clear` before invoking another skill (e.g., `/autonomous-tests` to re-test) to free context window tokens and prevent stale state from interfering with the next operation.

---

## Rules

- Never modify production data or connect to production services
- Never expose credentials, keys, or tokens in documentation output
- Always enter plan mode before executing fixes (Phase 2)
- Always delegate fixes to Agent Teams — never fix in main conversation
- **NEVER use the `Agent` tool directly for execution. ALWAYS use `TeamCreate` → `TaskCreate` → spawn agents with `team_name` parameter → `TaskUpdate` → `SendMessage`. Plain `Agent` calls bypass team coordination and task tracking. The `Agent` tool without `team_name` is PROHIBITED during Phase 3.**
- Always spawn agents with `model: "opus"` for maximum reasoning capability
- Always present findings for user selection before reading source code (Phase 1 before Phase 2)
- AskUserQuestion hook ensures user selection even in dontAsk/bypass mode
- Security fixes must address root causes — not mask symptoms
- Use UTC timestamps everywhere — always obtain from `date -u`, never guess
- Reuse `.claude/autonomous-tests.json` — never create a separate config
- Never activate Docker MCPs where `safe: false`
- V-prefix items always get enhanced security context, verification, and documentation
