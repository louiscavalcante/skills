# Autonomous Fixes — Output Templates

Reference file for Phase 5 documentation. Follow these structures exactly when generating output.

**Filename convention**: Get UTC timestamp by running `date -u +"%Y-%m-%d-%H-%M-%S"` in Bash (never guess). Pattern: `{YYYY-MM-DD-HH-MM-SS}_{semantic-name}.md`

---

## `docs/_autonomous/fix-results/{YYYY-MM-DD-HH-MM-SS}_{feature-name}-fix-results.md`

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
| Original Test IDs | {1.2, 4.1 — from source finding's Test ID field, or "N/A" for V-prefix} |
| Verification | {PASS / FAIL} |

**What was done**: {description of the fix applied}

**Verification details**: {how the fix was verified}

---

## Next Steps

- {Re-run autonomous-tests to verify fixes: `/autonomous-tests`}
- {Items still pending: list any PARTIAL/UNABLE items}
- {New findings discovered during fix cycle, if any}
```

**Rules**: One `### {ID}: {Title}` section per item. ID uses the assigned prefix (F/V/T). `---` between items. Always include `## Fix Cycle Metadata` and `## Next Steps`. If `Ready for Re-test: YES`, autonomous-tests will prioritize re-testing on next run. Populate `Original Test IDs` from the source pending-fixes `Test ID` field. For T-prefix items, use the test ID from the test-results entry directly. For V-prefix, use "N/A — vulnerability".

---

## Resolution Block (appended to pending-fixes)

When a fix is applied, append a `### Resolution` block to the corresponding fix entry in the pending-fixes document:

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

**Rules**: Append directly after the `### Suggested Resolution` section of the corresponding fix. Do not modify existing content — only append. A fix with `Status: RESOLVED` and `Verification: PASS` is excluded from future fix cycles.

---

## Test-Results Update (one-line append)

When a failed test (T-prefix) is fixed, append a status line to the corresponding entry in the test-results `### Requires Fix` subsection:

```markdown
   - **Fix applied**: {YYYY-MM-DD} — {brief description} (see `{fix-results path}`)
```

**Rules**: Append as the last bullet under the test entry. Do not modify existing content.

---

## Security Impact Subsection (V-prefix items only)

For every V-prefix item, include a `### Security Impact` subsection in the fix-results document:

```markdown
### Security Impact

| Field | Value |
|-------|-------|
| OWASP Category | {e.g., A03:2021 - Injection} |
| Attack Vector | {realistic exploitation scenario} |
| Regulatory Impact | {LGPD / GDPR / CCPA / HIPAA — which apply and why} |
| Compliance Risk | {Critical / High / Medium / Low} |
| Mitigation | {what the fix does} |
| Related Patterns Checked | {N files/endpoints verified for same pattern} |
| Residual Risk | {none / description} |
```

**Rules**: Always include for V-prefix items. The `### Security Impact` subsection appears after `**Verification details**` and before the `---` separator. `Related Patterns Checked` must reflect actual verification — list how many files/endpoints were scanned for the same vulnerability pattern.
