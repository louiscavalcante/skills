# Swarm Agent Tasks

Detailed lifecycle tasks for each swarm suite agent. Embedded verbatim in plans via the self-containment mandate — each parallel agent follows this task list without needing this file post-reset.

---

## Suite Agent Lifecycle (Tasks a-l)

Each parallel suite agent executes these tasks in order within its isolated Docker environment.

### a. Spec

Receive pre-generated spec: project name `swarm-{N}`, remapped ports, Docker context, compose path. Never generate specs — use exactly what the setup agent produced.

### b. Capabilities

Use frozen capabilities snapshot from setup agent. Agents MUST NOT re-scan capabilities. The snapshot is distributed verbatim to prevent drift between agents.

### c. Compose Setup (Docker Compose services)

Verify compose config, then start: `docker compose -p swarm-{N} -f {compose-path} up -d`. Max 2 attempts. Failure after 2 attempts → report for redistribution.

### d. Raw Docker Setup (non-Compose services)

`docker run -d --name swarm-{N}-{service} ...` with remapped ports. Create and connect network `swarm-{N}-net`. Apply resource limits and Docker labels.

### e. npm-dev Setup (local process services)

`rsync` project (exclude `node_modules/.next/dist/.turbo`). Set up `node_modules` per `nodeModulesStrategy` (`symlink` → `ln -s`, `hardlink` → `cp -al` with `cp -r` fallback, `copy` → `cp -r`). Resolve env overrides (`{port}`/`{backendPort}`). Start in background (capture PID). Remap env files per `swarm.envPortMappings`.

### f. Health Check

Poll remapped ports: 60s timeout, 2 attempts per service. Healthy → proceed. Unhealthy after retries → report failure for redistribution.

### g. Initialization

Run `swarm.initialization.commands` with namespace resolution (`{projectName}` → `swarm-{N}`). Wait `waitAfterStartSeconds`. Execute related project initialization if configured.

### h. DB Seeding

1. Run adapted `migrationCommand` with `swarm-{N}` namespace
2. Capture `dbBaseline` via `connectionCommand` before any writes
3. **Seed schema analysis gate** (MANDATORY): complete schema discovery BEFORE any insert
4. Seed schema discovery: query real doc (`findOne`/`SELECT * LIMIT 1`) or read service code. Mirror schema exactly — never invent fields or change types. Add `_testPrefix` marker only.
5. Seed test data with `testDataPrefix`
6. For related project collections: use cross-project seed map
7. Hit API read endpoints (via remapped ports) to verify serialization

### h2. DB Consistency: POST_SEED

Execute POST_SEED checks against agent's namespaced DB. Compare current counts to `dbBaseline` + expected seed counts. Report PASS/WARN/FAIL.

### i. Execute

Run integration test suites against agent's API using remapped ports. Execute curl commands. Check security items. Monitor per-agent logs at `/tmp/autonomous-swarm-{sessionId}/agent-{N}/logs/`. Apply finding verification before reporting.

For E2E browser suites (sequential only — not parallelized): navigate with agent-browser, observe with chrome-devtools (if enabled), verify backend state via curl/DB.

### i2. DB Consistency: POST_TEST

Execute POST_TEST checks against agent's namespaced DB. Compare against `dbBaseline` for mutation audit. Report PASS/WARN/FAIL.

### j. Report

Return to orchestrator: PASS/FAIL per test case, security observations, log findings, DB consistency results, anomalies detected, execution timeline.

### k. Audit (when enabled)

Write `agent-{N}.json`: `schemaVersion: "1.0"`, agentId, suites executed, environment details, timeline (`{ timestamp, action, target, result }`), configuredLimits (no `docker stats`), teardown status, duration.

### l. Teardown (ALWAYS — even on failure)

1. Remove `testDataPrefix` data from namespaced DB
2. DB consistency: POST_CLEANUP — verify cleanup completeness, pre-existing data preserved, structural integrity
3. Compose: `docker compose -p swarm-{N} down -v --remove-orphans`
4. Raw Docker: `docker stop` + `docker rm` containers, `docker network rm swarm-{N}-net`
5. npm-dev: kill captured PIDs, remove copied project directories
6. Remove agent temp dir: `rm -rf /tmp/autonomous-swarm-{sessionId}/agent-{N}/`
7. Verify no lingering containers: `docker ps -a --filter name=swarm-{N} -q` → empty
