---
name: autonomous-tests-swarm
description: 'Run autonomous E2E tests with per-agent Docker isolation. Each agent spins up its own database, API, and services on unique ports — true parallel testing with zero credential conflicts. Args: staged | unstaged | N | working-tree | file:<path> | rescan | guided [description]'
argument-hint: 'staged | unstaged | N | working-tree | file:<path> | rescan | guided'
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
- Capabilities: !`python3 -c "import json;c=json.load(open('.claude/autonomous-tests.json'));caps=c.get('capabilities',{});mcps=len(caps.get('dockerMcps',[]));ab='Y' if caps.get('frontendTesting',{}).get('agentBrowser') else 'N';pw='Y' if caps.get('frontendTesting',{}).get('playwright') else 'N';ec=sum(1 for s in c.get('externalServices',[]) if s.get('cli',{}).get('available'));print(f'MCPs:{mcps} agent-browser:{ab} playwright:{pw} ext-clis:{ec} scanned:{caps.get(\"lastScanned\",\"never\")}')" 2>/dev/null || echo "NOT SCANNED"`

## Role

Project-agnostic autonomous E2E test runner with **per-agent Docker isolation**. Each agent spins up its own fully isolated Docker environment (database, API, related services) on unique ports, runs migrations/seeds, executes test suites, and tears down. No shared state, no credential conflicts, true parallel testing. Never touch production.

## Orchestrator Protocol

The main agent is the Orchestrator. It coordinates phases but NEVER executes operational work.

**Orchestrator MUST delegate to agents:**
- Bash commands (capabilities scan, health checks, port scanning, cleanup)
- Source code reading (only agents read application source)
- File generation (docs, reports)
- Test execution, fix application, verification

**Orchestrator MAY directly:**
- Read config, SKILL.md, and reference files
- Run `date -u` for timestamps, `test -f` for file checks
- Enter/exit plan mode
- Use AskUserQuestion for user interaction
- Use TeamCreate/TaskCreate/TaskUpdate/SendMessage for coordination
- Compile summaries from agent reports
- Make phase-gating decisions (proceed/stop/abort)

**Reporting hierarchy:** Agent → Orchestrator → Plan

## Arguments: $ARGUMENTS

| Arg | Meaning |
|---|---|
| _(empty)_ | Default: working-tree (staged + unstaged) with smart doc analysis |
| `staged` | Staged changes only |
| `unstaged` | Unstaged changes only |
| `N` (number) | Last N commits only |
| `working-tree` | Staged + unstaged changes (same as default) |
| `file:<path>` | `.md` doc as additional test context. Combinable. |
| `rescan` | Force re-scan capabilities. Combinable. |
| `guided` | User augmentation mode (single-agent) — bypasses git diff. Alone: prompts user. |
| `guided "description"` | Description-based: happy-path workflows only, user performs actions. Single-agent. |
| `guided file:<path>` | Doc-based: happy-path workflows only, user performs actions. Single-agent. |

Args are space-separated. `file:` prefix detected, path validated as existing `.md` relative to project root. Combinable (e.g., `staged file:docs/feature.md rescan`).

**Guided mode** — user augmentation (NOT automation):
- **Doc-based** (`guided file:<path>` or pick from `docs/`/`_autonomous/pending-guided-tests/`): happy-path workflows only.
- **Description-based** (`guided "description"` or describe when prompted): happy-path workflows only.

User performs all actions on their real device/browser. Claude provides step-by-step instructions and verifies results via DB queries/API/logs. Only happy-path workflows in guided mode. Categories 2-9 handled exclusively in autonomous mode — NEVER in guided session. No agent-browser, no Playwright — guided mode never loads or uses browser automation tools. **Single agent execution** — guided mode overrides the parallel protocol. Spawn ONE agent at a time, sequentially.

`guided` alone prompts via `AskUserQuestion`. Combinable with `rescan` but **NOT** with `staged`/`unstaged`/`N`/`working-tree`.

Smart doc analysis always active in standard mode: identify relevant `docs/` files by path, feature name, cross-references — read only those.

Print resolved scope, then proceed without waiting.

---

## Phase 0 — Bootstrap

**Step 0: Prerequisites Check** — read `~/.claude/settings.json`:

1. **Agent teams flag**: verify `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is `"1"`. If not, **STOP**: tell user to run `bash <skill-dir>/scripts/setup-hook.sh`.
2. **ExitPlanMode hook** (informational): if absent, inform user it's skill-scoped and works automatically. Continue.
3. **AskUserQuestion hook** (informational): same as above. Continue.

**Step 1: Capabilities Scan** — delegate to Explore agent.

Triggers: `rescan` present, `capabilities` missing, or `lastScanned` older than `rescanThresholdDays` (default 7). If none, use cache.

Spawn ONE Explore agent (`subagent_type: "Explore"`, no `team_name`) for three parallel checks:
1. **Docker MCP Discovery**: `mcp-find` with service names and generic queries. Record `name`, `description`, infer `mode`, `safe: true` only for sandbox MCPs. If unavailable, `dockerMcps: []`.
2. **Frontend Testing**: `which agent-browser`, `which playwright`/`npx playwright --version` → set `frontendTesting` booleans.
3. **External Service CLI Detection**: load `autonomous-tests/references/external-services-catalog.json`. Scan CLAUDE.md files for `claudeMdKeywords`. For matches: run `detectionCommand` → `modeDetection.command` → pattern-match: `production` → blocked; `sandbox` → allowed; no match → allowed. Populate `cli.*` fields. Merge into `externalServices[]`.

Write to `capabilities` with `lastScanned` = current UTC time.

**CLAUDE.md deep scan**: `find . -maxdepth 3 -name "CLAUDE.md" -type f 2>/dev/null` + `~/.claude/CLAUDE.md` + `.claude/CLAUDE.md`. Cache list. Delegate reading to Explore agent.

**Step 2: Docker Context Detection** — `docker context ls`. Prefer `docker-desktop` (switch if needed). Store in `swarm.dockerContext`.

**Step 3: Config Validation** — `test -f .claude/autonomous-tests.json`.

Schema: base → `autonomous-tests/references/config-schema.json`; swarm → `references/config-schema-swarm.json`.

**Config hash method**: `python3 -c "import json,hashlib;d=json.load(open('.claude/autonomous-tests.json'));[d.pop(k,None) for k in ('_configHash','lastRun','capabilities')];print(hashlib.sha256(json.dumps(d,sort_keys=True).encode()).hexdigest())"`

### If `CONFIG_EXISTS` (returning run):

1. Read config
2. **Validate version**: require `version: 5` with `project`, `database`, `testing`. v4→v5: move `*Cli` fields to `externalServices[].cli`. v3→v4→v5: add empty `capabilities` first. < v3: warn, re-run first-run. Ensure `documentation.fixResults` defaults to `"docs/_autonomous/fix-results"` if missing.
3. **Verify trust**: compute hash via **Config hash method**. Check trust store (`~/.claude/trusted-configs/{project-hash}.sha256`). Mismatch → show config (redact `testCredentials` as `"********"`) → `AskUserQuestion` → write hash on approval.
4. **Testing priorities**: show current, `AskUserQuestion` for updates. New → replace. "None" → `[]`. Cascade via Feature Context Document.
5. Re-scan services, update config if needed
6. Update `lastRun` via `date -u +"%Y-%m-%dT%H:%M:%SZ"`
7. If `userContext` empty, run User Context Questionnaire
8. If `swarm` section missing, run Swarm Configuration Questionnaire
9. If config modified, re-stamp trust via **Config hash method**
10. Skip to Phase 1

### Swarm Configuration Questionnaire (when `swarm` absent):

1. **Detect mode**: compose files found → `"compose"`, Docker without compose → `"raw-docker"`. Confirm with user.
2. **Compose mode**: parse compose → extract services, ports → `portMappings`
3. **Env file detection**: parse `env_file:` directives → `swarm.envFiles` (`source: "compose-env_file"`). Scan dirs for `.env`/`.env.local` → `source: "auto-detected"`. Detect port variables: value matches `containerPort` + name has `PORT` → `type: "direct"`; value has `localhost:{port}` → `type: "url"`. Present via `AskUserQuestion`. Store confirmed mappings.
4. **Raw Docker mode**: ask for images, ports, env vars → `rawDockerServices`
5. Ask initialization commands
6. Per related project: detect mode (compose/raw-docker/npm-dev with `startCommand`, `projectPath`, `envOverrides`)
7. Max parallel agents (default: 5)
8. Resource limits (opt-in): `memory`, `cpus`, `readOnlyRootfs` + `tmpfsMounts`
9. Save and re-stamp trust

No `credentialType` questions — each agent creates its own test data.

### If `CONFIG_MISSING` (first run):

Delegate auto-extract to Explore agent:
1. **Auto-extract** from CLAUDE.md files + compose + env + manifests. Detect `seedCommand`, `migrationCommand`, `cleanupCommand`. **Database type detection**: MongoDB indicators (`mongosh`, `mongoose`/`mongodb`/`@typegoose`, `mongodb://` URIs, mongo containers) vs SQL indicators (`psql`/`mysql`/`sqlite3`, ORM packages, `postgres://`/`mysql://` URIs, SQL containers). Both found → ask user.
2. **Topology**: `single`, `monorepo` (workspace configs, multiple package.json, conventional dirs), `multi-repo` (cross-references, sibling `.git`, shared networking)
3. **Related projects**: scan siblings, grep CLAUDE.md/compose for external paths. Confirm each with user.
4. **Capabilities scan** — run Step 1
5. **User Context Questionnaire**: flaky areas? priorities? notes? (No credential questions.)
6. **Swarm Configuration Questionnaire**
7. Propose config → wait for approval → write
8. Stamp trust via **Config hash method**
9. If CLAUDE.md < 140 lines and lacks startup instructions, append max 10 lines

## Phase 1 — Safety & Environment

Single objective: verify safe, reserve ports, validate Docker.

Spawn ONE general-purpose agent. Agent performs:

1. **Production scan**: `.env` files for `productionIndicators`, `*LIVE*SECRET*`, `NODE_ENV=production`, production DB endpoints, non-local URLs. Show variable NAME only.
2. Run `sandboxCheck` commands from config
3. Verify Docker is local
4. Verify Docker context matches `swarm.dockerContext` (switch if needed)
5. Create `/tmp/autonomous-swarm-{sessionId}` (`date -u +%Y%m%d%H%M%S` for sessionId)
6. Scan port ranges from `swarm.portRangeStart` per agent via `ss -tlnp`/`netstat -tlnp` or socket test. Skip conflicts.
7. Reserve and store assignments
8. Validate: compose → `docker compose -f {file} config --quiet`; raw Docker → `docker image inspect || docker pull`; disk space → `docker system df`
9. If `swarm.audit.enabled` (default true): `mkdir -p .../audit/`, write `session.json` (`schemaVersion: "1.0"`, sessionId, timestamp, branch, scope, agent count, limits)

Agent reports: safety assessment, port assignments, validation results, audit status.

Orchestrator: **ABORT** if production detected. Keep port assignments for Phase 3.

## Phase 2 — Discovery

Fully autonomous — derive from code diff, codebase, or guided source. Never ask user what to test.

Spawn ONE Explore agent (`subagent_type: "Explore"`, no `team_name`).

### Standard mode

1. Get changed files from git (include `relatedProjects[].path` for cross-project tracing)
2. If `file:<path>` provided, read `.md` → extract features, criteria, endpoints, edge cases
3. Spawn Explore agent with: changed files, file reference content, `relatedProjects[]`, `testing.contextFiles`, CLAUDE.md paths, `documentation.*` paths. Agent performs:
   - **Feature map**: endpoints, DB operations (MongoDB: `find`/`aggregate`/`insertMany`/`updateOne`/`deleteMany`/`bulkWrite`/`createIndex`, schema changes; SQL: `SELECT`/`INSERT`/`UPDATE`/`DELETE`/`JOIN`/`GROUP BY`/`CREATE TABLE`/`ALTER TABLE`/`CREATE INDEX`, migrations, ORM ops), external services, business logic, auth flows, signal chains
   - **Dependency graph**: callers → changed code → callees, across files and projects
   - **Smart doc analysis**: (a) match paths/features/endpoints against `docs/` tree, (b) `_autonomous/` scan — Summary + Issues Found only, extract prior failures/bugs, (c) fix completion scan — `Status: RESOLVED` + `Verification: PASS` → regression targets, `Ready for Re-test: YES` → priority re-test
   - **Edge case inventory**: error handlers, validation branches, race conditions, retry logic
4. Receive agent report

### Guided mode (user augmentation — single agent)

**Validate**: `guided` + `staged`/`unstaged`/`N`/`working-tree` → STOP with error message. Combinable with `rescan` only.

1. **Resolve source**: `guided file:<path>` → doc-based; `guided "description"` → description-based; `guided` alone → `AskUserQuestion` (pick doc or describe)
2. Spawn Explore agent with guided source + mode type + same context as standard. Agent performs deep feature analysis (keywords → Glob/Grep → read → trace imports) plus same feature map, dependency, doc analysis, edge case work. Agent also identifies: DB seed requirements per test, external service setup needs, prerequisite state for each happy-path workflow.
3. Receive report. Orchestrator extracts only happy-path workflows — discard security, edge case, validation, race condition findings (those are autonomous-only).

### Regression Scope Analysis (conditional — after Explore report)

Check the Explore agent's report for re-test indicators:
- Fix-results entries with `Ready for Re-test: YES`
- Pending-fixes entries with `### Resolution` → `Status: RESOLVED` + `Verification: PASS`

**If NEITHER found** → skip, compile normal Feature Context Document below.

**If FOUND** → Regression mode. Orchestrator compiles from the Explore report (no additional agent — this is a filtering/cross-referencing operation on data already gathered):

1. **Fix manifest**: per resolved item — ID, title, files modified, what was done, source path, original test IDs, verification details. V-prefix: add OWASP + attack vector.
2. **1-hop impact zone**: from the Explore agent's dependency graph, extract only direct callers and direct callees of each modified file. Discard beyond 1-hop.
3. **Prior test mapping**: cross-reference `Source` paths and `Original Test IDs` against test-results to identify which suites and test IDs originally failed. If `Original Test IDs` absent (legacy fix-results), fall back to parsing `Source` path → open pending-fixes → extract `Test ID`.
4. **Prior pass mapping**: from the same test-results docs, extract suites/tests that PASSED — these are candidates for exclusion.
5. **Blast radius check**: if modified files' combined 1-hop zone covers >60% of the feature map → fall back to full Feature Context Document, note "blast radius exceeds regression threshold — running full scope."

Compile **Targeted Regression Context Document** (replaces Feature Context Document for Phase 3):
- Regression mode header (type, fix-results source path, original test-results path, fix date, item count)
- Fix manifest (per item: ID, title, files modified, description, original test IDs, 1-hop callers/callees)
- Regression test scope: Required tests (verify fix scenarios + 1-hop impact) and Excluded areas (unaffected suites from original run, with reason)
- Prior passing tests summary (context for agents — avoid re-testing)
- Environment/capabilities (same as Feature Context Document)

### Feature Context Document (standard/guided modes — skipped in regression mode)

Compile from agent report (do NOT re-read analyzed files). Contains: features, endpoints, DB tables/collections, external services, edge cases, prior history, capabilities. Guided mode adds `Mode:` and `Source:` at top. Cascaded to all agents in Phase 4.

## Phase 3 — Plan (Plan Mode)

**Enter plan mode.** Plan starts with:

**Step 0 — Context Reload**: re-read SKILL.md, config, templates (`autonomous-tests/references/templates.md`). Restore: resolved `$ARGUMENTS`, branch, commit range, Phase 2 findings, `userContext`, swarm config, port assignments, init commands, related project map. If regression mode: fix manifest, 1-hop impact zone, original test IDs, Targeted Regression Context Document. If guided: type, source, and full guided test list with per-test seed requirements.

**Tool loading gate**: If autonomous mode needs agent-browser/Playwright, list tools and prompt user via AskUserQuestion before plan approval. Declined tools excluded from plan. Guided mode: NEVER include browser automation tools — skip this gate entirely.

**Self-containment mandate** — the plan MUST embed directly (not reference "above" or prior phases):
1. All test suites with full details (name, objective, pre-conditions, steps, expected outcomes, teardown, verification)
2. Feature Context Document (condensed but complete)
3. Service Readiness Report from Phase 1 (port assignments, health status)
4. Per-suite agent spawn instructions with resolved values (swarm-{N} spec, ports, Docker context, compose path, capabilities snapshot, Feature Context Document)
5. Config paths: `documentation.*`, `database.connectionCommand`, `testing.unitTestCommand`, `testDataPrefix`
6. Swarm config: port assignments, init commands, related project map
7. If guided: per-test DB seed commands, user-facing step-by-step instructions, and verification queries

- Execution Protocol — autonomous mode (embed verbatim — orchestrator uses this after context reset):
  ```
  TEAM: TeamCreate → general-purpose team (team_name for all agents)
  MODEL: Always model: "opus"
  SETUP AGENT: Spawn first (general-purpose, opus, team_name). Creates agent dirs, generates modified compose/docker scripts with remapped ports, copies+remaps env files, validates configs, freezes capabilities snapshot, applies resource limits + Docker labels, reads source files, reports via SendMessage. Shut down before suite agents.
  FLOW: PARALLEL — multiple suite agents simultaneously:
    1. Set Docker context
    2. Confirm port ranges
    3. TaskCreate per suite (agent spec: project name swarm-{N}, ports, Docker context, compose path, frozen capabilities, Feature Context Document)
    4. Spawn agents with team_name, assign via TaskUpdate
    5. All agents execute in parallel
  FAILURE: redistribute failed agent's suites to healthy agents. Failed agent tears down immediately.
  POST-COMPLETION:
    - Docker cleanup: filter by name (swarm-) + labels (com.autonomous-swarm.session={sessionId})
    - Merge audit logs → audit-summary.json
    - rm -rf /tmp/autonomous-swarm-{sessionId}
  SHUTDOWN: SendMessage type: "shutdown_request" to all teammates
  ```

- Execution Protocol — guided mode (embed verbatim):
  ```
  MODE: User augmentation
  NO BROWSER AUTOMATION: agent-browser and Playwright MUST NOT be loaded
  NO PARALLEL AGENTS: Guided mode overrides parallel protocol. One agent at a time, sequential.
  CATEGORIES: Happy-path workflows ONLY
  FLOW: For each guided test (in order):
    1. Spawn ONE agent for DB seeding + external service setup
    2. Agent seeds database, configures services
    3. Agent reports readiness → shut down
    4. Orchestrator presents steps to user via AskUserQuestion
    5. User performs actions on real device/browser
    6. Orchestrator verifies results via DB queries/API/logs
    7. Record PASS/FAIL → next test
  PROHIBITED: agent-browser, Playwright, parallel agents, security/edge-case/validation tests
  ```

**Test categories** — standard (autonomous): all 9. Guided mode (both sub-modes): category 1 ONLY. Categories 2-9 never in guided. Non-happy-path findings queued as pending-autonomous-tests.

1. **Happy path** — normal flows end-to-end
2. **Invalid inputs & validation** — malformed data, missing fields, wrong types, boundaries
3. **Duplicate/idempotent requests** — rapid repeats, verify no duplicates
4. **Error handling** — every error branch in diff
5. **Unexpected DB changes** — orphans, missing refs, unintended mutations, slow queries
6. **Race conditions & timing** — concurrent writes, out-of-order webhooks, expired tokens
7. **Security** — injection, XSS/CSRF, auth bypass, data exposure, compliance
8. **Edge cases from code** — every branch/catch/guard/fallback covered
9. **Regression** — existing tests + re-verify broken flows

Per-agent setup: each uses pre-generated compose/docker commands, starts stack, runs init, executes suites. Failure redistribution: failed agent's suites reassigned to healthy agent.

Each suite: name, objective, pre-conditions, steps + expected outcomes, teardown, verification queries.

**Regression mode scoping**: When the plan receives a Targeted Regression Context Document:
- Suite 1 "Fix Verification" (always): one test per fixed item — re-execute the exact original failure scenario using original test IDs as reference
- Suite 2 "Impact Zone" (conditional): tests for 1-hop callers/callees — only categories where modified code is relevant (e.g., validation fix → Category 2; auth fix → Categories 4, 7; DB fix → Category 5). Skip categories with no code path overlap.
- No other suites — unaffected areas excluded
- State in plan: "Targeted regression re-test — scope limited to fix verification and 1-hop impact zone"
- Execution protocol: unchanged (same TeamCreate/parallel flow, just fewer suites)
- **Swarm efficiency note**: If regression scope produces <=2 suites, swarm Docker isolation overhead may exceed the benefit. The plan should note this but still execute as configured.

**Wait for approval.**

## Phase 4 — Execution (Agent Swarm)

`TeamCreate` → spawn `general-purpose` agents (one per suite or grouped). **Always `model: "opus"`**. All parallel. Coordinate via `TaskCreate`/`TaskUpdate`/`SendMessage`.

**Cascading context**: every agent gets full Feature Context Document from Phase 2.

**Capability-aware execution (autonomous mode ONLY)**: `agent-browser` first for UI if available → Playwright fallback → `mcp-add` safe MCPs → **External CLI gate**: prompt user once per service via `AskUserQuestion`, approved → `allowedOperations` only, declined → mark as "guided". Never use `safe: false` MCPs or `cli.blocked` CLIs.

**Guided mode execution**: No browser automation. No parallel agents. User performs all UI interactions. Swarm Docker isolation NOT used in guided mode — tests run against shared local stack.

**Anomaly detection**: duplicate records, unexpected DB changes, warning/error logs, slow queries, orphaned refs, auth anomalies, response anomalies. **Finding verification mandatory** — read source to confirm. Unconfirmed → `Severity: Unverified` in `### Unverified` subsection.

**API Response Security Inspection**: exposed IDs, leaked credentials, PII, compliance. **Source verification mandatory** — read model/serializer/DTO definitions. Synthetic data findings are false positives.

**Setup agent (MANDATORY)** — spawn first (`general-purpose`, `model: "opus"`, `team_name`):
1. Create `/tmp/autonomous-swarm-{sessionId}/agent-{N}/` per agent
2. Generate modified compose files / docker run scripts — remapped ports, namespaced names, related project files
3. npm-dev services: copy projects, set up `node_modules` per `nodeModulesStrategy` (`symlink` default → `ln -s`, `hardlink` → `cp -al` with `cp -r` fallback, `copy` → `cp -r`)
4. Copy + remap env files: `direct` → regex replace port, `url` → replace `localhost:ORIGINAL_PORT`. Preserve comments/prefixes/non-matching vars. Update compose `env_file:` paths.
5. npm-dev env remapping: apply `swarm.envPortMappings` to `.env`/`.env.local` in copies
6. Validate compose configs
7. Freeze capabilities snapshot — distributed verbatim, agents must NOT re-scan
8. Inject resource limits if configured (compose: `mem_limit`/`cpus`/`read_only`/`tmpfs`; raw: `--memory`/`--cpus`/`--read-only`/`--tmpfs`)
9. Apply Docker labels: `com.autonomous-swarm.managed=true`, `.session={sessionId}`, `.agent={N}`
10. Read key source files for context
11. Report via `SendMessage`: validated specs + Feature Context Document

Orchestrator waits for setup completion, then spawns suite agents with pre-generated specs. Setup agent shut down.

**Suite agent tasks (a-l)**:
- **a. Spec**: project name `swarm-{N}`, ports, Docker context, compose path
- **b. Capabilities**: frozen snapshot only
- **c. Compose setup**: verify + `docker compose -p swarm-{N} -f ... up -d`
- **d. Raw Docker setup**: `docker run -d --name swarm-{N}-{service} ...`, create/connect network `swarm-{N}-net`
- **e. npm-dev setup**: `rsync` project (exclude node_modules/.next/dist/.turbo), set up node_modules, resolve env overrides (`{port}`/`{backendPort}`), start in background (capture PID), remap env files
- **f. Health check**: poll remapped ports, 60s timeout, 2 attempts → report failure for redistribution
- **g. Init**: run `swarm.initialization.commands` with namespace resolution. Wait `waitAfterStartSeconds`. Related project init.
- **h. DB seeding**: adapted `migrationCommand`, `seedCommand`, `connectionCommand`, `cleanupCommand` with `swarm-{N}` namespace
- **i. Execute**: test suites against agent's API (remapped ports)
- **j. Report**: PASS/FAIL + anomalies via `SendMessage`
- **k. Audit** (when enabled): `agent-{N}.json` → `schemaVersion: "1.0"`, agentId, suites, environment, timeline (`{ timestamp, action, target, result }`), configuredLimits (no `docker stats`), teardown status, duration
- **l. Teardown (ALWAYS)**: compose `down -v --remove-orphans` / raw docker stop+rm+network rm / npm-dev kill PIDs / remove agent temp dir / verify no lingering containers

**Execution flow**:
1. Set Docker context
2. Confirm port ranges
3. Create tasks, spawn agents with `team_name`, assign via `TaskUpdate`
4. All parallel
5. **Failure redistribution**: failed agent's suites → healthy agent. Failed agent tears down.
6. Post-completion Docker cleanup verification:
   - Name-based: `docker ps -a --filter name=swarm- -q` → empty
   - Label-based: `docker ps -a --filter label=com.autonomous-swarm.session={sessionId} -q` → empty
   - Networks: `docker network ls --filter label=...session={sessionId} -q` → empty
   - Volumes: `docker volume ls --filter label=...session={sessionId} -q` → empty
   - Clean orphans if any
7. Merge audit logs (when enabled) → `audit-summary.json` (`schemaVersion: "1.0"`, metadata, per-agent, totals, cleanup verification)
8. `rm -rf /tmp/autonomous-swarm-{sessionId}`
9. Shut down via `SendMessage` `type: "shutdown_request"`

## Phase 5 — Results & Docs

### Fix cycle
- **Runtime-fixable** (env var, container, stuck job): fix → re-run → max 3 cycles
- **Code bug**: document (file, line, expected vs actual) → ask user

### Documentation
Delegate to agent. Dirs from config. Timestamp via `date -u +"%Y-%m-%d-%H-%M-%S"`. Pattern: `{timestamp}_{semantic-name}.md`. Read `autonomous-tests/references/templates.md` for structure.

Doc types: **test-results** (always), **pending-fixes** (bugs/infra), **pending-guided-tests** (browser/visual/device), **pending-autonomous-tests** (identified but not run).

When `swarm.audit.enabled`: append "Execution Audit" section (agent count, durations, limits, totals, cleanup, audit JSON path). Only orchestrator copies `audit-summary.json` to `docs/_autonomous/test-results/`. Re-runs: append "Re-run" section.

### Final cleanup
- Docker verification: same checks as Phase 4 step 6. Clean orphans.
- Verify `/tmp/autonomous-swarm-{sessionId}` removed
- Test data: remove by `testDataPrefix`. Never touch pre-existing data. Log + verify.

## Phase 6 — Finalize

> **Important**: Run `/clear` before invoking another skill to free context and prevent stale state.

---

## Rules

| Rule | Scope |
|---|---|
| No production data/connections | All |
| No credentials in output | All |
| Plan mode before execution | Phase 3 |
| Delegate via TeamCreate flow | Phases 4-5 |
| Always `model: "opus"` | Phases 4-5 |
| No unsafe MCPs (`safe: false`) | Phase 4 |
| External CLI: per-run confirmation, `allowedOperations` only | Phase 4 |
| Idempotent test data | Phase 4 |
| Always tear down, even on failure | Phase 4 |
| Never bind used ports | Phases 1, 4 |
| Never modify original compose/env — copies in `/tmp/` | Phase 4 |
| Namespace isolation: `docker compose -p` | Phase 4 |
| `--remove-orphans -v` in teardown | Phase 4 |
| Max 2 compose attempts before redistribute | Phase 4 |
| Never init against shared stack | Phase 4 |
| Docker Desktop context priority | Phases 0-1 |
| All temp files in `/tmp/` | All |
| npm-dev in copies only | Phase 4 |
| Clean `/tmp/autonomous-swarm-{sessionId}/` always | Phase 5 |
| Explore agents read-only | Phase 2 |
| Finding verification mandatory | Phase 4 |
| Resource limits when configured | Phase 4 |
| Docker labels hardcoded: `com.autonomous-swarm.*` | Phase 4 |
| Capabilities freeze in suite agents | Phase 4 |
| Audit logs when enabled | Phases 4-5 |
| Only orchestrator writes `docs/_autonomous/` | Phase 5 |
| Guided = user augmentation | No browser automation in guided mode — user performs all actions |
| Guided = happy path only | Category 1 only in guided mode — categories 2-9 autonomous-only |
| Tool loading gate | Browser tools need pre-plan approval in autonomous mode, never in guided |
| Plan self-containment | All context embedded in plan for post-reset survival — no "see above" references |
| Guided = single agent | Override parallel protocol — one agent at a time in guided mode |

## Operational Bounds

- **Max agents**: suites + 1 setup, capped at `swarm.maxAgents + 1` (default 6)
- **Max fix cycles**: 3 per suite
- **Health check**: 60s timeout, 2 attempts
- **Capability cache**: `rescanThresholdDays` (default 7)
- **Commands**: only user-approved config commands — no dynamic generation
- **Docker**: local only, Phase 1 aborts on production. Namespaced `swarm-{N}`, original compose untouched.
- **Credentials**: N/A — each agent seeds own data
- **MCPs**: only `safe: true` activated
- **Agents**: spawn → Docker → execute → teardown → shutdown. No persistent agents.
- **External CLIs**: `allowedOperations` only, per-run confirmation, blocked when `cli.blocked`. `prohibitedFlags`/`prohibitedOperations` always blocked.
- **System commands**: `which`, `docker compose ps`/`context ls`/`system df`, `docker ps -a --filter label=`, `docker network/volume ls --filter label=`, `git branch`/`diff`/`log`, `test -f`, `find . -maxdepth 3 -name "CLAUDE.md"`, `date -u`, `ss -tlnp`/`netstat -tlnp`, `curl -sf` localhost, `python3 -c` (json/hashlib/re), `cp -al`. `setup-hook.sh` modifies settings once at install only.
- **Downloads**: Docker images from project compose/config only. Playwright browsers if present. No other runtime downloads.
- **Data access**: outside project: `~/.claude/settings.json` (read), `~/.claude/trusted-configs/{hash}.sha256` (read/write), `~/.claude/CLAUDE.md` (read). CLAUDE.md 3 levels deep (read). `.env` scanned for patterns only — values never stored/logged/output. Modified files only in `/tmp/`.
- **Resource limits**: compose `mem_limit`/`cpus`/`read_only`/`tmpfs`, raw Docker `--memory`/`--cpus`/`--read-only`/`--tmpfs`. Non-null only. Per-container. Audit records configured, not runtime.
- **Labels**: `com.autonomous-swarm.managed=true`, `.session=`, `.agent=`. Hardcoded. Secondary cleanup verification.
- **Capabilities freeze**: setup agent snapshot → verbatim to suite agents. No re-scan.
- **Audit**: when enabled, agents write `agent-{N}.json` to `/tmp/.../audit/`, orchestrator merges to `audit-summary.json` (all `schemaVersion: "1.0"`). Only orchestrator copies to `docs/_autonomous/`.
- **Explore agents**: one per Phase 2. Read-only. No `team_name`.
- **Trust**: config SHA-256 vs out-of-repo trust store. Untrusted inputs → analysis → Feature Context Document → plan → user approval via ExitPlanMode. No untrusted content in shell commands.
