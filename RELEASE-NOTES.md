# Release Notes

## v1.1.1 (2026-03-03)

### Fixed
- **Enforce Agent Teams over plain Agent calls**: Added explicit rule prohibiting the `Agent` tool without `team_name` during execution phases — both skills now require the full `TeamCreate` → `TaskCreate` → spawn with `team_name` → `TaskUpdate` → `SendMessage` workflow

## v1.1.0 (2026-03-03)

### Added
- **autonomous-fixes skill**: Reads findings from autonomous-tests, applies fixes via Agent Teams, and updates docs for re-testing — creating a bidirectional test-fix loop
- **Vulnerability tracking (V-prefix)**: Security findings tracked separately with OWASP categorization, multi-regulation compliance (LGPD, GDPR, CCPA, HIPAA), exploitability assessment, and priority ranking
- **API Response Security inspection**: Deep analysis of all API responses for exposed IDs, leaked credentials, PII, and compliance violations during test execution
- **Attack surface analysis**: Comprehensive security test coverage — injection attacks, cross-site attacks, auth/authz, data exposure, input handling as attack vectors, infrastructure, and compliance
- **`vulnerability` argument**: Pre-select all V-prefix items in autonomous-fixes
- **`credentialType` config field**: Token-based (API key, JWT) vs session-based (cookie, login) credential classification for parallel execution decisions
- **`documentation.fixResults`** config path for fix-results output
- **Finding parser** (`references/finding-parser.md`): Parsing rules for V/F/T/G/A prefix assignment and cross-reference deduplication
- **Fix-results template**: Structured output for fix cycles with metadata, per-item results, and security impact subsections
- **Resolution block template**: Appended to pending-fixes by autonomous-fixes for traceability
- **`### Vulnerabilities` subsection** in test-results: Separate tracking from `### Requires Fix`
- **`### API Response Security` subsection** in test-results: Tabular security findings
- **AskUserQuestion hook**: Forces user prompt even in dontAsk/bypass mode (skill-scoped + hooks.json)
- **Trigger tests** for autonomous-fixes: 4 prompt files

### Changed
- **Token-based credentials now allow parallel execution**: Single token-based (stateless) credentials are parallel-safe; only session-based credentials require sequential execution
- **Sequential execution uses single agent**: When running sequentially, a single `general-purpose` agent with `model: "opus"` is spawned instead of running in the main conversation
- **Fix completion scanning**: autonomous-tests now scans for `### Resolution` blocks (RESOLVED + PASS → regression target) and fix-results (`Ready for Re-test: YES` → priority re-test)
- **Expanded Security test suite**: Covers OWASP Top 10, injection attacks (SQL/NoSQL/command/SSTI/header/log), cross-site attacks (XSS/CSRF/clickjacking), auth/authz bypass, JWT manipulation, input handling as attack vectors (file uploads, API payloads, query params, headers, request volume), infrastructure (SSRF, path traversal, insecure deserialization), and compliance violations
- **Config schema**: Added `documentation.fixResults` and `userContext.credentialType` fields
- **Credential type questionnaire**: First-run setup now asks whether each credential is token-based or session-based

## v1.0.0 (2026-03-02)

Initial public release of autonomous-tests.

### Added
- 8-phase execution pipeline (config → safety → services → discovery → plan → execute → fix → docs → cleanup)
- Config schema v4 with capabilities detection (Docker MCPs, agent-browser, Playwright, Stripe CLI)
- Smart doc analysis via `file:<path>` argument
- Test history scanning from `_autonomous/` folders
- Config trust store with SHA-256 hashing (`~/.claude/trusted-configs/`)
- Credential safety: env var references only, redacted display, per-agent isolation
- Production safety: auto-abort on live key detection
- Four structured output types: test-results, pending-fixes, pending-guided-tests, pending-autonomous-tests
- Cross-project dependency tracing
- setup-hook.sh installer for ExitPlanMode hook, Agent Teams flag, Opus model
- agent-browser prioritized over Playwright for web/frontend testing
