---
name: autonomous-tests-swarm
description: 'Run autonomous tests (integration + E2E) with per-agent Docker isolation. Each agent spins up its own database, API, and services on unique ports — true parallel testing with zero credential conflicts. Args: staged | unstaged | N | working-tree | file:<path> | rescan | guided [description]'
argument-hint: 'staged | unstaged | N | working-tree | file:<path> | rescan | guided'
disable-model-invocation: true
allowed-tools: Bash(*), Read(*), Write(*), Edit(*), Glob(*), Grep(*), Agent(*),
  EnterPlanMode(*), ExitPlanMode(*), AskUserQuestion(*)
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

## Role

Project-agnostic autonomous test runner with parallel execution via isolated Docker stacks. Analyzes code changes, auto-detects project capabilities, generates comprehensive test plans covering integration tests (curl-based API testing) and E2E tests (browser-based user flows), executes integration suites in PARALLEL (each agent with its own Docker stack on unique ports) and E2E suites SEQUENTIALLY, and documents findings for the test-fix-retest cycle.

## Test Taxonomy

This skill generates three types of tests. Read `../autonomous-tests/references/test-taxonomy.md` for full definitions:
- **Integration Tests**: API-level via `curl`. Security-focused request/response analysis. Classification: `integration/api`.
- **E2E Tests**: Frontend-to-backend flows via `agent-browser`/Playwright + chrome-devtools-mcp. Classification: `e2e/webapp`, `e2e/mobile`.
- **Regression Tests**: Unit tests (`testing.unitTestCommand`) run ONCE at the end. Classification: `regression/unit`.

Read `../autonomous-tests/references/security-checklist.md` for the 17-item security observation checklist applied to each suite.

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
- Use Agent() to spawn subagents for delegation
- Compile summaries from agent reports
- Make phase-gating decisions (proceed/stop/abort)

**Parallel spawning**: For integration suites, Orchestrator spawns MULTIPLE background subagents (`run_in_background: true`) up to `maxAgents` concurrent. E2E suites remain strictly sequential.

**Reporting hierarchy:** Agent -> Orchestrator -> Plan

## Arguments: $ARGUMENTS

| Arg | Meaning |
|---|---|
| _(empty)_ | Default: working-tree (staged + unstaged) with smart doc analysis |
| `staged` | Staged changes only |
| `unstaged` | Unstaged changes only |
| `N` (number) | Last N commits (e.g., `1` = last commit) |
| `working-tree` | Staged + unstaged (same as default) |
| `file:<path>` | `.md` doc as additional test context. Combinable. |
| `rescan` | Force capabilities re-scan. Combinable. |
| `guided` | User augmentation mode — bypasses git diff. Alone: prompts for doc or description. |
| `guided "desc"` | Description-based: happy-path workflows only, user performs actions. |
| `guided file:<path>` | Doc-based: happy-path workflows only, user performs actions. |

Space-separated, combinable (e.g., `staged file:docs/feature.md rescan`). `file:` validated as existing `.md` relative to project root.

**Guided mode** — user augmentation (NOT automation):
- **Doc-based** (`guided file:<path>` or pick from `docs/`/`_autonomous/pending-guided-tests/`): happy-path workflows only.
- **Description-based** (`guided "description"` or describe when prompted): happy-path workflows only.

User performs all actions on their real device/browser. Claude provides step-by-step instructions and verifies results via DB queries/API/logs. Only happy-path workflows in guided mode. Categories 2-8 handled exclusively in autonomous mode — NEVER in guided session. No agent-browser, no Playwright — guided mode never loads or uses browser automation tools.

`guided` alone prompts via `AskUserQuestion` to pick a doc or describe a feature. Combinable with `rescan` but NOT with `staged`/`unstaged`/`N`/`working-tree` (git-scope args incompatible — guided bypasses git diff).

Smart doc analysis always active in standard mode: match `docs/` files to changed code by path, feature name, cross-references — read only relevant docs.

Print resolved scope, then proceed without waiting.

---

## Phase 0 — Bootstrap

**Config hash method**: `python3 -c "import json,hashlib;d=json.load(open('.claude/autonomous-tests.json'));[d.pop(k,None) for k in ('_configHash','lastRun','capabilities')];print(hashlib.sha256(json.dumps(d,sort_keys=True).encode()).hexdigest())"` — referenced throughout as "Config hash method".

**Step 0: Prerequisites Check** — Read `~/.claude/settings.json`:
1. **ExitPlanMode hook** (informational): if missing -> inform user the skill-scoped hook handles it automatically; global setup available via the script. Continue.
2. **AskUserQuestion hook** (informational): same as above. Continue.

**Step 1: Capabilities Scan** — Triggers: `rescan` arg, `capabilities` missing, or `lastScanned` older than `rescanThresholdDays` (default 7 days). If none -> use cache.

Spawn **Explore agent** (`subagent_type: "Explore"`, thoroughness: `"medium"`) to perform:
1. **Docker MCP Discovery**: `mcp-find` for MCPs matching service names and generic queries. Record `name`, `description`, `mode`; `safe: true` only for known sandbox MCPs. If unavailable -> empty array.
2. **Frontend Testing**: `which agent-browser`, `which playwright`/`npx playwright --version` -> set `frontendTesting` booleans.
3. **Chrome DevTools MCP Detection**: Run `mcp-find` for chrome-devtools; scan `~/.claude.json` and `~/.claude/settings.json` for `mcpServers` containing `chrome-devtools`. Store in `capabilities.frontendTesting.chromeDevtools`.
4. **Project Type Detection**: Read `../autonomous-tests/references/project-type-detection.md`. Scan `package.json` files in project root and `relatedProjects[]` paths. Store in `project.frontendType` and `relatedProjects[].frontendType`.
5. **External Service CLI Detection**: Load `references/external-services-catalog.json`. Scan CLAUDE.md files for `claudeMdKeywords`. Per match: run `detectionCommand` -> if available, run `modeDetection.command` -> pattern-match -> populate `allowedOperations`/`prohibitedFlags` -> merge into `externalServices[]`.

Agent reports back. Orchestrator writes to `capabilities` with `lastScanned` = UTC time (`date -u`).

**Step 1.5: Tool Inventory** — ALWAYS runs (no caching — tools change between sessions):

- **Orchestrator directly** (no agent spawn):
  1. **Skills**: Extract available skills from system-reminder context
  2. **Agents**: Extract available agent types from Agent tool description
- **Delegate to Explore agent** (combine with Step 1 if triggered, or spawn separately):
  3. **MCP servers**: Run `mcp-find` + scan `~/.claude/settings.json` for `mcpServers`. Include chrome-devtools-mcp in inventory if available.
  4. **CLIs**: External service detection + probe common tools (`which curl`, `which jq`, `which ngrok`, `which uvx`)
- **Compile Tool Inventory**: Per-phase recommendations (Safety: health-check CLIs; Discovery: Explore+Grep/Glob; Plan: skills/agents; Execution: service MCPs, CLI fallbacks, browser tools, DB tools, chrome-devtools-mcp)

**CLAUDE.md deep scan** (Phase 0 + Phase 2): `find . -maxdepth 3 -name "CLAUDE.md" -type f` + `~/.claude/CLAUDE.md` + `.claude/CLAUDE.md`. Cache list for capabilities scan, auto-extract, Phase 2 enrichment, Feature Context Document.

**Step 2: Config Check** — `test -f .claude/autonomous-tests.json && echo "CONFIG_EXISTS" || echo "CONFIG_MISSING"`. Schema: `references/config-schema-swarm.json` (extends base `../autonomous-tests/references/config-schema.json`).

### If `CONFIG_EXISTS` (returning run):
1. Read config.
2. **Version validation**: require `version: 6` + fields `project`, `database`, `testing`, `swarm`. v5->v6: add `frontendType: "none"`, `chromeDevtools: false`, `e2eUrl: null`, `browserPreference: "agent-browser"`, add `logFile: null` to services, add `logCommand: null` to relatedProjects, add `frontendIndicators`, bump to 6. v4->v5->v6: chain migrations. <4 or missing fields -> warn, re-run first-run.
   - Missing `database.seedStrategy` -> default `"autonomous"`, inform user.
   - Missing `documentation.fixResults` -> add `"docs/_autonomous/fix-results"`.
   - Missing `swarm` -> run Swarm Configuration Questionnaire.
3. **Config trust**: Compute hash using **Config hash method**. Check trust store `~/.claude/trusted-configs/{project-hash}.sha256`. Mismatch -> show config (redact `testCredentials` values as `"********"`) -> `AskUserQuestion` for approval -> write hash.
4. **Testing priorities**: Show `userContext.testingPriorities`. `AskUserQuestion`: "Pain points or priorities?" with "None" option. Update config.
5. **Re-scan services**: Delegate to Explore agent. Update config if needed.
6. `date -u +"%Y-%m-%dT%H:%M:%SZ"` -> update `lastRun`.
7. Empty `userContext` -> run questionnaire, save.
8. **Re-stamp trust**: if config modified -> recompute hash, write to trust store.
9. Skip to Phase 1.

### If `CONFIG_MISSING` (first run):
Spawn **Explore agent** for auto-extraction:
1. **Auto-extract** from CLAUDE.md files + compose + env + package manifests. Detect migration/cleanup/seed commands. Detect DB type (MongoDB vs SQL). Both found -> ask user.
2. **Topology**: `single` | `monorepo` | `multi-repo`.
3. **Related projects**: scan sibling dirs, grep for external paths -> ask user per candidate -> populate `relatedProjects`.

Agent reports. Orchestrator proceeds:
4. **Capabilities scan** — delegate (Step 1).
5. **Seeding strategy** via `AskUserQuestion`: autonomous (recommended) or command.
6. **Swarm Configuration Questionnaire** via `AskUserQuestion`: `maxAgents` (default 3), `portRangeStart` (default 9000), `dockerContext` (auto-detected), `containerPrefix`, compose vs raw-docker mode. Validate Docker context exists and port range is available.
7. **User Context Questionnaire**: flaky areas? credentials (env var/role names only)? priorities? notes? -> store in `userContext`.
8. **Propose config** -> STOP for confirmation -> write.
9. **Stamp trust**: compute hash -> write to trust store.
10. If CLAUDE.md < 140 lines and lacks startup instructions -> append max 10 lines.

## Phase 1 — Safety, Environment & Log Monitoring

**Objective**: Verify the environment is safe, start services, reserve ports, and begin per-agent log capture.

Spawn ONE **general-purpose subagent** (foreground) to perform:
1. **Production scan**: `.env` files for `productionIndicators`, `*LIVE*SECRET*`, `NODE_ENV=production`, production DB endpoints, non-local URLs. Show variable NAME only.
2. Run `sandboxCheck` commands from config.
3. Verify Docker is local. Validate `swarm.dockerContext` exists: `docker context inspect {dockerContext}`.
4. **Port reservation**: Verify port range `portRangeStart` to `portRangeStart + (maxAgents * portStep)` is free. `lsof -i :{port}` or `ss -tlnp` per port. Conflict -> warn + suggest alternative range.
5. **Related project safety scan**: For each `relatedProjects[]` with a `path`, scan `.env` files for production indicators. Any production indicator -> **ABORT**.
6. **Service startup**: per service in config + related projects with `startCommand`: health check -> healthy: `already-running` -> unhealthy: start + poll 5s/30s -> `started-this-run` or report failure.
7. Start webhook listeners: for each `externalServices[]` with `webhookListener != null`, run the command as a background process and record PID.
8. **Log monitoring setup**: After services are healthy, start log capture per `../autonomous-tests/references/log-monitoring-protocol.md` (Swarm Variant):
   - Per-agent log paths at `/tmp/autonomous-swarm-{sessionId}/agent-{N}/logs/`
   - Create base directory structure for all agents
   - Record log file paths and PIDs in Service Readiness Report
9. **Service Readiness Report**: per service — name, URL/port, health status, health check endpoint, source, log file path, log capture PID, assigned port range per agent.

Agent reports: safety assessment + Service Readiness Report with log paths. Gates: **ABORT** if production. **STOP** if unhealthy.

## Phase 2 — Discovery

Fully autonomous — derive from code diff, codebase, or guided source. Never ask what to test.

**Delegation**: ONE Explore agent (`subagent_type: "Explore"`, thoroughness: `"medium"`).

### Standard mode
1. Changed files from git (scope args) — include `relatedProjects[].path` for cross-project deps.
2. If `file:<path>` -> read `.md`, extract features/criteria/endpoints/edge cases.
3. **Spawn Explore agent** with: changed files, file reference content, `relatedProjects[]`, `testing.contextFiles`, CLAUDE.md paths, `documentation.*` paths. Agent performs:
   - **Feature map**: API endpoints, DB ops, external services, business logic, auth flows, signal/event chains
   - **Dependency graph**: callers -> changed code -> callees, cross-file/project imports
   - **Smart doc analysis**: match paths/features against `docs/`, scan `_autonomous/` (Summary + Issues Found only), fix completion scan
   - **Edge case inventory**: error handlers, validation branches, race conditions, retry logic
   - **Cross-project seed map**: For each `relatedProjects[]`, trace which collections/tables are read by E2E flows
   - **Test flow classification**: Classify each scenario as `integration/api`, `e2e/webapp`, `e2e/mobile`, `guided/webapp`, `guided/mobile`. Project type influences: if `frontendType` is `webapp` -> `e2e/webapp`; if `mobile` -> `e2e/mobile`; if `api-only` -> only `integration/api`.
   - **Security checklist mapping**: Read `../autonomous-tests/references/security-checklist.md`. Map each of 17 items to YES/NO/PARTIAL per discovered feature.
   - **Data seeding analysis**: Read `../autonomous-tests/references/data-seeding-protocol.md`. Analyze DB schema and models. Return seed plan with table names, field names, example values, create/cleanup commands.
   - **Related project log commands**: Discover log commands per `relatedProjects[]`.
4. Receive structured report.

### Guided mode (user augmentation)
**Validate first**: `guided` + `staged`/`unstaged`/`N`/`working-tree` -> STOP with combinability error.
1. **Resolve source**: `guided file:<path>` -> doc-based | `guided "desc"` -> description-based | `guided` alone -> `AskUserQuestion`.
2. **Spawn Explore agent** with same inputs. Agent performs: deep feature analysis + same feature map/dependency/doc analysis/edge cases. Also identifies: DB seed requirements, external service setup needs, prerequisite state per happy-path workflow.
3. Receive report. Orchestrator extracts only happy-path workflows — discard security, edge case, validation findings.

### Regression Scope Analysis (conditional — after Explore report)
Check for re-test indicators in `documentation.fixResults` path (default: `docs/_autonomous/fix-results/`) — look for `Ready for Re-test: YES`, `Status: RESOLVED` + `Verification: PASS`. If found -> compile **Targeted Regression Context Document** (fix manifest, 1-hop impact zone, original test IDs, blast radius check >60% -> full scope).

### Feature Context Document (standard/guided modes — skipped in regression mode)
Compile from Explore report (do NOT re-read files). Contents: features, endpoints, DB collections/tables, cross-project seed map, test flow classifications, security checklist applicability map, data seeding plan, log file paths from Service Readiness Report, related project log commands, external services, edge cases, test history, capabilities, **swarm port mappings and Docker stack configuration**. Guided mode adds `Mode` + `Source` at top. Cascaded to every Phase 4 agent.

### Post-Discovery Prompts (standard mode only — skip if `guided` or regression)
Single `AskUserQuestion`:
- **Guided Happy-Path** — After all autonomous tests, generate guided test plan where user performs actions while agent verifies. Happy-path only. Include? (yes/no)

Parse response into `guidedHappyPathApproved` boolean.

## Phase 3 — Plan (Plan Mode)

**Enter plan mode (/plan).** Plan starts with:

**Step 0 — Context Reload** (for post-approval reconstruction):
- Re-read: SKILL.md, config, `../autonomous-tests/references/templates.md`
- Scope: `$ARGUMENTS`, branch, commit range
- Findings: Phase 2 discoveries (modules, endpoints, dependencies, test flow classifications)
- User context: flaky areas, priorities, notes
- Service Readiness Report from Phase 1 (including log file paths, port assignments)
- Swarm config: `maxAgents`, `portRangeStart`, `portStep`, `dockerContext`, compose paths
- If regression mode: fix manifest, 1-hop impact zone, original test IDs, Targeted Regression Context Document
- If guided: type, source, full guided test list with per-test seed requirements
- If guided happy-path approved: happy-path workflows with seed requirements, user instructions, verification queries

**Tool loading gate**: If plan includes `e2e/webapp` or `e2e/mobile` suites AND `capabilities.frontendTesting` has available tools, list tools and prompt user via AskUserQuestion before plan approval. Declined tools excluded from plan. Guided mode: NEVER include browser automation tools — skip this gate.

**Self-containment mandate** — the plan MUST embed directly (not reference "above" or prior phases):
1. All test suites with full details (name, objective, pre-conditions, steps, expected outcomes, teardown, verification)
2. Feature Context Document (condensed but complete)
3. Service Readiness Report from Phase 1 (including log file paths, capture PIDs, port assignments)
4. Per-suite agent spawn instructions with resolved values, port mappings, and Docker stack config
5. Config paths: `documentation.*`, `database.connectionCommand`, `testing.unitTestCommand`, `testDataPrefix`
6. Credential role names from `testCredentials`
7. If guided: per-test DB seed commands, user-facing instructions, verification queries
8. Seed schema discovery mandate (embedded verbatim) per `../autonomous-tests/references/data-seeding-protocol.md`
9. If guided happy-path approved: Guided Happy-Path Decision block
10. Documentation checklist (always — output directories, template path, filename convention, doc types this run produces)
11. Tool Inventory from Phase 0
12. DB Consistency Check Protocol from `../autonomous-tests/references/db-consistency-protocol.md`
13. Security checklist applicability map (which of the 17 items apply to which features)
14. Explicit data seeding plan (tables, fields, values, curl/DB commands)
15. Log file paths from Service Readiness Report
16. Chrome DevTools protocol (if available) from `../autonomous-tests/references/chrome-devtools-protocol.md`
17. Service startup commands for all project + relatedProject services
18. Execution protocols from `references/execution-protocols-swarm.md` — embed relevant protocols verbatim
19. Suite agent tasks from `references/swarm-agent-tasks.md` — embed lifecycle tasks verbatim

### Test Plan Structure

```
## Test Plan

### Integration Test Suites (curl-based) — PARALLEL EXECUTION
Categories 1-8 per ../autonomous-tests/references/test-taxonomy.md. Each suite includes:
- Explicit curl commands with expected responses (remapped ports per agent)
- Security checklist items applicable to this suite (YES/PARTIAL only)
- Data seeding commands (what to create before, what to clean after)
- Per-agent log file paths
- Docker stack assignment (swarm-{N}, ports, compose path)

### E2E Test Suites (browser-based) — SEQUENTIAL EXECUTION
Only if frontendType != api-only. Runs against shared local stack (NOT swarm-isolated).
For webapp: agent-browser flows with chrome-devtools-mcp observations
For mobile: guided steps with verification commands

### Regression (unit tests — runs LAST)
Single testing.unitTestCommand execution after all suites complete.
```

**Regression mode scoping**: When Targeted Regression Context Document is present:
- Suite 1 "Fix Verification": one test per fixed item — re-execute original failure scenario
- Suite 2 "Impact Zone" (conditional): tests for 1-hop callers/callees
- No other suites. Execution protocol unchanged.

**Pre-approval validation**: Before presenting the plan, verify all self-containment items are present. Missing items -> add before prompting.

**Wait for user approval.**

## Phase 4 — Execution (Subagents)

Spawn subagents per the execution protocols in `references/execution-protocols-swarm.md`. Each agent follows the lifecycle in `references/swarm-agent-tasks.md`.

### 1. Service Restoration Agent (fg, FIRST)
Context reset kills background processes. Re-establish services and log captures:
1. Run `healthCheck` per service — healthy -> `verified-post-reset` — unhealthy -> `startCommand` + poll 5s/30s
2. Related projects: same check via `relatedProjects[]`
3. Start webhook listeners
4. **Re-start log captures** per `../autonomous-tests/references/log-monitoring-protocol.md` (Swarm Variant) for all services
5. Recreate per-agent directories at `/tmp/autonomous-swarm-{sessionId}/agent-{N}/logs/`
6. **Gate**: any `failed-post-reset` -> **STOP**
7. Return updated Service Readiness Report with new log file paths and PIDs

### 2. Setup Agent (fg)
Read source files, compile Feature Context Documents, read CLAUDE.md files. Generate per-agent specs (swarm-{N}, remapped ports, compose paths). Freeze capabilities snapshot for distribution. Proceeds after completion.

### 3. Integration Suite Agents (bg, PARALLEL — up to maxAgents concurrent)
Each agent spawned with `run_in_background: true`. Each receives:
- Pre-generated spec (swarm-{N}, ports, compose path)
- Frozen capabilities snapshot
- Feature Context Document with remapped curl commands
- Security checklist subset (YES/PARTIAL items only)
- Data seeding instructions per `../autonomous-tests/references/data-seeding-protocol.md`
- Per-agent log paths at `/tmp/autonomous-swarm-{sessionId}/agent-{N}/logs/`
- DB consistency protocol, credential role name, Tool Inventory subset

Each agent executes lifecycle tasks a-l from `references/swarm-agent-tasks.md` within its isolated Docker stack. Failure -> redistribute to replacement background subagent.

Orchestrator waits for ALL parallel agents to complete, then performs audit merge per `references/execution-protocols-swarm.md` (Audit Merge Protocol).

### 4. E2E Suite Agents (fg, SEQUENTIAL — one at a time)
Only if `frontendType` != `api-only`. Runs against shared local stack (NOT swarm-isolated).
Each agent receives: user journey steps, browser config, chrome-devtools protocol (if `chromeDevtools: true`), log paths, Service Readiness Report, Feature Context Document, Tool Inventory subset.

**Webapp**: Navigate with `agent-browser` -> snapshot -> execute journey -> re-snapshot + devtools check -> verify backend via curl -> verify DB.
**Mobile**: Present guided steps via `AskUserQuestion` -> user acts -> verify via curl/DB/logs.

Browser tool priority (skipping without attempting is PROHIBITED):
1. `agent-browser` (PRIMARY) — `open <url>` -> `snapshot -i` -> `click/fill @ref` -> re-snapshot
2. Playwright (FALLBACK) — if agent-browser unavailable/errors
3. Direct HTTP/API (LAST RESORT) — mark untestable parts as "guided"

Reports back: PASS/FAIL per step, screenshots, network/console findings, backend verification, logs.

### 5. Guided Happy-Path (fg, optional, if user approved)
Runs LAST — after autonomous suites. No browser automation. Category 1 only. Swarm isolation NOT used — shared local stack.
For each test: seed DB -> present steps via `AskUserQuestion` (MANDATORY — text output PROHIBITED) with options `["Done - ready to verify", "Skip this test", "Issue encountered"]` -> user acts -> verify via DB/API/logs -> PASS/FAIL.

### 6. Regression Agent (fg, LAST)
Run `testing.unitTestCommand` once. Report total/passed/failed/skipped. Never interleaved with other suites.

### Critical Execution Rules
- Never create batch scripts — each test explicitly passed to subagent
- Explicit data seeding instructions (table, fields, values, commands) — never guess
- Each subagent receives applicable security checklist items only
- Each subagent receives per-agent log file paths to check after execution
- Orchestrator checks logs between suites and after parallel completion
- **Credential assignment**: Rotate role names from `testCredentials` across suites (round-robin: suite 1 gets role A, suite 2 gets role B, wraps to role A if more suites than roles) — pass role name only, never values
- **Finding verification** (mandatory): identify source code -> read to confirm -> distinguish real vs agent-created -> report only confirmed. Unconfirmed -> `Severity: Unverified` in `### Unverified`
- **Anomaly detection**: duplicate records, unexpected DB changes, warning/error logs, slow queries, orphaned references, auth anomalies, unexpected response fields/status codes
- **External CLI guard**: Before any CLI command from `externalServices[]`, verify the subcommand is in `allowedOperations` and no `prohibitedFlags` are present. Reject non-matching commands.
- Integration suites: PARALLEL (`run_in_background: true`), up to `maxAgents` concurrent
- E2E suites: SEQUENTIAL (fg, one at a time) — browser automation cannot parallelize
- Guided mode overrides to SEQUENTIAL for all suites (no parallel execution)

## Phase 5 — Results & Docs

**Fix cycle**: Runtime-fixable issues -> verify real (re-read error, retry once, confirm root cause) -> spawn subagent to fix -> re-run suite -> max 3 cycles. Code bug -> document + ask user.

**Audit merge**: If not done in Phase 4, merge all parallel agent results per `references/execution-protocols-swarm.md` (Audit Merge Protocol). Consolidate findings, security observations, DB consistency, log findings across all agents.

**Documentation**: Spawn subagent (foreground). Timestamp via `date -u +"%Y-%m-%d-%H-%M-%S"`. Pattern: `{timestamp}_{semantic-name}.md`. Read `../autonomous-tests/references/templates.md`. Four doc types: test-results (always — rename header to "Test Results"), pending-fixes (bugs/infra), pending-guided-tests (browser/visual/physical), pending-autonomous-tests (identified but not run). Include service log analysis, DB consistency results (if WARN/FAIL). When audit enabled -> append "Execution Audit" section (agent count, durations, limits, cleanup). Include ALL results from autonomous + guided phases.

**Docker cleanup verification**: Spawn subagent (foreground) per `references/execution-protocols-swarm.md` (Docker Cleanup Verification):
1. Verify no lingering swarm containers, networks, or volumes
2. Clean orphans if any remain
3. Remove `/tmp/autonomous-swarm-{sessionId}/`

**Cleanup**: Remove `testDataPrefix` data only. Never touch pre-existing. Kill log capture processes. Verify cleanup. Log actions.

**DB consistency final check**: Run POST_CLEANUP verification. Zero test records must remain.

## Phase 6 — Finalize

> **Important**: Run `/clear` before invoking another skill (e.g., `/autonomous-fixes`) to free context window tokens and prevent stale state from interfering with the next operation.

---

## Rules

| Rule | Detail |
|---|---|
| No production | Never modify production data or connect to production services |
| No credentials in output | Never expose credentials, keys, tokens, or env var values — pass role names only |
| Plan before execution | Phase 3 plan mode required before any test execution |
| Subagents only | All execution via Agent(). Main-conversation execution PROHIBITED |
| Model inheritance | Subagents inherit from main conversation — ensure Opus is set |
| Integration = parallel | Integration suites run in PARALLEL via `run_in_background: true`, up to `maxAgents` concurrent |
| E2E = sequential | E2E suites run ONE at a time — browser automation cannot parallelize |
| Guided = all sequential | Guided mode overrides parallel — all suites sequential |
| Isolated Docker stacks | Each parallel agent gets its own Docker stack with remapped ports and namespaced containers |
| Port cleanup mandatory | All swarm ports must be freed after execution — no lingering binds |
| Docker cleanup mandatory | All swarm containers, networks, volumes removed after execution — no orphans |
| Explore agents read-only | No file edits or state-modifying commands |
| UTC timestamps | Via `date -u` only, never guess |
| No unsafe MCPs | Never activate `safe: false` MCPs |
| External CLI gating | Blocked when `cli.blocked`. Per-run user confirmation. `allowedOperations` only |
| No dynamic commands | Only execute verbatim config commands — no generation/concatenation/interpolation |
| Integration tests = curl | Always `curl` — never mock, never script-based test runners |
| E2E tests = browser | `agent-browser` (primary) or Playwright (fallback) — never test production |
| Unit tests = regression | Run ONCE at the end — never during integration/E2E suites |
| Data seeding = explicit | Never guess field names, values, or schemas. Seed schema discovery mandatory |
| Each test = one subagent | Never batch scripts — each test passed individually to subagent |
| Service logs monitored | Log capture active during all test phases. Check between suites |
| Finding verification | Verify against source code before reporting any finding |
| Idempotent test data | Prefix with `testDataPrefix`. Skip or reset if exists |
| External API care | Delays between calls, sandbox modes, minimize requests |
| `_autonomous/` reading | Summary + Issues Found sections only |
| Capabilities auto-detected | Never ask user to configure manually |
| Guided = user augmentation | No browser automation in guided mode — user performs all actions |
| Guided = happy-path only | Category 1 only in guided mode — categories 2-8 autonomous-only |
| Tool loading gate | Browser tools need pre-plan approval in autonomous mode, never in guided |
| Plan self-containment | All context embedded in plan for post-reset survival — no "see above" references |
| Guided happy-path = post-all | Guided happy-path runs last — after all autonomous suites |
| Post-discovery prompts | Standard mode only — skipped when `guided` arg or regression mode active |
| Documentation in every run | Test-results doc generated for every run. Embedded in plan execution protocol |
| DB consistency inline | POST_SEED, POST_TEST, POST_CLEANUP checks within Phase 4 per suite |
| Audit merge before docs | Parallel results merged before documentation phase |

## Operational Bounds

| Bound | Constraint |
|---|---|
| Max parallel agents | `swarm.maxAgents` (default 5) |
| Max agents total | Approved test suites + service restoration + setup + regression |
| Max fix cycles | 3 per suite |
| Health check timeout | 30s per service (60s for swarm stacks) |
| Capability cache | `rescanThresholdDays` (default 7 days) |
| Command scope | User-approved config commands only |
| Docker scope | Local only — Phase 1 aborts on production indicators |
| Docker context | `swarm.dockerContext` validated in Phase 1 |
| Port range | `portRangeStart` to `portRangeStart + (maxAgents * portStep)` — validated free |
| Credential scope | Env var references only — raw values forbidden, redacted on display |
| MCP scope | `safe: true` only |
| Subagent lifecycle | Integration: parallel bg. E2E/guided/regression: one fg at a time |
| Explore agent scope | One per Phase 2. Read-only |
| External CLI scope | `allowedOperations` only. Per-run confirmation. Blocked when `cli.blocked` |
| System commands | `which`, `docker compose ps`, `docker context inspect/show`, `git branch`/`diff`/`log`, `test -f`, `find . -maxdepth 3 -name "CLAUDE.md" -type f`, `date -u`, `curl -sf` localhost, `python3 -c` json/hashlib, `lsof`/`ss` for port checks |
| External downloads | Docker images via user's compose only. Playwright browsers if present. No other downloads |
| Data access | Outside project: `~/.claude/settings.json` (RO), `~/.claude/trusted-configs/` (RW), `~/.claude/CLAUDE.md` (RO). `.env` scanned for patterns only |
| Trust boundaries | Config SHA-256 verified out-of-repo. Untrusted inputs -> analysis only -> plan -> user approval |
| Guided happy-path scope | Category 1 only. No browser automation. Sequential. Runs last |
| Documentation output | Minimum 1 doc (test-results) per run. Embedded in execution protocol for post-reset survival |
| Temp directory | `/tmp/autonomous-swarm-{sessionId}/` — removed in Phase 5 cleanup |
