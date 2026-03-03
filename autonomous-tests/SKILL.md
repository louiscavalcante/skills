---
name: autonomous-tests
description: 'Run autonomous E2E tests. Args: staged | unstaged | N (last N commits) | working-tree
  | file:<path> | rescan (default: working-tree with smart doc analysis). Example: /autonomous-tests 3 file:docs/feature.md'
argument-hint: 'staged | unstaged | N | working-tree | file:<path> | rescan'
disable-model-invocation: true
allowed-tools: Bash(*), Read(*), Write(*), Edit(*), Glob(*), Grep(*), Agent(*),
  EnterPlanMode(*), ExitPlanMode(*), TaskCreate(*),
  TaskUpdate(*), TaskList(*), TaskGet(*), TeamCreate(*),
  SendMessage(*), TeamDelete(*)
hooks:
  PreToolUse:
    - matcher: ExitPlanMode
      hooks:
        - type: command
          command: "echo '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\"}}'"
---

## Dynamic Context

- Args: $ARGUMENTS
- Branch: !`git branch --show-current`
- Unstaged: !`git diff --stat HEAD 2>/dev/null | tail -5`
- Staged: !`git diff --cached --stat 2>/dev/null | tail -5`
- Commits: !`git log --oneline -5 2>/dev/null`
- Docker: !`docker compose ps 2>/dev/null | head -10 || echo "No docker-compose found"`
- Config: !`test -f .claude/autonomous-tests.json && echo "YES" || echo "NO -- first run"`
- Agent Teams: !`python3 -c "import json;s=json.load(open('$HOME/.claude/settings.json'));print('ENABLED' if s.get('env',{}).get('CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS')=='1' else 'DISABLED')" 2>/dev/null || echo "DISABLED -- settings not found"`
- Capabilities: !`python3 -c "import json;c=json.load(open('.claude/autonomous-tests.json')).get('capabilities',{});mcps=len(c.get('dockerMcps',[]));ab='Y' if c.get('frontendTesting',{}).get('agentBrowser') else 'N';pw='Y' if c.get('frontendTesting',{}).get('playwright') else 'N';sc='Y' if c.get('stripeCli',{}).get('available') else 'N';print(f'MCPs:{mcps} agent-browser:{ab} playwright:{pw} stripe-cli:{sc} scanned:{c.get(\"lastScanned\",\"never\")}')" 2>/dev/null || echo "NOT SCANNED"`

## Role

Project-agnostic autonomous E2E test runner. Exercise features against the live LOCAL stack, verify state at every step, produce documentation, never touch production.

## Arguments: $ARGUMENTS

| Arg | Meaning |
|---|---|
| _(empty)_ | Default: working-tree (staged + unstaged) with smart doc analysis |
| `staged` | Staged changes only |
| `unstaged` | Unstaged changes only |
| `N` (number) | Last N commits only (e.g., `1` = last commit, `3` = last 3) |
| `working-tree` | Staged + unstaged changes (same as default) |
| `file:<path>` | Use a `.md` doc as additional test context (relative to project root). Combinable with other args. |
| `rescan` | Force re-scan of capabilities regardless of cache. Combinable with other args. |

Args are space-separated. `file:` prefix is detected and the path validated as an existing `.md` file relative to project root. Multiple args can be combined (e.g., `staged file:docs/feature.md rescan`).

Smart doc analysis is always active: identify which `docs/` files are relevant to the changed code by path, feature name, and cross-references — read only those, never all docs.

Print resolved scope, then proceed without waiting.

---

## Phase 0 — Configuration

**Step 0: Prerequisites Check**

Read `~/.claude/settings.json` and check two things:

1. **Agent teams feature flag**: verify `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is `"1"`. If missing or not `"1"`, **STOP** and tell the user:
   > Agent teams are required for this skill but not enabled. Run: `bash <skill-dir>/scripts/setup-hook.sh`
   > This enables the `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` flag and the ExitPlanMode approval hook in your settings.
   Do not proceed until the flag is confirmed enabled.

2. **ExitPlanMode hook** (informational): if the `PreToolUse` → `ExitPlanMode` hook is not present, inform the user:
   > The `ExitPlanMode` approval hook ensures test plans require your approval before execution (even in `dontAsk` mode). This skill includes it as a skill-scoped hook, so it works automatically during `/autonomous-tests` runs. To also enable it globally, the setup script above already handles it.
   Then continue — do not block on this.

**Step 1: Capabilities Scan**

Scan triggers: `rescan` argument is present, `capabilities` section is missing from config, or `capabilities.lastScanned` is older than `capabilities.rescanThresholdDays` (default 7 days).

If none of the triggers are met, skip this step and use cached capabilities.

When triggered, run three checks in parallel:

1. **Docker MCP Discovery**: Use `mcp-find` to search for available MCPs (e.g., query "stripe", "database", "testing"). For each result, record `name`, `description`, infer `mode` from context (sandbox/staging/local/unknown), and set `safe: true` only for well-known sandbox MCPs. Agents can later `mcp-add` safe MCPs at runtime. If `mcp-find` is unavailable or errors, set `dockerMcps` to an empty array and continue.

2. **Frontend Testing**: Run `which agent-browser` to check for agent-browser availability. Check for playwright via `which playwright` or `npx playwright --version`. Set booleans in `frontendTesting.agentBrowser` and `frontendTesting.playwright`.

3. **Stripe CLI**: Run `which stripe`. If available, run `stripe config --list 2>/dev/null` to detect mode. If output contains `sk_live_` keys → set `mode: "live"`, `blocked: true` → **STOP and warn user**: "Stripe CLI is configured with live keys. Autonomous tests will NOT use Stripe CLI to prevent production charges. Switch to test keys or unset live keys to enable Stripe testing." If `sk_test_` found → `mode: "sandbox"`, `blocked: false`. Otherwise `mode: "unknown"`, `blocked: false`. If `which stripe` fails, set `available: false`.

Write results to `capabilities` in config with `lastScanned` set to current UTC time (obtained via `date -u`).

**Step 2: Run `test -f .claude/autonomous-tests.json && echo "CONFIG_EXISTS" || echo "CONFIG_MISSING"` in Bash.**

Schema reference: `references/config-schema.json`.

### If output is `CONFIG_EXISTS` (returning run):

1. Read `.claude/autonomous-tests.json`
2. **Validate config version**: check that `version` equals `4` and that the required fields (`project`, `database`, `testing`) exist. If `version` is `3`, perform **v3→v4 migration**: add an empty `capabilities` section (with `lastScanned: null`), bump `version` to `4`, inform the user: "Config migrated from v3 to v4. Capabilities will be scanned on this run." Then continue with the capabilities scan in Step 1 above. If version is less than `3` or required fields are missing, warn the user and re-run the first-run setup below instead.
   **Ensure `documentation.fixResults`**: if the `documentation` section exists but `fixResults` is missing, add `"fixResults": "docs/_autonomous/fix-results"` as the default path. This enables the autonomous-fixes loop.
   **Ensure `userContext.credentialType`**: if `userContext.testCredentials` exists but `userContext.credentialType` is missing or empty, prompt the user for each credential role: "Is `{role-name}` **token-based** (API key, JWT — stateless, parallel-safe) or **session-based** (cookie, login — stateful, sequential-only)?" Save answers to `userContext.credentialType`. This determines whether agents can run in parallel with a single credential. Only prompt once — skip if `credentialType` already has entries for all credential roles.
3. **Verify config trust**: compute a SHA-256 hash of the config content (excluding the `_configHash`, `lastRun`, and `capabilities` fields) by running: `python3 -c "import json,hashlib;d=json.load(open('.claude/autonomous-tests.json'));[d.pop(k,None) for k in ('_configHash','lastRun','capabilities')];print(hashlib.sha256(json.dumps(d,sort_keys=True).encode()).hexdigest())"`. Then check if this hash exists in the **trust store** at `~/.claude/trusted-configs/` (the trust file is named after a hash of the project root: `python3 -c "import hashlib,os;print(hashlib.sha256(os.path.realpath('.').encode()).hexdigest()[:16])"` + `.sha256`). If the trust file is missing or its content doesn't match the computed hash, the config has not been approved by this user — **show the config to the user for confirmation, but redact all values in `userContext.testCredentials`** — display only the role names (keys) with values replaced by `"********"`. Never output raw credential values, env var references, or descriptions from this field. This prevents accidental exposure even if raw secrets were stored in the config. If confirmed, write the new hash to the trust store file (`mkdir -p ~/.claude/trusted-configs/` first). This prevents a malicious config committed to a repo from bypassing approval, since the trust store lives outside the repo in the user's home directory.
4. Re-scan for new services and update config if needed
5. Get current UTC time by running `date -u +"%Y-%m-%dT%H:%M:%SZ"` in Bash, then update `lastRun` with that exact value (never guess the time)
6. If `userContext` is missing or all arrays are empty, run the **User Context Questionnaire** below once, then save answers to config
7. **Skip to Phase 1** — do NOT run first-run steps below

### If output is `CONFIG_MISSING` (first run only):

1. **Auto-extract** from CLAUDE.md files + compose files + env files + package manifests
2. **Detect project topology** — set `project.topology` to one of:
   - `single` — one repo, one project
   - `monorepo` — one repo, multiple packages (detected via: workspace configs like `lerna.json`, `nx.json`, `turbo.json`, `pnpm-workspace.yaml`; multiple `package.json` in subdirs; or conventional directory structures like `backend/` + `frontend/`, `server/` + `client/`, `api/` + `web/`, `packages/`)
   - `multi-repo` — separate repos that work together as a system (detected via: CLAUDE.md references to other paths, sibling directories with their own `.git`, shared docker-compose networking, cross-repo API URLs like `localhost:3000` called from another project)
3. **Discover related projects** — scan for sibling directories with `.git` or `package.json`, grep CLAUDE.md and compose files for paths outside the project root. For each candidate found, ask the user: "Is `{path}` part of this system? What is its role?" Populate the `relatedProjects` array with confirmed entries.
4. **Capabilities scan** — run Step 1 above (capabilities scan) before the User Context Questionnaire so detected capabilities can inform the config proposal.
5. **User Context Questionnaire** — present all questions at once, accept partial answers:
   - Any known flaky areas or intermittent failures?
   - Test user credentials to use (reference env var names or role names, never raw values)?
   - For each credential: is it **token-based** (API key, JWT — stateless, parallel-safe) or **session-based** (cookie, login — stateful, sequential-only)? Default: session.
   - Any specific testing priorities or focus areas?
   - Any additional notes for the test runner?
   Store answers in the `userContext` section of the config. Store credential type answers in `userContext.credentialType` (e.g., `{"admin": "token", "member": "session"}`).
6. **Propose config** → STOP and wait for user to confirm → write config
7. **Stamp config trust**: after writing, compute the config hash with `python3 -c "import json,hashlib;d=json.load(open('.claude/autonomous-tests.json'));[d.pop(k,None) for k in ('_configHash','lastRun','capabilities')];print(hashlib.sha256(json.dumps(d,sort_keys=True).encode()).hexdigest())"` and write the result to the trust store at `~/.claude/trusted-configs/{project-hash}.sha256` (create the directory if needed). This marks the config as user-approved in a location outside the repo that cannot be forged by a committed file.
8. If project CLAUDE.md < 140 lines and lacks startup instructions, append max 10 lines.

## Phase 1 — Safety

**ABORT if any production indicators found** in `.env` files: `sk_live_`, `pk_live_`, `*LIVE*SECRET*`, `NODE_ENV=production`, production DB endpoints (RDS, Atlas without dev/stg/test), non-local API URLs. Show variable NAME only, never the value. Run `sandboxCheck` commands from config. Verify Docker is local.

## Phase 2 — Service Startup

For each service in config **and each related project with a `startCommand`**: health check → if unhealthy, start + poll 30s → if still unhealthy, STOP for user guidance. Start webhook listeners in background. Tail logs for errors during execution.

## Phase 3 — Autonomous Feature Identification & Discovery

All identification is fully autonomous — derive everything from the code diff and codebase. Never ask the user what to test.

1. Get changed files from git based on scope arguments — **include related projects** (`relatedProjects[].path`) when tracing cross-project dependencies (e.g., backend API change that affects webapp pages)
2. **File reference processing**: if `file:<path>` was provided, read the `.md` file. Extract feature descriptions, acceptance criteria, endpoints, edge cases, and any test scenarios described in the doc. This supplements (doesn't replace) diff-based discovery — merge file reference insights with diff analysis.
3. Read every changed file. For each, build a **feature map**:
   - API endpoints affected (routes, controllers, handlers)
   - Database operations (queries, writes, schema changes, index usage)
   - External service integrations (webhooks, SDK calls, third-party APIs)
   - Business logic and validation rules
   - Authentication/authorization flows touched
   - Signal/event chains (pub/sub, queues, outbox patterns)
4. Trace the full dependency graph: callers → changed code → callees. Follow imports across files and project boundaries to understand the complete blast radius.
5. **Smart doc analysis**:

   **a. Standard doc analysis**: identify docs relevant to the changed code by matching file paths, feature names, endpoint references, and `testing.contextFiles` entries. Scan the `docs/` tree but read only relevant files — never read all docs indiscriminately. Skip purely historical or unrelated docs.

   **b. _autonomous folder scan**: scan the configured documentation output directories (`documentation.testResults`, `documentation.pendingFixes`, `documentation.pendingGuidedTests`, `documentation.pendingAutonomousTests` paths from config). Match filenames — which contain `{feature-name}` — against current features, endpoints, and files from the feature map. For matches, read **only** the Summary and Issues Found sections (do not read full documents). Extract:
   - Previously failing tests for the same features
   - Known bugs and pending fixes related to current changes
   - Guided tests that may now be automatable (e.g., agent-browser is now available)
   - Pending autonomous tests queued from earlier runs that target the same features

   Feed extracted findings as a "Prior Test History" section in the Feature Context Document.

   **c. Fix completion scan**: Scan pending-fixes docs for `### Resolution` blocks. Items with `Status: RESOLVED` and `Verification: PASS` become **regression targets** — add them to the test plan for re-verification. Scan the `documentation.fixResults` directory for documents with `Ready for Re-test: YES` — these are **priority re-test targets** from recent fix cycles and should be tested first.

6. Produce a **Feature Context Document** (kept in memory, not written to disk) summarizing: all features touched, all endpoints, all DB collections/tables affected, all external services involved, all edge cases identified from reading the code (error handlers, validation branches, race conditions, retry logic), prior test history from `_autonomous/` scans, file reference content (if provided), and available capabilities from config. This document is cascaded to every agent in Phase 5.

## Phase 4 — Test Plan (Plan Mode)

**Enter plan mode (Use /plan).** The plan MUST start with a "Context Reload" section as **Step 0** containing:
- Instruction to re-read this skill file (the SKILL.md that launched this session)
- Instruction to read the config: `.claude/autonomous-tests.json`
- Instruction to read the templates: the `references/templates.md` file from this skill
- The resolved scope arguments: `$ARGUMENTS`
- The current branch name and commit range being tested
- Any related project paths involved
- Key findings from Phase 3 (affected modules, endpoints, dependencies)
- The `userContext` from config (flaky areas, testing priorities, notes)
- Credential assignment plan for agent teams (see Phase 5)

This ensures that when context is cleared after plan approval, the executing agent can fully reconstruct the session state.

Then design test suites covering **all** of the following categories:

1. **Happy path** — normal expected flows end-to-end
2. **Invalid inputs & validation** — malformed data, missing fields, wrong types, boundary values
3. **Duplicate/idempotent requests** — send the same API call 2-3 times rapidly, verify no duplicate DB records, no double charges, no duplicate side-effects (emails, webhooks, events)
4. **Error handling** — trigger every error branch visible in the diff (network failures, invalid state transitions, auth failures, permission denials)
5. **Unexpected database changes** — verify no orphaned records, no missing references, no unintended field mutations, no index-less slow queries on new fields
6. **Race conditions & timing** — concurrent writes to same resource, out-of-order webhook delivery, expired tokens mid-flow
7. **Security** — comprehensive attack surface analysis covering:
   - *Injection attacks*: SQL, NoSQL, command injection, LDAP injection, XPath injection, template injection (SSTI), header injection, log injection
   - *Cross-site attacks*: XSS (stored, reflected, DOM-based), CSRF, clickjacking
   - *Authentication/Authorization*: auth bypass, broken access control, privilege escalation, insecure session management, missing MFA verification, JWT manipulation (alg:none, key confusion)
   - *Data exposure*: sensitive data in responses (see API Response Security above), verbose error messages, stack traces in production-like responses, internal metadata leakage, information disclosure via timing attacks
   - *Input handling as attack vectors* — treat ALL user-controlled inputs as potential attack surfaces: file uploads (abnormal sizes, malformed content, zip bombs, polyglot files, path traversal in filenames, content-type mismatch), API payloads (oversized payloads, deeply nested objects, type confusion, prototype pollution), query parameters (injection, parameter pollution, encoding bypass), headers (host header injection, SSRF via forwarded headers), request volume (excessive requests/rate limiting, resource exhaustion, ReDoS patterns)
   - *Infrastructure*: SSRF, path traversal, insecure deserialization, components with known vulnerabilities, security misconfiguration, insufficient logging/monitoring
   - *Compliance*: data minimization violations, unnecessary PII collection, missing consent verification, retention policy violations

   All security findings go into the `### Vulnerabilities` subsection of `## Issues Found` in test-results (not mixed into `### Requires Fix`). Each vulnerability entry includes: (1) clear risk explanation, (2) realistic exploitation scenario, (3) regulatory/operational impact, (4) recommended mitigation strategy, (5) priority ranking: data leaks > credential exposure > privilege escalation > DoS risks > compliance violations
8. **Edge cases from code reading** — every `if/else`, `try/catch`, guard clause, and fallback in the changed code should have at least one test targeting it
9. **Regression** — existing unit tests if configured, plus re-verify any previously broken flows

Each suite needs: name, objective, pre-conditions, steps with expected outcomes, teardown, and explicit **verification queries** (DB checks, log checks, API response checks). **Wait for user approval.**

## Phase 5 — Execution (Agent Teams)

Use `TeamCreate` to create a test team. Spawn `general-purpose` Agents as teammates — one per approved suite. **Always use `model: "opus"` when spawning agents** (Opus 4.6 has adaptive reasoning/thinking built-in — no budget to configure, it thinks as deeply as needed automatically). Coordinate via `TaskCreate`/`TaskUpdate` and `SendMessage`.

**Credential sharing — CRITICAL**: Assign each agent a **distinct test credential** from `userContext.testCredentials` to prevent session conflicts (e.g., one agent logging in invalidates another's token). Check `userContext.credentialType` for each role — `"token"` means stateless (API key, JWT) and is parallel-safe even with a single credential; `"session"` (or absent — the default) means stateful (cookie, login session) and requires sequential execution if shared. If only one credential exists **and** its type is `"session"` (or unset), run agents **sequentially** — never in parallel with shared session-based auth. If only one credential exists but its type is `"token"`, agents may run in **parallel** since token-based auth is stateless and concurrent use does not cause conflicts. Include only the **role name** (key from `testCredentials`) in each agent's task description — never the credential value or env var reference. Each agent must resolve its assigned credential by reading the config file or environment at runtime.

**Cascading context — CRITICAL**: Every agent MUST receive the full **Feature Context Document** from Phase 3 in its task description. This includes: all features touched, all endpoints, all DB collections affected, all external services involved, all identified edge cases, prior test history, and available capabilities. Agents need this complete picture to understand cross-feature side-effects (e.g., testing endpoint A may break endpoint B's state).

**Capability-aware execution**: Agents should leverage detected capabilities from config when relevant to their test suite. **Priority for web/frontend testing: agent-browser > Playwright** — always prefer `agent-browser` when available; only fall back to Playwright if agent-browser is unavailable or unsuitable for the specific test:
- Use `agent-browser` **first** if `frontendTesting.agentBrowser` is true and the suite involves UI testing, browser-based verification, or any web interaction
- Use Playwright **only as fallback** if `frontendTesting.playwright` is true and agent-browser is not available
- Use `mcp-add` to activate Docker MCPs from `dockerMcps` that are marked `safe: true` and relevant to the test needs (e.g., a Stripe sandbox MCP for payment tests)
- Use Stripe CLI if `stripeCli.available` is true and `stripeCli.blocked` is false for webhook forwarding, payment intent testing, or event simulation
- **NEVER** activate MCPs where `safe: false` — these may be production or unknown-mode services
- **NEVER** use Stripe CLI when `stripeCli.blocked` is true — this indicates live keys are configured

**Anomaly detection**: Each agent must actively watch for and report:
- Duplicate records created by repeated API calls
- Unexpected DB field changes outside the tested operation
- Warning/error log entries that appear during test execution
- Slow queries or missing indexes (check `docker logs` and DB explain plans)
- Orphaned or inconsistent references between collections/tables
- Auth tokens or sessions behaving unexpectedly (expired mid-flow, leaked between users)
- Any response field or status code that differs from what the code intends

**API Response Security Inspection**: Every agent must deeply analyze ALL API responses exercised during test execution and detect:

*Exposed Identifiers*:
- Internal database IDs (MongoDB ObjectIDs, auto-increment integers, UUIDs that reveal creation order)
- Sequential or guessable IDs (enumeration attacks)
- Sensitive resource references (file paths, internal URLs, infrastructure details)

*Leaked Credentials/Secrets*:
- API keys in response bodies or headers
- Tokens (JWT, OAuth, session tokens) exposed beyond intended scope
- Passwords or hashed credentials in responses
- Environment variables or config values leaked in error messages
- Cloud/infrastructure secrets (AWS keys, connection strings)

*Exposed Personal Data* (multi-regulation compliance):
- PII: names, emails, phone numbers, addresses, government IDs (CPF/SSN/etc.), dates of birth
- Sensitive personal data: health records (HIPAA), financial data, biometric data, racial/ethnic origin, political opinions, religious beliefs, sexual orientation, genetic data
- Data subject to privacy regulations:
  - **LGPD** (Brazil): all personal data of Brazilian data subjects
  - **GDPR** (EU): personal data of EU residents
  - **CCPA/CPRA** (California): personal information of California consumers
  - **HIPAA** (US): protected health information
  - Other applicable regional regulations

Each finding must be categorized by: **Severity**, **Regulatory impact** (which laws apply), **Exploitability** (how easily an attacker can leverage it), **Compliance risk** (legal/financial exposure). All API response security findings go into the `### API Response Security` subsection of `## Issues Found` in test-results documentation.

**Execution flow**:
1. Create tasks for each suite via `TaskCreate` — include: env details from config, exact test steps, verification queries, teardown instructions, the full Feature Context Document, and the **role name** of the assigned credential (agents resolve the actual value at runtime from config or env vars — never embed credential values in task descriptions)
2. Assign tasks to agents via `TaskUpdate` with `owner`
3. If credentials allow (distinct per agent, or single token-based credential), agents may run in parallel; otherwise spawn a **single `general-purpose` agent with `model: "opus"`** and run suites **sequentially** through it — never execute test suites in the main conversation
4. Report PASS/FAIL after each suite completes, including any anomalies detected
5. After all suites complete, shut down teammates via `SendMessage` with `type: "shutdown_request"`

## Phase 6 — Fix Cycle

- **Runtime-fixable** (env var, container, stuck job): fix → re-run affected suite → max 3 cycles
- **Code bug**: document with full context (file, line, expected vs actual) → ask user before proceeding

## Phase 7 — Documentation

Generate docs in dirs from config (create dirs if needed). Get filename timestamp by running `date -u +"%Y-%m-%d-%H-%M-%S"` in Bash (never guess the time). Filename pattern: `{timestamp}_{semantic-name}.md`. **Read `references/templates.md` for the exact output structure** of each file type before writing.

Generate up to four doc types based on findings:
- **test-results**: Always generated. Full E2E results with pass/fail per suite.
- **pending-fixes**: Generated when code bugs or infrastructure issues are found.
- **pending-guided-tests**: Generated when tests need browser/visual/physical-device interaction.
- **pending-autonomous-tests**: Generated when automatable tests were identified but not run (time/scope/dependency constraints).

On re-runs: if docs exist for this feature + date → append a "Re-run" section instead of duplicating.

## Phase 8 — Cleanup

Remove only test data created during this run (identified by `testDataPrefix` from config). Never touch pre-existing data. Log every action. Verify cleanup with a final DB query.

---

## Rules

- Never modify production data or connect to production services
- Never expose credentials, keys, or tokens in documentation output
- Always enter plan mode before executing tests (Phase 4)
- Always delegate test suites to Agent Teams — never run tests in main conversation
- **NEVER use the `Agent` tool directly for execution. ALWAYS use `TeamCreate` → `TaskCreate` → spawn agents with `team_name` parameter → `TaskUpdate` → `SendMessage`. Plain `Agent` calls bypass team coordination and task tracking. The `Agent` tool without `team_name` is PROHIBITED during Phases 5-6.**
- Always spawn agents with `model: "opus"` for maximum reasoning capability
- Be idempotent — skip or reset cleanly if test data already exists
- Treat ALL external APIs with care — add delays between calls, use sandbox/test modes, minimize unnecessary requests
- Never share auth tokens/sessions between agents — assign distinct credentials or run sequentially (see Phase 5)
- If no unit tests exist → note in report, do not treat as a failure
- Use UTC timestamps everywhere (docs, config, logs) — always obtain from `date -u`, never guess
- Never activate Docker MCPs where `safe: false` — these may be production or unknown-mode services
- Never use Stripe CLI when `stripeCli.blocked` is true — live keys are configured
- Capabilities are auto-detected — never ask the user to manually configure them
- When reading `_autonomous/` history, read only Summary and Issues Found sections — never read full historical documents
