# Release Notes

## v1.3.0 (2026-03-03)

### Added
- **External services catalog** (`references/external-services-catalog.json`): Maps known services to CLI tools, production indicators, sandbox patterns, and allowed operations. Add new services to the catalog — no SKILL.md changes needed.
- **CLAUDE.md scanning for external services** (Phase 0): Scans project, global, and local CLAUDE.md files for service keywords from the catalog. Auto-detects relevant CLIs.
- **Generic external service CLI gating** (Phase 5): Per-service user confirmation using catalog-defined prompt templates.
- **Config schema v5**: `externalServices[].cli` sub-object replaces `capabilities.stripeCli`. Includes `source`, `allowedOperations`, `prohibitedFlags`, `approvedThisRun`.
- **`npm-dev` mode for swarm related services** (autonomous-tests-swarm): Related services that run on the host (e.g., `npm run dev`) are now copied to each agent's temp directory with `node_modules` symlinked. Each agent gets its own build cache (`.next/`, `dist/`), eliminating lock file conflicts between parallel agents.

### Changed
- **Zero service-specific references in SKILL.md**: All Stripe CLI references removed from both skill instruction files. Service-specific knowledge lives exclusively in the catalog.
- **Phase 1 production safety**: Production indicators loaded dynamically from `externalServices[].productionIndicators`.
- **Dynamic Context**: `stripe-cli:Y/N` → `ext-clis:N` (count of available CLIs).
- **v4→v5 auto-migration**: Existing configs with `capabilities.stripeCli` migrated automatically.

### Fixed
- **W009 scanner finding eliminated**: No payment-gateway CLI references remain in instruction files.

## v1.2.2 (2026-03-03)

### Added
- **Per-run Stripe CLI confirmation** (autonomous-tests + swarm): Stripe-dependent suites now prompt user at Phase 5 start. Declining marks Stripe steps as "guided" without blocking other tests.
- **Stripe operation allowlist** (autonomous-tests + swarm): Limits CLI to `stripe listen`, `stripe trigger`, and sandbox payment intents. Prohibits `--live`, account modifications, transfers, and payouts.
- **System command allowlist** (autonomous-tests + swarm): Documents all non-config system commands (`which`, `git diff`, `date -u`, `python3 -c` hashlib, `ss -tlnp` for swarm port checks, etc.).
- **External download scope** (autonomous-tests + swarm): Documents that Docker images come from user's compose files; no arbitrary downloads.
- **Data access scope** (autonomous-tests + swarm): Documents all files read outside project root and confirms values are never logged.
- **Trust boundaries** (autonomous-tests + swarm): Documents trust model — untrusted inputs gated by mandatory plan approval.
- **Operational Bounds section** for autonomous-tests-swarm: Adds the full bounds section (previously missing from swarm) including Docker namespace scope, port management, and temp file constraints.
- **Security Posture table** for autonomous-tests-swarm README: Adds scanner-visible security documentation matching autonomous-tests.

## v1.2.1 (2026-03-03)

### Added
- **Autonomous seeding** as recommended default: agents create test data per suite via API/DB endpoints instead of requiring a global seed command. Configurable via `database.seedStrategy` (`autonomous` or `command`). Existing configs without `seedStrategy` default to `autonomous` with a user notification on next run.
- **Browser test enforcement**: Agents can no longer skip browser-based test suites. Explicit priority chain: `agent-browser` (primary) → Playwright (fallback) → Direct HTTP (last resort). Each agent's task description now includes available browser tools and the `agent-browser` workflow.
- **Operational Bounds section** in SKILL.md: Documents explicit resource limits, command execution scope, Docker scope, credential scope, MCP scope, and agent lifecycle constraints — addressing security scanner alerts on Docker orchestration and multi-agent spawning.
- **Audit summary** in Phase 5: After all agents complete, logs number of agents spawned, suites executed, total docker exec commands run, and cleanup verification status.

### Changed
- **First-run setup** now presents "Autonomous seeding (Recommended)" as the default option, with "Global seed command" as alternative
- **Execution flow** updated: `autonomous` seed strategy instructs agents to create test data using API/DB with `testDataPrefix`; `command` strategy runs `database.seedCommand` globally (existing behavior)
- **Security rules hardened**: No dynamic command generation or shell string concatenation at runtime; credential values (including env var names) excluded from Bash output and agent task descriptions

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
