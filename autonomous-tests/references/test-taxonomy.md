# Test Taxonomy

Reference taxonomy for test types, categories, anomaly detection, and finding verification. Embedded verbatim in plans via the self-containment mandate — agents classify and execute tests without needing this file post-reset.

---

## Test Types

### Integration Tests

- **Definition**: API-level tests exercised via HTTP requests. Security-focused, no UI interaction.
- **Tool**: Always `curl`.
- **Classification**: `integration/api`
- **Scope**: Categories 1-8. All autonomous — no user interaction required.
- **Browser**: Never required. Integration tests never gate on browser availability.

### E2E Tests

- **Definition**: Full user-flow tests requiring browser or device interaction.
- **Tool (webapp)**: `agent-browser` (primary) or Playwright (fallback) + chrome-devtools-mcp for observation.
- **Tool (mobile)**: Guided steps for physical device — user performs actions, agent verifies via DB/API/logs.
- **Classification**: `e2e/webapp`, `e2e/mobile`
- **Scope**: Happy-path workflows (category 1) in browser/device context.
- **NEVER tests production environments.**

### Regression Tests

- **Definition**: Existing unit tests run via `testing.unitTestCommand`.
- **Tool**: Project's test runner (pytest, jest, vitest, etc.).
- **Classification**: `regression/unit`
- **Scope**: Run ONCE at the very end after ALL suites complete. Never interleaved with other suites.

### Guided Tests

- **Definition**: Step-by-step user interaction via `AskUserQuestion`. Agent seeds data, presents instructions, user acts, agent verifies.
- **Classification**: `guided/webapp`, `guided/mobile`
- **Scope**: Category 1 (happy path) ONLY. Categories 2-9 are autonomous-only — NEVER in guided sessions.
- **No browser automation**: `agent-browser` and Playwright MUST NOT be loaded in guided mode.

---

## Integration Test Categories

Standard (autonomous) mode: all 8 categories. Guided mode: category 1 ONLY.

### Category 1 — Happy Path

Baseline functionality via curl. Normal expected flows end-to-end. Verify correct responses, status codes, and DB state for standard operations.

### Category 2 — Input Validation & Edge Cases

Boundary conditions, type mismatches, empty values, missing required fields, wrong types, oversized payloads via curl. Verify proper error responses and no data corruption.

### Category 3 — Idempotency & Retries

Duplicate requests, rapid same-call repetition via curl. Verify no duplicate records, charges, or side-effects. Concurrent operations that should be idempotent.

### Category 4 — Error Handling

Graceful failures, error messages via curl. Trigger every error branch: network failures, invalid states, auth failures, permission denials. Verify error responses are informative but not leaky.

### Category 5 — Race Conditions & Concurrency

Parallel curl requests, timing-dependent bugs. Concurrent writes, out-of-order webhooks, expired tokens mid-flow. Verify data consistency under concurrent access.

### Category 6 — Security & Injection

Injection attacks, XSS payloads, CSRF, auth bypass via curl. Covers security checklist items 1-6, 9-11:

- SQL/NoSQL/command/LDAP/XPath/SSTI/header/log injection
- XSS (stored/reflected/DOM), CSRF, clickjacking
- Auth bypass, broken access control, privilege escalation, session manipulation, JWT manipulation
- Input attacks: file uploads (sizes/zip bombs/polyglots/path traversal), oversized/nested/type confusion/prototype pollution payloads, parameter injection/pollution/encoding, host injection/SSRF, rate limiting/ReDoS

Findings classified with OWASP categories. Priority: data leaks > credentials > escalation > DoS > compliance.

### Category 7 — API Response Security

ID leakage, credential exposure, PII, compliance violations via curl. Covers security checklist items 2, 8, 9:

- Exposed identifiers: internal DB IDs, sequential/guessable IDs, sensitive refs (paths, internal URLs)
- Leaked secrets: API keys, tokens beyond scope, passwords/hashes, env vars in errors, cloud secrets
- Personal data (multi-regulation): PII (names, emails, phones, addresses, govt IDs, DOB), sensitive data (health/financial/biometric/racial/political/religious/sexual/genetic)
- Regulatory mapping: LGPD, GDPR, CCPA/CPRA, HIPAA

Verify against source code (model/serializer/DTO) to confirm fields exist in real schema — not test data. False positives MUST NOT be reported.

### Category 8 — Data Consistency

Referential integrity, orphans, mutations via curl + DB queries. Covers security checklist item 7:

- Orphaned records after deletions
- Missing foreign key/reference integrity
- Unintended mutations to non-target data
- Index-less slow queries

---

## Browser Tool Priority

For autonomous E2E tests requiring browser interaction, attempt in this order. Skipping without attempting is PROHIBITED:

1. **`agent-browser`** (PRIMARY) — `open <url>` then `snapshot -i` then `click/fill @ref` then re-snapshot
2. **Playwright** (FALLBACK) — if agent-browser unavailable or errors
3. **Direct HTTP/API** (LAST RESORT) — mark untestable UI parts as "guided"

Integration tests (categories 1-8 via curl) NEVER gate on browser availability.

---

## Anomaly Detection

During test execution, agents watch for these anomalies and report when detected:

- **Duplicate records** — unexpected duplicates created by test operations
- **Unexpected DB changes** — modifications to collections/tables not targeted by the test
- **Warning/error logs** — stderr output, application warnings, error-level log entries
- **Slow queries / missing indexes** — queries taking >100ms, full table/collection scans
- **Orphaned references** — foreign keys/refs pointing to non-existent documents/rows
- **Auth token anomalies** — expired tokens accepted, token reuse after logout, privilege escalation
- **Unexpected response fields** — fields not in the API contract, extra data leakage
- **Unexpected status codes** — 500s where 4xx expected, 200s where errors expected
- **State inconsistencies** — frontend/backend/DB state disagreement after operations
- **Performance degradation** — response times >2s for standard operations

---

## Finding Verification Protocol

Before reporting ANY finding, agents MUST complete this verification sequence:

1. **Identify source code** — locate the exact file, function, and line responsible for the observed behavior
2. **Read and confirm** — read the source code to confirm the behavior is real (not a test artifact or mock)
3. **Distinguish real vs agent-created** — verify the finding exists in the actual codebase, not in test data created by the agent
4. **Classification**:
   - **Confirmed** — source code review confirms the issue is genuine. Report with full details.
   - **Unverified** — cannot confirm from source code alone. Report with `Severity: Unverified` in `### Unverified` subsection.
5. **Report only confirmed findings** — unconfirmed observations go to `### Unverified`, never to main findings

False positives erode trust. When in doubt, classify as Unverified rather than inflating severity.
