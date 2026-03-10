# Security Checklist

Reference checklist for security observations during testing. Embedded verbatim in plans via the self-containment mandate — agents evaluate security without needing this file post-reset.

---

## Security Observation Items

17 items evaluated per feature during Discovery. Each mapped as YES / NO / PARTIAL based on feature relevance.

| # | Item | Description |
|---|------|-------------|
| 1 | Security | Authentication, authorization, and access control mechanisms |
| 2 | Data protection | Encryption in transit, masked logs, no exposure in UI/API responses |
| 3 | Authentication flows | Login, logout, session expiration, token refresh, MFA |
| 4 | Authorization/permissions | Role-based access, resource restrictions, ownership checks |
| 5 | Input validation | Invalid, malicious, and unexpected input handling |
| 6 | Injection protection | SQL, command, script, NoSQL, LDAP, XPath, SSTI injection defense |
| 7 | Data integrity | Correct and consistent storage across operations |
| 8 | Privacy compliance | Consent flows, data visibility, regulatory requirements |
| 9 | Error handling | No stack traces, internal details, or sensitive info in error responses |
| 10 | Session management | Expiration, reuse prevention, logout invalidation |
| 11 | Access boundaries | Cross-user data access prevention, restricted resource enforcement |
| 12 | Auditability | Logging of important actions (login, data changes, admin ops) |
| 13 | Resilience to failures | Safe behavior when dependencies fail (DB down, API timeout, queue full) |
| 14 | Consistency across systems | Frontend/backend/DB state agreement after operations |
| 15 | Performance impact on flows | Responsive critical journeys, no blocking operations on user-facing paths |
| 16 | Recovery behavior | Retries, partial failures, interrupted processes handled gracefully |
| 17 | User feedback | Clear, safe messages for success/failure — no sensitive data in messages |

---

## Discovery Mapping

During Phase 2 (Discovery), map each item to the feature under test:

```
Feature: {feature name}
Security Observations:
  1. Security:           YES — {brief reason}
  2. Data protection:    PARTIAL — {what applies}
  3. Authentication:     NO — {not relevant to this feature}
  ...
```

- **YES** — Feature directly involves this concern. Generate test cases.
- **PARTIAL** — Feature touches this concern indirectly. Generate lightweight checks.
- **NO** — Feature does not involve this concern. Skip related test cases.

Only YES and PARTIAL items are embedded in suite agent prompts. NO items are excluded to reduce noise.

---

## Embedding in Suite Prompts

For each suite agent, include only the applicable security items:

```
SECURITY OBSERVATIONS for this suite:
- Item 1 (Security): {YES} — verify auth on all endpoints
- Item 5 (Input validation): {YES} — test malformed payloads
- Item 9 (Error handling): {PARTIAL} — check error responses don't leak internals
```

Category 6 (Security & Injection) suites receive items 1-6, 9-11.
Category 7 (API Response Security) suites receive items 2, 8, 9.
Category 8 (Data Consistency) suites receive item 7.
Other categories receive applicable items based on Discovery mapping.

---

## API Response Security Inspection Protocol

Analyze ALL API responses for the following categories. This inspection runs within Category 7 suites and as a background check in all other suites.

### Exposed Identifiers

- Internal database IDs (ObjectId, UUID, auto-increment)
- Sequential or guessable IDs enabling enumeration
- Sensitive references: internal file paths, internal URLs, infrastructure details

### Leaked Secrets

- API keys or tokens beyond the requesting user's scope
- Passwords or password hashes in any response
- Environment variables in error messages
- Cloud provider secrets (AWS keys, GCP tokens, Azure secrets)

### Personal Data (Multi-Regulation)

- **PII**: Names, emails, phone numbers, addresses, government IDs, date of birth
- **Sensitive**: Health, financial, biometric, racial, political, religious, sexual orientation, genetic data
- **Regulations**: LGPD (Brazil), GDPR (EU), CCPA/CPRA (California), HIPAA (US health)

### Verification Protocol

1. Identify suspicious field in API response
2. Read model/serializer/DTO source code to confirm field exists in real schema
3. Determine if field is intentionally exposed or accidentally leaked
4. **False positives MUST NOT be reported** — only confirmed leaks

### Finding Format

Each finding includes:
- **Severity**: Critical / High / Medium / Low
- **Regulatory impact**: Which regulations apply (LGPD / GDPR / CCPA / HIPAA)
- **Exploitability**: How an attacker could use this
- **Compliance risk**: Critical / High / Medium / Low
- **Endpoint**: Exact path and method
- Output to `### API Response Security` subsection in test-results

---

## OWASP Category Mapping

Classify all vulnerabilities using OWASP Top 10 categories:

| OWASP ID | Category | Maps To |
|----------|----------|---------|
| A01:2021 | Broken Access Control | Items 1, 4, 11 |
| A02:2021 | Cryptographic Failures | Items 2, 8 |
| A03:2021 | Injection | Items 5, 6 |
| A04:2021 | Insecure Design | Items 13, 16 |
| A05:2021 | Security Misconfiguration | Items 9, 12 |
| A06:2021 | Vulnerable Components | Item 6 (known CVEs) |
| A07:2021 | Auth Failures | Items 3, 10 |
| A08:2021 | Data Integrity Failures | Item 7 |
| A09:2021 | Logging Failures | Item 12 |
| A10:2021 | SSRF | Item 6 (SSRF subset) |

Vulnerability priority order: data leaks > credential exposure > privilege escalation > DoS > compliance violations.

Each vulnerability finding in `### Vulnerabilities` subsection includes the OWASP ID, attack vector, evidence, regulatory impact, and recommended mitigation.
