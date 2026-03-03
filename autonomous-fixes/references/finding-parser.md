# Finding Parser — Parsing Rules

Reference file for Phase 1 (Finding Presentation). Follow these rules exactly when parsing `_autonomous/` documents.

---

## ID Assignment

| Prefix | Category | Source |
|--------|----------|--------|
| **V** | Security / Vulnerability | `### Vulnerabilities` in test-results, security items in pending-fixes |
| **F** | Bug (non-security) | pending-fixes, non-security categories |
| **T** | Failed Test | `### Requires Fix` in test-results |
| **G** | Guided Test (informational) | pending-guided-tests |
| **A** | Autonomous Test (informational) | pending-autonomous-tests |

IDs are assigned sequentially per prefix: V-1, V-2, F-1, F-2, T-1, etc.

---

## Parsing: `pending-fixes/`

Each `## Fix N:` section is one finding. Extract:

| Field | Location |
|-------|----------|
| Title | `## Fix N: {Title}` heading |
| Severity | Metadata table → `Severity` row |
| Category | Metadata table → `Category` row |
| Test ID | Metadata table → `Test ID` row |
| Problem | `### Problem` subsection |
| Evidence | `### Evidence` subsection (fenced code block) |
| Suggested Resolution | `### Suggested Resolution` subsection |
| Resolution Status | `### Resolution` subsection (if present) — `Status` field |

**V-prefix assignment**: Items where Category is one of:
- `Security Gap`
- `Data Leak`
- `Privacy Violation`

Or where the Severity tag contains security-related keywords (e.g., "injection", "XSS", "auth bypass", "exposure").

All other items get **F-prefix**.

**Skip resolved items**: If a `### Resolution` block exists with `Status: RESOLVED` and `Verification: PASS`, do not present this item — it has already been fixed and verified.

---

## Parsing: `test-results/`

### `### Requires Fix` subsection

Each numbered entry is one finding. Extract:

| Field | Location |
|-------|----------|
| Title | `**{Issue title}**` (bold text) |
| Severity | Parenthetical after title |
| Endpoint/File | `Endpoint / File:` line |
| Problem | Description lines |
| Suggested Resolution | Resolution lines |

These get **T-prefix**.

**Exception**: If a `### Requires Fix` item has security-related keywords in its title or description (injection, XSS, CSRF, auth bypass, data leak, exposure, SSRF, privilege escalation), assign **V-prefix** instead.

### `### Vulnerabilities` subsection

Each numbered entry is one finding. Extract:

| Field | Location |
|-------|----------|
| Title | `**{Title}**` (bold text) |
| OWASP Category | Parenthetical after title |
| Severity | After `—` dash |
| Endpoint/File | `Endpoint / File:` line |
| Attack Vector | `Attack Vector:` line |
| Evidence | `Evidence:` line |
| Regulatory Impact | `Regulatory Impact:` line |
| Compliance Risk | `Compliance Risk:` line |
| Recommended Mitigation | `Recommended Mitigation:` line |

These always get **V-prefix**.

### `### API Response Security` subsection

Each table row is one finding. Extract:

| Field | Column |
|-------|--------|
| Endpoint | `Endpoint` column |
| Finding | `Finding` column |
| Category | `Category` column |
| Severity | `Severity` column |
| Regulation | `Regulation` column |

These always get **V-prefix**. Group related API response findings from the same endpoint into a single V-prefix item.

---

## Parsing: `pending-guided-tests/`

Count `## Test N:` sections. These get **G-prefix** but are informational only (count displayed, not selectable for fixing).

---

## Parsing: `pending-autonomous-tests/`

Count `## Test N:` sections. These get **A-prefix** but are informational only (count displayed, not selectable for fixing).

---

## Cross-Reference Deduplication

After parsing all sources, deduplicate:

1. **Same endpoint + same issue**: If a pending-fix and a test-results finding reference the same endpoint/file and describe the same problem, merge them into one item. Prefer the pending-fix version (it has more detail).
2. **Same vulnerability**: If a `### Vulnerabilities` entry and an `### API Response Security` entry describe the same exposure on the same endpoint, merge into one V-prefix item.
3. **Fix already applied**: If a pending-fix has a `### Resolution` block with `Status: RESOLVED` and `Verification: PASS`, exclude it entirely.

After deduplication, re-number IDs sequentially within each prefix.

---

## Output Format

Present findings grouped by category:

```
## Vulnerabilities ({count})

- [V-1] {Title} — {Severity} — {OWASP Category}
  Endpoint: {path} | Regulation: {LGPD/GDPR/etc.} | Compliance Risk: {level}

- [V-2] ...

## Bugs ({count})

- [F-1] {Title} — {Severity}
  File: {path} | Category: {category}

- [F-2] ...

## Failed Tests ({count})

- [T-1] {Title} — {Severity}
  Endpoint: {path}

- [T-2] ...

## Informational

- Guided tests pending: {G count}
- Autonomous tests pending: {A count}
```
