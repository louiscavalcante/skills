# Autonomous Tests — Output Templates

Reference file for Phase 7 documentation. Follow these structures exactly when generating output.

**Filename convention**: Get UTC timestamp by running `date -u +"%Y-%m-%d-%H-%M-%S"` in Bash (never guess). Pattern: `{YYYY-MM-DD-HH-MM-SS}_{semantic-name}.md`

---

## `docs/_autonomous/test-results/{YYYY-MM-DD-HH-MM-SS}_{feature-name}-e2e-results.md`

```markdown
# E2E Test Results: {Feature Name}

- **Date**: {YYYY-MM-DD HH:MM:SS UTC}
- **Branch**: {branch}
- **Commits tested**: `{short-sha}` ({summary}) [+ more if multiple]
- **Environment**: Local ({services list with versions/modes})
- **Prior E2E run**: `{path}` ({date}, {summary}) [omit if first run]
- **Capabilities**: {list of capabilities used} [omit if none]
- **File reference**: `{path}` [omit if none]
- **Prior history**: {count} related docs found in _autonomous/ [omit if none]

## Summary

| Suite | Tests | Pass | Fail | Skip | Findings |
|-------|-------|------|------|------|----------|
| 1. {Suite Name} | N | N | N | N | {brief finding or "All pass"} |
| **Total** | **N** | **N** | **N** | **N** | **N issues found** |

## Per-Suite Results

### Suite 1: {Suite Name}

| Test ID | Description | Expected | Actual | Status |
|---------|-------------|----------|--------|--------|
| 1.1 | {what was tested} | {expected outcome} | {actual outcome} | PASS |
| 1.2 | {what was tested} | {expected outcome} | {actual outcome} | **FAIL** |

---

### Suite 2: {Suite Name}

| Test ID | Description | Expected | Actual | Status |
|---------|-------------|----------|--------|--------|

---

## Issues Found

### Runtime-Fixed

- {description, if any}

### Requires Fix

1. **{Issue title}** ({Severity})
   - Endpoint / File: `{path or endpoint}`
   - {Problem description}
   - {Suggested resolution}

### Vulnerabilities

1. **{Title}** ({OWASP Category}) — {Severity}
   - Endpoint / File: `{path}`
   - Attack Vector: {realistic exploitation description}
   - Evidence: {what was found in the response/behavior}
   - Regulatory Impact: {LGPD / GDPR / CCPA / HIPAA — which apply}
   - Compliance Risk: {Critical / High / Medium / Low}
   - Recommended Mitigation: {what to do}

### API Response Security

| Endpoint | Finding | Category | Severity | Regulation |
|----------|---------|----------|----------|------------|
| `{path}` | {what was exposed} | {Data Leak / ID Exposure / Secret Leak} | {severity} | {LGPD/GDPR/etc.} |

### Needs Guided Testing

- {What needs manual testing and why}
- See `docs/_autonomous/pending-guided-tests/{timestamp}_{feature-name}-guided-tests.md`

### Queued for Autonomous Re-run

- {Tests identified but not run in this session}
- See `docs/_autonomous/pending-autonomous-tests/{timestamp}_{feature-name}-autonomous-tests.md`

## Environment Post-Test State

- Backend: {status}
- Database: {status}
- Unit tests: {count} passing
- External services: {status and mode}
- Test data: {what was created/modified, or "read-only run"}
```

**Rules**: `---` between suites. Bold `**FAIL**` entries. Backticks for paths/SHAs. Include file:line in issues. Omit "Queued for Autonomous Re-run" section if none were queued.

---

## `docs/_autonomous/pending-guided-tests/{YYYY-MM-DD-HH-MM-SS}_{feature-name}-guided-tests.md`

Each test is a self-contained section with subsections — not a bullet list.

```markdown
# {Feature Name} — Guided Tests

These tests require browser interaction, visual verification, or real user actions that cannot be automated via CLI/API alone.

---

## Test 1: {Descriptive Test Name}

**Purpose**: {One sentence describing what this test verifies end-to-end.}

### Prerequisites

- {Required state, e.g. "A batch must exist with status `accumulating`"}
- {Required services, e.g. "Stripe webhook listener must be running"}

### Steps

1. {Action with specific details — URLs, credentials, button names}
2. {Next action}
3. {Next action}
4. Wait for {processing/webhook/etc.} (~{estimated time})

### Verification (Claude checks)

```bash
# {Descriptive comment explaining what this checks}
{exact verification command}

# {Next check}
{exact verification command}
```

### Expected

- {Specific expected outcome with values, statuses, field names}
- {Another expected outcome}

---

## Test 2: {Descriptive Test Name}

**Purpose**: {One sentence.}

### Steps

1. {Action}
2. {Action}

### Verification (Claude checks)

```bash
# {Check description}
{command}
```

### Expected

- {Outcome}

### Notes

{Timing dependencies, edge cases, or alternatives — only when relevant.}

---

## Environment Info

| Item | Value |
|------|-------|
| Backend | `{url}` |
| Webapp | `{url}` |
| External Service Mode | {Sandbox/Test} |
| Test User | `${TEST_USER_EMAIL}` / `${TEST_USER_PASSWORD}` (env var references — never raw credentials) |
| Test Data | `{relevant test identifiers}` |
```

**Rules**: `---` between every test. Number sequentially (`## Test 1:`, `## Test 2:`). `**Purpose**:` as bold paragraph, not a heading. `### Steps` with numbered list including specific URLs/credentials. `### Verification (Claude checks)` with fenced bash + `# comment` lines. `### Expected` with bullet list. Include `### Prerequisites` and `### Notes` only when they add value. Always end with `## Environment Info` table. Never expose real credentials.

---

## `docs/_autonomous/pending-fixes/{YYYY-MM-DD-HH-MM-SS}_{feature-name}-fixes.md`

```markdown
# Pending Fixes: {Feature Name}

- **Date**: {YYYY-MM-DD HH:MM:SS UTC}
- **Branch**: {branch}
- **Related E2E**: `docs/_autonomous/test-results/{timestamp}_{feature-name}-e2e-results.md`

---

## Fix 1: {Descriptive Fix Title}

| Field | Value |
|-------|-------|
| Severity | {Critical / High / Medium / Low} |
| Category | {Code Bug / Infrastructure / Missing Migration / Missing Index / Security Gap} |
| Test ID | {e.g. 4.1 — links back to test results} |

### Problem

{Clear description with specific error messages or unexpected behavior.}

### Evidence

```
{Test output, log lines, or DB query results}
```

### Suggested Resolution

{What to change, where, and why.}

- File: `{path}:{line}`
- Action: {what to do}

---

## Infrastructure Notes

{Only include if there are infrastructure-level findings.}

### Missing Indexes

- Collection: `{name}` — {what index is needed and why}

### Missing Migrations

- {What migration is needed}
```

**Rules**: Number fixes (`## Fix 1:`, `## Fix 2:`). Metadata summary table per fix. `### Problem` / `### Evidence` / `### Suggested Resolution` subsections. Fenced code blocks for evidence. Reference test IDs for traceability. `---` between fixes. Never expose credentials. Vulnerabilities are ALWAYS tracked in the separate `### Vulnerabilities` subsection — never mixed into `### Requires Fix`.

### Resolution Block (appended by autonomous-fixes)

When a fix is applied by `autonomous-fixes`, a `### Resolution` block is appended to the corresponding fix entry:

```markdown
### Resolution

| Field | Value |
|-------|-------|
| Status | {RESOLVED / PARTIAL / UNABLE} |
| Fix Date | {YYYY-MM-DD HH:MM:SS UTC} |
| Fix Cycle | `{path to fix-results doc}` |
| Verification | {PASS / FAIL — re-test result} |

{Brief description of what was changed and why.}
```

A fix with `Status: RESOLVED` and `Verification: PASS` becomes a regression target for future autonomous-tests runs.

---

## `docs/_autonomous/pending-autonomous-tests/{YYYY-MM-DD-HH-MM-SS}_{feature-name}-autonomous-tests.md`

Tests that can be fully automated but were not run in this session (queued for a future `/autonomous-tests` run).

```markdown
# Pending Autonomous Tests: {Feature Name}

- **Date**: {YYYY-MM-DD HH:MM:SS UTC}
- **Branch**: {branch}
- **Related E2E**: `docs/_autonomous/test-results/{timestamp}_{feature-name}-e2e-results.md`
- **Reason queued**: {Why these weren't run — e.g., dependency not ready, time constraint, scope excluded}

---

## Test 1: {Descriptive Test Name}

| Field | Value |
|-------|-------|
| Priority | {High / Medium / Low} |
| Category | {API / Integration / Webhook / Database / UI-API} |
| Estimated Duration | {e.g., ~30s, ~2min} |

### Objective

{What this test verifies and why it matters.}

### Pre-conditions

- {Required state}
- {Required services}

### Steps

1. {API call or action with specific details}
2. {Next action}
3. {Verification query}

### Expected Outcome

- {Specific expected result with values}
- {Database state check}

### Teardown

- {Cleanup actions}

---

## Automation Notes

- {Hints for the autonomous runner — e.g., required seed data, timing considerations}
- {Services that must be running}
```

**Rules**: Same structure conventions as other templates. `---` between tests. Number sequentially (`## Test 1:`, `## Test 2:`). Always include `### Teardown` per test. Always end with `## Automation Notes` section. Cross-reference the related E2E run that generated these. Never expose credentials.

---

## `docs/_autonomous/fix-results/{YYYY-MM-DD-HH-MM-SS}_{feature-name}-fix-results.md`

Generated by `autonomous-fixes` after a fix cycle completes.

```markdown
# Fix Results: {Feature Name}

## Fix Cycle Metadata

| Field | Value |
|-------|-------|
| Date | {YYYY-MM-DD HH:MM:SS UTC} |
| Branch | {branch} |
| Items Attempted | {N} |
| Resolved | {N} |
| Partial | {N} |
| Unable | {N} |
| Ready for Re-test | {YES / NO} |

## Results

### {F/V/T}-{N}: {Item Title}

| Field | Value |
|-------|-------|
| Source | `{path to pending-fixes or test-results doc}` |
| Status | {RESOLVED / PARTIAL / UNABLE} |
| Files Modified | `{path1}`, `{path2}` |
| Verification | {PASS / FAIL} |

**What was done**: {description of the fix applied}

**Verification details**: {how the fix was verified}

---

## Next Steps

- {Re-run autonomous-tests to verify fixes: `/autonomous-tests`}
- {Items still pending: list any PARTIAL/UNABLE items}
- {New findings discovered during fix cycle, if any}
```

**Rules**: One `### {ID}: {Title}` section per item. ID uses the same prefix assigned during finding presentation (F/V/T). `---` between items. Always include `## Fix Cycle Metadata` and `## Next Steps`. If `Ready for Re-test: YES`, autonomous-tests will prioritize re-testing these items on next run.
