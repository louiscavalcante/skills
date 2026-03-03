# Release Notes

## v1.2.0 (2026-03-03)

### Added
- **autonomous-tests-swarm skill**: Per-agent Docker isolation — each agent spins up its own database, API, and services on unique ports, runs migrations/seeds, executes test suites, and tears down independently. No shared state, no credential conflicts, true parallel testing.
- **Docker context detection**: Auto-detects available Docker contexts, prioritizes Docker Desktop when available
- **Port discovery and allocation**: Scans for available port ranges, assigns non-conflicting ranges per agent
- **Compose and raw-docker modes**: Supports both docker-compose-based and raw `docker run` environments
- **Related service inclusion**: Agents can include related projects (e.g., webapp + backend) in their isolated stack
- **Failure redistribution**: If an agent's environment fails to start, its suites are redistributed to a healthy agent
- **Swarm config schema** (`references/config-schema-swarm.json`): Defines the `swarm` section for `.claude/autonomous-tests.json`
- **Trigger tests** for autonomous-tests-swarm: 2 prompt files
- **Database seeding fields** in config schema: `database.seedCommand`, `database.migrationCommand`, `database.cleanupCommand` — agents execute in order: migrate → seed → test → cleanup
- **Auto-detection of seed/migration commands** during first-run setup: scans compose files, `scripts/` directories, Makefiles, and package.json for common patterns (`manage.py migrate`, `npx prisma db seed`, `knex seed:run`, etc.)
- **Explicit MongoDB and SQL detection** in Phase 0: checks both MongoDB indicators (`mongosh`, `mongoose`, `mongodb://`) and SQL indicators (`psql`, `prisma`, `pg`, `postgres://`) to set `database.type` accurately
- **Database operation distinction in Phase 3**: feature map now distinguishes MongoDB operations (`find`, `aggregate`, `insertMany`, etc.) from SQL operations (`SELECT`, `JOIN`, `CREATE TABLE`, migrations, ORM ops)
- **Per-suite database seeding in swarm** (autonomous-tests-swarm): each agent's task description includes explicit lifecycle commands adapted for `swarm-{N}` namespace
- **Context Reset Advisory** (Phase 9 / Phase 8): all three skills now display a prominent reminder to run `/clear` before invoking another skill to free context window tokens
- **AskUserQuestion hook** added to autonomous-tests and autonomous-tests-swarm: all three skills now have identical hooks (ExitPlanMode + AskUserQuestion) for consistent behavior
- **Source Document Cleanup** (autonomous-fixes Phase 7): after all findings are resolved, offers to remove source documents (pending-fixes, test-results) via `AskUserQuestion`. Fix-results are never removed — they're the permanent record.
- **Testing priorities prompt** (autonomous-tests + swarm): on every returning run, prompts the user to update `testingPriorities` with current pain points. "None" clears cached priorities so agents start fresh. Updated priorities feed into the Feature Context Document cascaded to all agents.

### Changed
- **Sequential execution reworked** (autonomous-tests): now creates one task per suite with a fresh agent spawned for each — agent is shut down after completing its suite, and a new agent is spawned for the next. This keeps context clean and avoids token exhaustion from accumulated state.
- **Trust verification uses AskUserQuestion** in all three skills: the hook ensures the approval prompt is always shown even in `dontAsk` or bypass mode
- **Setup scripts install 4 items** (up from 3): ExitPlanMode hook, AskUserQuestion hook, Agent Teams flag, and model — for both autonomous-tests and autonomous-tests-swarm

### Fixed
- **Config trust hash mismatch between skills**: All three skills now re-stamp the trust hash at the end of Phase 0 after all config modifications (adding `fixResults`, `credentialType`, service re-scans, `swarm` section). Previously, config modifications happened before or after the trust check without re-stamping, causing false "config changed" warnings when switching between skills.

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
