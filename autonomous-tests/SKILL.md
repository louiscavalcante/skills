---
name: autonomous-tests
description: 'Run autonomous tests (integration via curl + E2E via browser). Args: staged | unstaged | N | working-tree | file:<path> | rescan | guided [description]'
argument-hint: 'staged | unstaged | N | working-tree | file:<path> | rescan | guided'
disable-model-invocation: true
allowed-tools: Bash(*), Read(*), Write(*), Edit(*), Glob(*), Grep(*), Agent(*),
  EnterPlanMode(*), ExitPlanMode(*), AskUserQuestion(*), TaskCreate(*), TaskUpdate(*)
---

## Dynamic Context

- Args: $ARGUMENTS
- Branch: !`git branch --show-current`
- Unstaged: !`git diff --stat HEAD 2>/dev/null | tail -5`
- Staged: !`git diff --cached --stat 2>/dev/null | tail -5`
- Commits: !`git log --oneline -5 2>/dev/null`
- Docker: !`docker compose ps 2>/dev/null | head -10 || echo "No docker-compose found"`
- Config: !`test -f .claude/autonomous-tests.json && echo "YES" || echo "NO -- first run"`
- Capabilities: !`python3 -c "import json;c=json.load(open('.claude/autonomous-tests.json'));caps=c.get('capabilities',{});mcps=len(caps.get('dockerMcps',[]));ab='Y' if caps.get('frontendTesting',{}).get('agentBrowser') else 'N';pw='Y' if caps.get('frontendTesting',{}).get('playwright') else 'N';cd='Y' if caps.get('frontendTesting',{}).get('chromeDevtools') else 'N';ec=sum(1 for s in c.get('externalServices',[]) if s.get('cli',{}).get('available'));print(f'MCPs:{mcps} agent-browser:{ab} playwright:{pw} chrome-devtools:{cd} ext-clis:{ec} scanned:{caps.get(\"lastScanned\",\"never\")}')" 2>/dev/null || echo "NOT SCANNED"`

## Role

Project-agnostic autonomous test runner. Analyzes code changes, auto-detects project capabilities, generates comprehensive test plans covering integration tests (curl-based API testing) and E2E tests (browser-based user flows), executes test suites via subagents, and documents findings for the test-fix-retest cycle.

## Test Taxonomy

This skill generates three types of tests. Read `references/test-taxonomy.md` for full definitions:
- **Integration Tests**: API-level via `curl`. Security-focused request/response analysis. Classification: `integration/api`.
- **E2E Tests**: Frontend-to-backend flows via `agent-browser`/Playwright + chrome-devtools-mcp. Classification: `e2e/webapp`, `e2e/mobile`.
- **Regression Tests**: Unit tests (`testing.unitTestCommand`) run ONCE at the end. Classification: `regression/unit`.

Read `references/security-checklist.md` for the 17-item security observation checklist applied to each suite.

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

**Reporting hierarchy:** Agent -> Orchestrator -> Plan

## Task Tracking Protocol

The orchestrator uses `TaskCreate` and `TaskUpdate` to track phase-level progress. This provides visible progress indicators and a deterministic execution sequence for the post-reset orchestrator.

**When to create tasks**: Immediately after plan approval (start of Phase 4), create ALL phase tasks at once. This gives a complete checklist that survives context pressure.

**Task lifecycle**: `pending` -> `in_progress` (when phase starts) -> `completed` (when phase finishes). If a phase triggers STOP/ABORT, update the task description with the reason before halting.

**Task naming**: `Phase {N}: {Phase Name}` (e.g., `Phase 4.1: Service Restoration`). For guided happy-path, each scenario gets its own subtask: `Phase 4.6.{M}: {Scenario Name}`.

**Dependency chaining**: Each task blocks the next so the orchestrator processes them in order.

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
4. **Project Type Detection**: Read `references/project-type-detection.md`. Scan `package.json` files in project root and `relatedProjects[]` paths. Store in `project.frontendType` and `relatedProjects[].frontendType`.
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

**Step 2: Config Check** — `test -f .claude/autonomous-tests.json && echo "CONFIG_EXISTS" || echo "CONFIG_MISSING"`. Schema: `references/config-schema.json`.

### If `CONFIG_EXISTS` (returning run):
1. Read config.
2. **Version validation**: require `version: 6` + fields `project`, `database`, `testing`. v5->v6: add `frontendType: "none"`, `chromeDevtools: false`, `e2eUrl: null`, `browserPreference: "agent-browser"`, add `logFile: null` to services, add `logCommand: null` to relatedProjects, add `frontendIndicators`, remove deprecated eligibility and `credentialType` fields, bump to 6. v4->v5->v6: chain migrations. <4 or missing fields -> warn, re-run first-run.
   - Missing `database.seedStrategy` -> default `"autonomous"`, inform user.
   - Missing `documentation.fixResults` -> add `"docs/_autonomous/fix-results"`.
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
6. **User Context Questionnaire**: flaky areas? credentials (env var/role names only)? priorities? notes? -> store in `userContext`.
7. **Propose config** -> STOP for confirmation -> write.
8. **Stamp trust**: compute hash -> write to trust store.
9. If CLAUDE.md < 140 lines and lacks startup instructions -> append max 10 lines.

## Phase 1 — Safety, Environment & Log Monitoring

**Objective**: Verify the environment is safe, start services, and begin log capture.

Spawn ONE **general-purpose subagent** (foreground) to perform:
1. **Production scan**: `.env` files for `productionIndicators`, `*LIVE*SECRET*`, `NODE_ENV=production`, production DB endpoints, non-local URLs. Show variable NAME only.
2. Run `sandboxCheck` commands from config.
3. Verify Docker is local.
4. **Related project safety scan**: For each `relatedProjects[]` with a `path`, scan `.env` files for production indicators. Any production indicator -> **ABORT**.
5. **Service startup**: per service in config + related projects with `startCommand`: health check -> healthy: `already-running` -> unhealthy: start + poll 5s/30s -> `started-this-run` or report failure.
6. Start webhook listeners: for each `externalServices[]` with `webhookListener != null`, run the command as a background process and record PID.
7. **Log monitoring setup**: After services are healthy, start log capture per `references/log-monitoring-protocol.md`:
   - For each service with `logCommand`: start background log capture to `/tmp/test-logs-{sessionId}/`
   - Record log file paths and PIDs in Service Readiness Report
8. **Service Readiness Report**: per service — name, URL/port, health status, health check endpoint, source, log file path, log capture PID.

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
   - **Test flow classification**: Classify each scenario as `integration/api` (API-only, curl), `e2e/webapp` (browser automation), `e2e/mobile` (physical device guided steps), `guided/webapp`, `guided/mobile`. Project type influences: if `frontendType` is `webapp` -> generate `e2e/webapp` suites; if `mobile` -> `e2e/mobile`; if `api-only` -> only `integration/api`.
   - **Security checklist mapping**: Read `references/security-checklist.md`. Map each of 17 items to YES/NO/PARTIAL per discovered feature.
   - **Data seeding analysis**: Read `references/data-seeding-protocol.md`. Analyze DB schema and models. Return seed plan with table names, field names, example values, create/cleanup commands.
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
Compile from Explore report (do NOT re-read files). Contents: features, endpoints, DB collections/tables, cross-project seed map, test flow classifications, security checklist applicability map, data seeding plan, log file paths from Service Readiness Report, related project log commands, external services, edge cases, test history, capabilities. Guided mode adds `Mode` + `Source` at top. Cascaded to every Phase 4 agent.

### Post-Discovery Prompts (standard mode only — skip if `guided` or regression)
**MUST execute BEFORE entering plan mode** — guided happy-path inclusion must be decided before the plan is written.
Single `AskUserQuestion`:
- **Guided Happy-Path** — After all autonomous tests and regression, generate guided test plan where user performs actions while agent verifies logs and DB per step. Happy-path only. Include? (yes/no)

Parse response into `guidedHappyPathApproved` boolean.

## Phase 3 — Plan (Plan Mode)

**Enter plan mode (/plan).** Plan starts with:

**Step 0 — Context Reload** (for post-approval reconstruction):
- Re-read: SKILL.md, config, `references/templates.md`
- Scope: `$ARGUMENTS`, branch, commit range
- Findings: Phase 2 discoveries (modules, endpoints, dependencies, test flow classifications)
- User context: flaky areas, priorities, notes
- Service Readiness Report from Phase 1 (including log file paths — Phase 3 agents MUST NOT start services)
- If regression mode: fix manifest, 1-hop impact zone, original test IDs, Targeted Regression Context Document
- If guided: type, source, full guided test list with per-test seed requirements
- If guided happy-path approved: happy-path workflows with seed requirements, user instructions, verification queries

**Tool loading gate**: If plan includes `e2e/webapp` or `e2e/mobile` suites AND `capabilities.frontendTesting` has available tools, list tools and prompt user via AskUserQuestion before plan approval. Declined tools excluded from plan. Guided mode: NEVER include browser automation tools — skip this gate.

**Self-containment mandate** — the plan MUST embed directly (not reference "above" or prior phases):
1. All test suites with full details (name, objective, pre-conditions, steps, expected outcomes, teardown, verification)
2. Feature Context Document (condensed but complete)
3. Service Readiness Report from Phase 1 (including log file paths and capture PIDs)
4. Per-suite agent spawn instructions with resolved values
5. Config paths: `documentation.*`, `database.connectionCommand`, `testing.unitTestCommand`, `testDataPrefix`
6. Credential role names from `testCredentials`
7. If guided: per-test DB seed commands, user-facing instructions, verification queries
8. Seed schema discovery mandate (embedded verbatim) per `references/data-seeding-protocol.md`
9. If guided happy-path approved: Guided Happy-Path Decision block
10. Documentation checklist (always — output directories, template path, filename convention, doc types this run produces)
11. Tool Inventory from Phase 0
12. DB Consistency Check Protocol from `references/db-consistency-protocol.md`
13. Security checklist applicability map (which of the 17 items apply to which features)
14. Explicit data seeding plan (tables, fields, values, curl/DB commands per `references/data-seeding-protocol.md`)
15. Log file paths from Service Readiness Report
16. Chrome DevTools protocol (if available) from `references/chrome-devtools-protocol.md`
17. Service startup commands for all project + relatedProject services
18. Execution protocols from `references/execution-protocols.md` — embed relevant protocols verbatim
19. Task Tracking Block — create all phase tasks at execution start (embed verbatim):
    ```
    IMMEDIATELY after plan approval and context reload, create tasks:
      TaskCreate("Phase 4.1: Service Restoration", "Re-establish services and log captures post-reset")
      TaskCreate("Phase 4.2: Setup", "Read source files, compile Feature Context Documents")
      TaskCreate("Phase 4.3: Integration Suites", "Execute integration test suites sequentially via subagents")
      TaskCreate("Phase 4.4: E2E Suites", "Execute E2E browser-based test suites via subagents") — skip if frontendType == api-only
      TaskCreate("Phase 4.5: Regression", "Run unit tests via testing.unitTestCommand")
      TaskCreate("Phase 4.6: Guided Happy-Path", "User-augmented verification per scenario") — skip if not approved
        For each happy-path scenario [M]: TaskCreate("Phase 4.6.[M]: [Scenario Name]", "[scenario description]")
      TaskCreate("Phase 5: Results & Docs", "Fix cycles, documentation generation, cleanup")
    Chain: 4.1 -> 4.2 -> 4.3 -> 4.4 -> 4.5 -> 4.6 -> 5 (sequential via addBlockedBy)
    Before each phase: TaskUpdate(id, status: "in_progress")
    After each phase: TaskUpdate(id, status: "completed")
    ```
20. Phase Orchestration Protocol from `references/execution-protocols.md` — embed verbatim. Contains concrete Agent() spawn templates for every phase.

### Test Plan Structure

```
## Test Plan

### Integration Test Suites (curl-based)
Categories 1-8 per references/test-taxonomy.md. Each suite includes:
- Explicit curl commands with expected responses
- Security checklist items applicable to this suite (YES/PARTIAL only)
- Data seeding commands (what to create before, what to clean after)
- Log file paths for post-suite analysis

### E2E Test Suites (browser-based) — only if frontendType != api-only
For webapp: agent-browser flows with chrome-devtools-mcp observations
For mobile: guided steps with verification commands
Each suite includes:
- User journey steps
- Expected UI states
- Chrome DevTools observations (if available)
- Backend verification via curl after UI actions

### Regression (unit tests — runs LAST)
Single testing.unitTestCommand execution after all suites complete.
```

**Regression mode scoping**: When Targeted Regression Context Document is present:
- Suite 1 "Fix Verification": one test per fixed item — re-execute original failure scenario
- Suite 2 "Impact Zone" (conditional): tests for 1-hop callers/callees
- No other suites. Execution protocol unchanged (sequential subagent flow).

**Pre-approval validation**: Before presenting the plan, verify all self-containment items (1-20) are present. Missing items -> add before prompting.

**Wait for user approval.**

## Phase 4 — Execution (Subagents)

**First**: Create all phase tasks per the Task Tracking Block embedded in the plan. Chain dependencies.

**Then**: Follow the Phase Orchestration Protocol embedded in the plan for concrete Agent() spawn templates. Each phase: TaskUpdate -> spawn subagent with detailed context -> receive report -> TaskUpdate completed.

Spawn `general-purpose` subagents sequentially (foreground). Each receives full context and returns results directly.

### 1. Service Restoration Agent (fg, FIRST)
Context reset kills background processes. Re-establish services and log captures:
1. Run `healthCheck` per service — healthy -> `verified-post-reset` — unhealthy -> `startCommand` + poll 5s/30s
2. Related projects: same check via `relatedProjects[]`
3. Start webhook listeners
4. **Re-start log captures** per `references/log-monitoring-protocol.md` for all services with `logCommand`
5. **Gate**: any `failed-post-reset` -> **STOP**
6. Return updated Service Readiness Report with new log file paths and PIDs

### 2. Setup Agent (fg)
Read source files, compile Feature Context Documents, read CLAUDE.md files. Proceeds after completion.

### 3. Integration Suite Agents (fg, sequential, one at a time)
Each agent receives: Feature Context, explicit curl commands, security checklist subset (YES/PARTIAL items only), data seeding instructions (table, fields, values, commands per `references/data-seeding-protocol.md`), log file paths, DB consistency protocol, Tool Inventory subset.

Execution per suite: migrate -> capture dbBaseline -> seed (after schema discovery) -> POST_SEED check -> execute curls + security checks -> POST_TEST check -> cleanup -> POST_CLEANUP check.

After each suite: orchestrator checks service logs for errors (`grep ERROR/WARN --since timestamp`), runs DB consistency checks.

Reports back: PASS/FAIL per test, security observations, log findings, DB consistency, anomalies.

### 4. E2E Suite Agents (fg, sequential, one at a time) — only if `frontendType` != `api-only`
Each agent receives: user journey steps, browser tool config, chrome-devtools protocol (if `chromeDevtools: true` per `references/chrome-devtools-protocol.md`), log file paths, Service Readiness Report, Feature Context Document, Tool Inventory subset.

**Webapp**: Navigate with `agent-browser` -> snapshot -> execute journey -> re-snapshot + devtools check -> verify backend via curl -> verify DB.
**Mobile**: Present guided steps via `AskUserQuestion` -> user acts -> verify via curl/DB/logs.

Browser tool priority (skipping without attempting is PROHIBITED):
1. `agent-browser` (PRIMARY) — `open <url>` -> `snapshot -i` -> `click/fill @ref` -> re-snapshot
2. Playwright (FALLBACK) — if agent-browser unavailable/errors
3. Direct HTTP/API (LAST RESORT) — mark untestable parts as "guided"

Reports back: PASS/FAIL per step, screenshots, network/console findings, backend verification, logs.

### 5. Regression Agent (fg, after autonomous suites)
Run `testing.unitTestCommand` once. Report total/passed/failed/skipped. Never interleaved with other suites.

### 6. Guided Happy-Path (MAIN CONVERSATION, optional, if user approved — LAST)
Runs LAST — after all autonomous suites and regression. No browser automation. Category 1 only.
Each happy-path scenario is a separate task (`Phase 4.6.{M}`).

**Per-scenario flow** (orchestrator drives — NOT delegated to a single subagent):
1. TaskUpdate(scenario task, status: "in_progress")
2. **Seed**: Spawn subagent (fg) to seed DB and set up prerequisites for this scenario
3. **Per-step loop** (for each step in the scenario):
   a. Orchestrator presents step via `AskUserQuestion` (MANDATORY — text output PROHIBITED):
      Options: `["Done - ready to verify", "Skip this test", "Issue encountered"]`
   b. If "Done": spawn verification subagent (fg) that:
      - Checks service logs since step start (grep ERROR/WARN --since timestamp)
      - Runs DB queries to verify expected state changes from this step
      - Runs API verification calls if applicable
      - Reports: PASS/FAIL with log findings + DB state analysis
   c. If verification FAIL: record finding, continue to next step (do not halt scenario)
   d. If "Skip": record SKIPPED, continue
   e. If "Issue encountered": record user's description, continue
4. After all steps: TaskUpdate(scenario task, status: "completed")
5. Next scenario

### Critical Execution Rules
- Never create batch scripts — each test explicitly passed to subagent
- Explicit data seeding instructions (table, fields, values, commands) — never guess
- Each subagent receives applicable security checklist items only
- Each subagent receives log file paths to check after execution
- Orchestrator checks logs between suites
- **Credential assignment**: Rotate role names from `testCredentials` across suites (round-robin: suite 1 gets role A, suite 2 gets role B, wraps to role A if more suites than roles) — pass role name only, never values
- **Finding verification** (mandatory): identify source code -> read to confirm -> distinguish real vs agent-created -> report only confirmed. Unconfirmed -> `Severity: Unverified` in `### Unverified`
- **Anomaly detection**: duplicate records, unexpected DB changes, warning/error logs, slow queries, orphaned references, auth anomalies, unexpected response fields/status codes
- **External CLI guard**: Before any CLI command from `externalServices[]`, verify the subcommand is in `allowedOperations` and no `prohibitedFlags` are present. Reject non-matching commands.
- Prohibited: multiple concurrent subagents, parallel execution. Exception: guided happy-path runs in main conversation (orchestrator presents steps, subagents seed and verify)

## Phase 5 — Results & Docs

**Fix cycle**: Runtime-fixable issues -> verify real (re-read error, retry once, confirm root cause) -> spawn subagent to fix -> re-run suite -> max 3 cycles. Code bug -> document + ask user.

**Documentation**: Spawn subagent (foreground). Timestamp via `date -u +"%Y-%m-%d-%H-%M-%S"`. Pattern: `{timestamp}_{semantic-name}.md`. Read `references/templates.md`. Four doc types: test-results (always — rename header to "Test Results"), pending-fixes (bugs/infra), pending-guided-tests (browser/visual/physical), pending-autonomous-tests (identified but not run). Include service log analysis, DB consistency results (if WARN/FAIL).

**Cleanup**: Spawn subagent (foreground). Remove `testDataPrefix` data only. Never touch pre-existing. Kill log capture processes. Remove `/tmp/test-logs-{sessionId}/`. Verify cleanup. Log actions.

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
| Subagents only | All execution via Agent(subagent_type: "general-purpose"). Main-conversation execution PROHIBITED |
| Model inheritance | Subagents inherit from main conversation — ensure Opus is set |
| Strictly sequential | One agent at a time in Phases 4-5. Spawn -> complete -> shut down -> next |
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
| Guided happy-path = post-all | Guided happy-path runs last — after all autonomous suites AND regression |
| Post-discovery prompts | Standard mode only — skipped when `guided` arg or regression mode active |
| Documentation in every run | Test-results doc generated for every run. Embedded in plan execution protocol |
| DB consistency inline | POST_SEED, POST_TEST, POST_CLEANUP checks within Phase 4 per suite |
| Task tracking per phase | TaskCreate for all execution phases at plan start. TaskUpdate in_progress/completed around each. Phase Orchestration Protocol embedded in plan |
| Guided = main conversation | Orchestrator presents steps via AskUserQuestion. Subagents seed DB and verify logs/DB per step. NOT delegated to a single subagent |
| Guided = per-scenario tasks | Each happy-path scenario gets its own task (Phase 4.6.{M}) |

## Operational Bounds

| Bound | Constraint |
|---|---|
| Max agents | Approved test suites + one service restoration agent + one setup agent + one regression agent |
| Max fix cycles | 3 per suite |
| Health check timeout | 30s per service |
| Capability cache | `rescanThresholdDays` (default 7 days) |
| Command scope | User-approved config commands only |
| Docker scope | Local only — Phase 1 aborts on production indicators |
| Credential scope | Env var references only — raw values forbidden, redacted on display |
| MCP scope | `safe: true` only |
| Subagent lifecycle | One foreground subagent at a time in Phases 4-5 |
| Explore agent scope | One per Phase 2. Read-only |
| External CLI scope | `allowedOperations` only. Per-run confirmation. Blocked when `cli.blocked` |
| System commands | `which`, `docker compose ps`, `git branch`/`diff`/`log`, `test -f`, `find . -maxdepth 3 -name "CLAUDE.md" -type f`, `date -u`, `curl -sf` localhost, `python3 -c` json/hashlib only |
| External downloads | Docker images via user's compose only. Playwright browsers if present. No other downloads |
| Data access | Outside project: `~/.claude/settings.json` (RO), `~/.claude/trusted-configs/` (RW), `~/.claude/CLAUDE.md` (RO). `.env` scanned for patterns only |
| Trust boundaries | Config SHA-256 verified out-of-repo. Untrusted inputs -> analysis only -> plan -> user approval |
| Guided happy-path scope | Category 1 only. No browser automation. Sequential. Runs last |
| Documentation output | Minimum 1 doc (test-results) per run. Embedded in execution protocol for post-reset survival |
