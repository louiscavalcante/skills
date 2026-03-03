---
name: autonomous-tests-swarm
description: 'Run autonomous E2E tests with per-agent Docker isolation. Each agent spins up its own database, API, and services on unique ports — true parallel testing with zero credential conflicts. Args: staged | unstaged | N | working-tree | file:<path> | rescan'
argument-hint: 'staged | unstaged | N | working-tree | file:<path> | rescan'
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
- Unstaged: !`git diff --stat HEAD 2>/dev/null | tail -5`
- Staged: !`git diff --cached --stat 2>/dev/null | tail -5`
- Commits: !`git log --oneline -5 2>/dev/null`
- Docker: !`docker compose ps 2>/dev/null | head -10 || echo "No docker-compose found"`
- Docker Context: !`docker context show 2>/dev/null || echo "unknown"`
- Config: !`test -f .claude/autonomous-tests.json && echo "YES" || echo "NO -- first run"`
- Swarm Config: !`python3 -c "import json;c=json.load(open('.claude/autonomous-tests.json'));print('YES' if 'swarm' in c else 'NO -- needs setup')" 2>/dev/null || echo "NO -- config missing"`
- Agent Teams: !`python3 -c "import json;s=json.load(open('$HOME/.claude/settings.json'));print('ENABLED' if s.get('env',{}).get('CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS')=='1' else 'DISABLED')" 2>/dev/null || echo "DISABLED -- settings not found"`
- Capabilities: !`python3 -c "import json;c=json.load(open('.claude/autonomous-tests.json')).get('capabilities',{});mcps=len(c.get('dockerMcps',[]));ab='Y' if c.get('frontendTesting',{}).get('agentBrowser') else 'N';pw='Y' if c.get('frontendTesting',{}).get('playwright') else 'N';sc='Y' if c.get('stripeCli',{}).get('available') else 'N';print(f'MCPs:{mcps} agent-browser:{ab} playwright:{pw} stripe-cli:{sc} scanned:{c.get(\"lastScanned\",\"never\")}')" 2>/dev/null || echo "NOT SCANNED"`

## Role

Project-agnostic autonomous E2E test runner with **per-agent Docker isolation**. Each agent spins up its own fully isolated Docker environment (database, API, related services) on unique ports, runs migrations/seeds, executes test suites, and tears down. No shared state, no credential conflicts, true parallel testing. Never touch production.

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
   > The `ExitPlanMode` approval hook ensures test plans require your approval before execution (even in `dontAsk` mode). This skill includes it as a skill-scoped hook, so it works automatically during `/autonomous-tests-swarm` runs. To also enable it globally, the setup script above already handles it.
   Then continue — do not block on this.

**Step 1: Capabilities Scan**

Scan triggers: `rescan` argument is present, `capabilities` section is missing from config, or `capabilities.lastScanned` is older than `capabilities.rescanThresholdDays` (default 7 days).

If none of the triggers are met, skip this step and use cached capabilities.

When triggered, run three checks in parallel:

1. **Docker MCP Discovery**: Use `mcp-find` to search for available MCPs (e.g., query "stripe", "database", "testing"). For each result, record `name`, `description`, infer `mode` from context (sandbox/staging/local/unknown), and set `safe: true` only for well-known sandbox MCPs. Agents can later `mcp-add` safe MCPs at runtime. If `mcp-find` is unavailable or errors, set `dockerMcps` to an empty array and continue.

2. **Frontend Testing**: Run `which agent-browser` to check for agent-browser availability. Check for playwright via `which playwright` or `npx playwright --version`. Set booleans in `frontendTesting.agentBrowser` and `frontendTesting.playwright`.

3. **Stripe CLI**: Run `which stripe`. If available, run `stripe config --list 2>/dev/null` to detect mode. If output contains `sk_live_` keys → set `mode: "live"`, `blocked: true` → **STOP and warn user**: "Stripe CLI is configured with live keys. Autonomous tests will NOT use Stripe CLI to prevent production charges. Switch to test keys or unset live keys to enable Stripe testing." If `sk_test_` found → `mode: "sandbox"`, `blocked: false`. Otherwise `mode: "unknown"`, `blocked: false`. If `which stripe` fails, set `available: false`.

Write results to `capabilities` in config with `lastScanned` set to current UTC time (obtained via `date -u`).

**Step 2: Docker Context Detection**

1. Run `docker context ls --format '{{.Name}} {{.Current}}'` to list available contexts
2. If `docker-desktop` context exists → use it (set as current if not already: `docker context use docker-desktop`)
3. If only `default` or other contexts → use current, but inform user: "Using Docker context `{name}`. Docker Desktop context not found."
4. Store detected context in `swarm.dockerContext`

**Step 3: Config Validation**

Run `test -f .claude/autonomous-tests.json && echo "CONFIG_EXISTS" || echo "CONFIG_MISSING"` in Bash.

Schema reference: the base config uses `autonomous-tests/references/config-schema.json`. The `swarm` section uses `references/config-schema-swarm.json` from this skill.

### If output is `CONFIG_EXISTS` (returning run):

1. Read `.claude/autonomous-tests.json`
2. **Validate config version**: check that `version` equals `4` and that the required fields (`project`, `database`, `testing`) exist. If `version` is `3`, perform **v3→v4 migration**: add an empty `capabilities` section (with `lastScanned: null`), bump `version` to `4`, inform the user: "Config migrated from v3 to v4. Capabilities will be scanned on this run." Then continue with the capabilities scan in Step 1 above. If version is less than `3` or required fields are missing, warn the user and re-run the first-run setup below instead.
   **Ensure `documentation.fixResults`**: if the `documentation` section exists but `fixResults` is missing, add `"fixResults": "docs/_autonomous/fix-results"` as the default path.
3. **Verify config trust**: compute a SHA-256 hash of the config content (excluding the `_configHash`, `lastRun`, and `capabilities` fields) by running: `python3 -c "import json,hashlib;d=json.load(open('.claude/autonomous-tests.json'));[d.pop(k,None) for k in ('_configHash','lastRun','capabilities')];print(hashlib.sha256(json.dumps(d,sort_keys=True).encode()).hexdigest())"`. Then check if this hash exists in the **trust store** at `~/.claude/trusted-configs/` (the trust file is named after a hash of the project root: `python3 -c "import hashlib,os;print(hashlib.sha256(os.path.realpath('.').encode()).hexdigest()[:16])"` + `.sha256`). If the trust file is missing or its content doesn't match the computed hash, the config has not been approved by this user — **show the config to the user for confirmation, but redact all values in `userContext.testCredentials`** — display only the role names (keys) with values replaced by `"********"`. Never output raw credential values, env var references, or descriptions from this field. Use `AskUserQuestion` to prompt for approval — the hook ensures this prompt is always shown even in `dontAsk` or bypass mode. If confirmed, write the new hash to the trust store file (`mkdir -p ~/.claude/trusted-configs/` first).
4. **Testing priorities prompt**: Show the current `userContext.testingPriorities` from config (or "None set" if empty/missing). Use `AskUserQuestion` to ask: "Any pain points or testing priorities for this run?" Present the current priorities for reference and offer options including "None" to clear any cached priorities. If the user provides new priorities, replace `userContext.testingPriorities` in config. If the user selects "None", set `userContext.testingPriorities` to an empty array `[]` — this clears stale priorities so agents start fresh. If the user keeps existing priorities, no change needed. Updated priorities are cascaded to agents via the Feature Context Document in Phase 5.
5. Re-scan for new services and update config if needed
6. Get current UTC time by running `date -u +"%Y-%m-%dT%H:%M:%SZ"` in Bash, then update `lastRun` with that exact value (never guess the time)
7. If `userContext` is missing or all arrays are empty, run the **User Context Questionnaire** below once, then save answers to config
8. **Ensure `swarm` section exists** — if missing, run the Swarm Configuration Questionnaire below
9. **Re-stamp config trust**: if the config was modified during any of the steps above (steps 2, 4, 5, 7, or 8 — e.g., added `fixResults`, updated priorities, updated services, added `swarm` section), re-compute the SHA-256 hash and write it to the trust store. This prevents false "config changed" warnings on the next run of any skill. Use the same hash computation as step 3.
10. **Skip to Phase 1** — do NOT run first-run steps below

### Swarm Configuration Questionnaire (runs when `swarm` section is absent):

1. **Detect mode**: Check for compose files in `project.services[].path` and project root. If found → `mode: "compose"`. If no compose file but project uses Docker containers (detected from `project.services[].type` or `docker ps`) → `mode: "raw-docker"`. Ask user to confirm.
2. **Compose mode**: Parse compose file to extract service names and port mappings → populate `portMappings`
3. **Raw Docker mode**: Ask user which images/containers the project uses, what ports they expose, what env vars they need → populate `rawDockerServices`
4. Ask: "What initialization commands should run after services start?" (migrations, seeds, indexes, init scripts)
5. For each related project: "Does `{name}` need its own services in the agent's test stack? (e.g., webapp needs the backend API running)" → populate `relatedServices`
6. Ask: "Maximum parallel agents?" (default: 5)
7. Save swarm section to config and re-stamp config trust

No `credentialType` questions — each agent creates its own test data. Skip `userContext.testCredentials` and `credentialType` — not needed for swarm.

### If output is `CONFIG_MISSING` (first run only):

1. **Auto-extract** from CLAUDE.md files + compose files + env files + package manifests. Auto-detect and propose `database.seedCommand`, `database.migrationCommand`, and `database.cleanupCommand` by scanning compose files, `scripts/` directories, Makefiles, and package.json scripts. Common patterns: `manage.py migrate`, `manage.py seed_test_data`, `npx prisma migrate deploy`, `npx prisma db seed`, `knex migrate:latest`, `knex seed:run`.
   **Database type detection**: Explicitly detect by checking both MongoDB and SQL indicators:
   - **MongoDB**: `mongosh`/`mongo` binaries, `mongoose`/`mongodb`/`@typegoose` packages, connection strings (`mongodb://`, `MONGO_URI`, `MONGODB_URL`), `mongo`/`mongodb` containers in compose files
   - **SQL**: `psql`/`mysql`/`sqlite3` binaries, `pg`/`mysql2`/`sequelize`/`prisma`/`knex`/`typeorm`/`drizzle`/`sqlalchemy`/`django.db` packages, `DATABASE_URL` with `postgres://`/`mysql://`/`sqlite:///`, `postgres`/`mysql`/`mariadb` containers in compose files
   - Set `database.type` accordingly. If both found, ask user which is primary.
2. **Detect project topology** — set `project.topology` to one of:
   - `single` — one repo, one project
   - `monorepo` — one repo, multiple packages (detected via: workspace configs like `lerna.json`, `nx.json`, `turbo.json`, `pnpm-workspace.yaml`; multiple `package.json` in subdirs; or conventional directory structures like `backend/` + `frontend/`, `server/` + `client/`, `api/` + `web/`, `packages/`)
   - `multi-repo` — separate repos that work together as a system (detected via: CLAUDE.md references to other paths, sibling directories with their own `.git`, shared docker-compose networking, cross-repo API URLs like `localhost:3000` called from another project)
3. **Discover related projects** — scan for sibling directories with `.git` or `package.json`, grep CLAUDE.md and compose files for paths outside the project root. For each candidate found, ask the user: "Is `{path}` part of this system? What is its role?" Populate the `relatedProjects` array with confirmed entries.
4. **Capabilities scan** — run Step 1 above (capabilities scan) before the User Context Questionnaire so detected capabilities can inform the config proposal.
5. **User Context Questionnaire** — present all questions at once, accept partial answers:
   - Any known flaky areas or intermittent failures?
   - Any specific testing priorities or focus areas?
   - Any additional notes for the test runner?
   Store answers in the `userContext` section of the config. Skip credential questions — swarm agents create their own test data.
6. **Swarm Configuration Questionnaire** — run the swarm questionnaire above
7. **Propose config** → STOP and wait for user to confirm → write config
8. **Stamp config trust**: after writing, compute the config hash with `python3 -c "import json,hashlib;d=json.load(open('.claude/autonomous-tests.json'));[d.pop(k,None) for k in ('_configHash','lastRun','capabilities')];print(hashlib.sha256(json.dumps(d,sort_keys=True).encode()).hexdigest())"` and write the result to the trust store at `~/.claude/trusted-configs/{project-hash}.sha256` (create the directory if needed).
9. If project CLAUDE.md < 140 lines and lacks startup instructions, append max 10 lines.

## Phase 1 — Safety

**ABORT if any production indicators found** in `.env` files: `sk_live_`, `pk_live_`, `*LIVE*SECRET*`, `NODE_ENV=production`, production DB endpoints (RDS, Atlas without dev/stg/test), non-local API URLs. Show variable NAME only, never the value. Run `sandboxCheck` commands from config. Verify Docker is local.

## Phase 2 — Port Discovery & Environment Validation

Do NOT start the shared stack — agents start their own isolated environments.

1. **Verify Docker context**: ensure the correct Docker context is active (`docker context show`). If it doesn't match `swarm.dockerContext`, run `docker context use {swarm.dockerContext}`.
2. **Create session temp dir**: `mkdir -p /tmp/autonomous-swarm-{sessionId}` (use `date -u +%Y%m%d%H%M%S` for sessionId). Store `sessionId` for later phases.
3. **Scan for available port ranges** starting from `swarm.portRangeStart`:
   - For each planned agent (N agents for N suites, capped at `maxAgents`), check if the port range `portRangeStart + N * portStep` through `portRangeStart + N * portStep + portStep - 1` has no conflicts
   - Check conflicts via: `ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null` or Python socket binding test
   - If a range is blocked, skip it and try the next
4. Reserve ranges and store assignments for Phase 5
5. **Validate environment**:
   - Compose mode: validate compose file exists and is parseable (`docker compose -f {file} config --quiet`)
   - Raw Docker mode: validate images exist locally or can be pulled (`docker image inspect {image} || docker pull {image}`)
   - Check Docker disk space: `docker system df` — warn if space is low (agents will spin up N copies)

## Phase 3 — Autonomous Feature Identification & Discovery

All identification is fully autonomous — derive everything from the code diff and codebase. Never ask the user what to test.

1. Get changed files from git based on scope arguments — **include related projects** (`relatedProjects[].path`) when tracing cross-project dependencies (e.g., backend API change that affects webapp pages)
2. **File reference processing**: if `file:<path>` was provided, read the `.md` file. Extract feature descriptions, acceptance criteria, endpoints, edge cases, and any test scenarios described in the doc. This supplements (doesn't replace) diff-based discovery — merge file reference insights with diff analysis.
3. Read every changed file. For each, build a **feature map**:
   - API endpoints affected (routes, controllers, handlers)
   - Database operations — distinguish by type:
     - **MongoDB**: `find`, `findOne`, `aggregate`, `insertMany`, `insertOne`, `updateOne`, `updateMany`, `deleteOne`, `deleteMany`, `bulkWrite`, `createIndex`, collection creation, Mongoose/Typegoose schema changes
     - **SQL**: `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `JOIN`, `GROUP BY`, `CREATE TABLE`, `ALTER TABLE`, `CREATE INDEX`, migrations (Prisma, Knex, Sequelize, TypeORM, Drizzle, Alembic, Django), ORM operations
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
- Instruction to read the templates: `autonomous-tests/references/templates.md` (shared with autonomous-tests)
- The resolved scope arguments: `$ARGUMENTS`
- The current branch name and commit range being tested
- Any related project paths involved
- Key findings from Phase 3 (affected modules, endpoints, dependencies)
- The `userContext` from config (flaky areas, testing priorities, notes)
- The `swarm` config section
- Port assignments per agent (from Phase 2)
- Initialization commands
- Related project inclusion map (which suites need which related projects)

This ensures that when context is cleared after plan approval, the executing agent can fully reconstruct the session state.

Then design test suites covering **all** of the following categories:

1. **Happy path** — normal expected flows end-to-end
2. **Invalid inputs & validation** — malformed data, missing fields, wrong types, boundary values
3. **Duplicate/idempotent requests** — send the same API call 2-3 times rapidly, verify no duplicate DB records, no double charges, no duplicate side-effects (emails, webhooks, events)
4. **Error handling** — trigger every error branch visible in the diff (network failures, invalid state transitions, auth failures, permission denials)
5. **Unexpected database changes** — verify no orphaned records, no missing references, no unintended field mutations, no index-less slow queries on new fields
6. **Race conditions & timing** — concurrent writes to same resource, out-of-order webhook delivery, expired tokens mid-flow
7. **Security** — comprehensive attack surface analysis (injection, XSS/CSRF, auth bypass, data exposure, input handling, infrastructure, compliance — same categories as autonomous-tests)
8. **Edge cases from code reading** — every `if/else`, `try/catch`, guard clause, and fallback in the changed code should have at least one test targeting it
9. **Regression** — existing unit tests if configured, plus re-verify any previously broken flows

The plan must include per-agent environment setup: "Each agent generates a modified compose file (or docker run commands), starts its stack, runs initialization, then executes suites."

The plan must note: "If an agent's environment fails to start (compose up fails, health check timeout), its suites are reassigned to another agent's existing environment or queued for retry."

Each suite needs: name, objective, pre-conditions, steps with expected outcomes, teardown, and explicit **verification queries** (DB checks, log checks, API response checks). **Wait for user approval.**

## Phase 5 — Execution (Agent Swarm)

Use `TeamCreate` to create a test team. Spawn `general-purpose` Agents as teammates — one per suite (or group if suites share dependencies). **Always use `model: "opus"` when spawning agents**. ALL agents run in parallel — no credential conflicts possible since each agent has its own isolated environment. Coordinate via `TaskCreate`/`TaskUpdate` and `SendMessage`.

**Cascading context — CRITICAL**: Every agent MUST receive the full **Feature Context Document** from Phase 3 in its task description. This includes: all features touched, all endpoints, all DB collections affected, all external services involved, all identified edge cases, prior test history, and available capabilities. Agents need this complete picture to understand cross-feature side-effects.

**Capability-aware execution**: Same as autonomous-tests — agents leverage detected capabilities:
- Use `agent-browser` **first** if `frontendTesting.agentBrowser` is true and the suite involves UI testing
- Use Playwright **only as fallback** if agent-browser is not available
- Use `mcp-add` to activate Docker MCPs from `dockerMcps` that are marked `safe: true` and relevant
- Use Stripe CLI if `stripeCli.available` is true and `stripeCli.blocked` is false
- **NEVER** activate MCPs where `safe: false`
- **NEVER** use Stripe CLI when `stripeCli.blocked` is true

**Anomaly detection**: Same as autonomous-tests — each agent watches for duplicate records, unexpected DB changes, warning/error logs, slow queries, orphaned references, unexpected auth behavior, and response anomalies.

**API Response Security Inspection**: Same as autonomous-tests — deep analysis of all API responses for exposed IDs, leaked credentials, PII, and compliance violations.

**Execution flow**:

1. Ensure correct Docker context is active: `docker context use {swarm.dockerContext}`
2. Reserve port ranges for each agent (confirmed from Phase 2)
3. Create tasks via `TaskCreate` — each task description includes:

   **a. Environment spec**: project name (`swarm-{N}`), assigned port range, port mappings per service, Docker context to use

   **b. Environment setup (compose mode)**:
   - Read the project's compose file (path from `swarm.composeFile` and `swarm.composePath`)
   - Generate a modified compose file at `/tmp/autonomous-swarm-{sessionId}/agent-{N}/docker-compose.yml` with:
     - All host ports remapped to agent's assigned range
     - Container names namespaced via `-p swarm-{N}`
   - If related projects are needed: read their compose file, generate modified version in same dir, ensure services share a Docker network
   - Start: `docker compose -p swarm-{N} -f /tmp/autonomous-swarm-{sessionId}/agent-{N}/docker-compose.yml up -d`

   **c. Environment setup (raw Docker mode)**:
   - For each service in `swarm.rawDockerServices`:
     - `docker run -d --name swarm-{N}-{service} -p {assignedPort}:{containerPort} {envFlags} {volumeFlags} {image}`
   - Create a Docker network: `docker network create swarm-{N}-net`
   - Connect all containers: `docker network connect swarm-{N}-net swarm-{N}-{service}`
   - If related projects need raw Docker services, start them and connect to the same network

   **d. Health check**: Poll each service using remapped ports (from `portMappings[].healthCheck` with `{port}` and `{containerName}` resolved). Timeout: 60s. If unhealthy after 2 attempts, **report failure** via `SendMessage` — orchestrator redistributes suites to a healthy agent.

   **e. Initialization**: Run each command from `swarm.initialization.commands` with `{projectName}` resolved to `swarm-{N}` and `{containerName}` resolved. Wait `waitAfterStartSeconds` between start and first init command.

   **f. Related project init**: Run related project init commands if applicable

   **f2. Per-suite database seeding**: Each suite's task description MUST include explicit database lifecycle commands adapted for the agent's environment:
   - If `database.migrationCommand` exists: adapted for namespace (e.g., `docker compose -p swarm-{N} exec backend python manage.py migrate`)
   - If `database.seedCommand` exists: adapted similarly
   - `database.connectionCommand` adapted for verification queries
   - If `database.cleanupCommand` exists: adapted for post-test cleanup
   - Replace container names and project names with `swarm-{N}` namespace

   **g. Test execution**: Run assigned test suites against the agent's own API (using remapped ports in all URLs)

   **h. Results**: Report PASS/FAIL per suite with anomalies via `SendMessage`, same format as autonomous-tests

   **i. Teardown (ALWAYS — even on failure)**:
   - Compose mode: `docker compose -p swarm-{N} -f /tmp/autonomous-swarm-{sessionId}/agent-{N}/docker-compose.yml down -v --remove-orphans`
   - Raw Docker mode: `docker stop $(docker ps -q --filter name=swarm-{N}) && docker rm $(docker ps -aq --filter name=swarm-{N}) && docker network rm swarm-{N}-net`
   - Same for related project containers/compose if started
   - Remove `/tmp/autonomous-swarm-{sessionId}/agent-{N}/` directory
   - Verify no lingering containers: `docker ps -a --filter name=swarm-{N} -q`

4. Spawn agents with `team_name` and assign tasks via `TaskUpdate` with `owner`
5. All agents run in parallel
6. **Failure redistribution**: if an agent reports environment startup failure via `SendMessage`, the orchestrator:
   - Identifies which suites were assigned to the failed agent
   - Picks a healthy agent that has completed or is about to complete its suites
   - Sends the failed suites to the healthy agent via `SendMessage` (the healthy agent runs them against its already-running environment)
   - The failed agent still tears down its partially-started environment
7. After all agents complete, verify ALL Docker resources cleaned up: `docker ps -a --filter name=swarm- -q` should return empty
8. Clean up session temp dir: `rm -rf /tmp/autonomous-swarm-{sessionId}`
9. Shut down teammates via `SendMessage` with `type: "shutdown_request"`

## Phase 6 — Fix Cycle

- **Runtime-fixable** (env var, container, stuck job): fix → re-run affected suite → max 3 cycles
- **Code bug**: document with full context (file, line, expected vs actual) → ask user before proceeding

## Phase 7 — Documentation

Generate docs in dirs from config (create dirs if needed). Get filename timestamp by running `date -u +"%Y-%m-%d-%H-%M-%S"` in Bash (never guess the time). Filename pattern: `{timestamp}_{semantic-name}.md`. **Read `autonomous-tests/references/templates.md` for the exact output structure** of each file type before writing. The output format is identical to autonomous-tests.

Generate up to four doc types based on findings:
- **test-results**: Always generated. Full E2E results with pass/fail per suite.
- **pending-fixes**: Generated when code bugs or infrastructure issues are found.
- **pending-guided-tests**: Generated when tests need browser/visual/physical-device interaction.
- **pending-autonomous-tests**: Generated when automatable tests were identified but not run (time/scope/dependency constraints).

On re-runs: if docs exist for this feature + date → append a "Re-run" section instead of duplicating.

## Phase 8 — Cleanup

Remove only test data created during this run (identified by `testDataPrefix` from config). Never touch pre-existing data. Log every action. Verify cleanup with a final DB query.

Additionally, verify Docker cleanup:
- Run `docker ps -a --filter name=swarm- -q` — must return empty
- Run `docker network ls --filter name=swarm- -q` — must return empty
- Verify `/tmp/autonomous-swarm-{sessionId}` is removed
- If any orphaned resources remain, clean them up and warn the user

## Phase 9 — Context Reset Advisory

After all phases complete, display this message prominently:

> **Important**: Run `/clear` before invoking another skill (e.g., `/autonomous-fixes`) to free context window tokens and prevent stale state from interfering with the next operation.

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
- If no unit tests exist → note in report, do not treat as a failure
- Use UTC timestamps everywhere (docs, config, logs) — always obtain from `date -u`, never guess
- Never activate Docker MCPs where `safe: false`
- Never use Stripe CLI when `stripeCli.blocked` is true
- Capabilities are auto-detected — never ask the user to manually configure them
- When reading `_autonomous/` history, read only Summary and Issues Found sections — never read full historical documents
- **Always tear down agent environments, even on failure — never leave orphaned containers**
- **Never bind to ports already in use — always verify availability first**
- **Never modify the project's original compose file — only generate copies in `/tmp/autonomous-swarm-{sessionId}/`**
- **Always use `docker compose -p {projectName}` for namespace isolation**
- **Include `--remove-orphans` and `-v` in teardown to prevent volume/network leaks**
- **If compose startup fails, do NOT retry indefinitely — report failure after 2 attempts and redistribute suites**
- **Never run initialization commands against the shared/main stack — only against agent-owned stacks**
- **Always detect and use Docker Desktop context when available — prioritize over default context**
- **All temp files go in `/tmp/` (OS temp dir) — never pollute the project directory**
- **Clean up `/tmp/autonomous-swarm-{sessionId}/` at the end of every run, even on failure**
