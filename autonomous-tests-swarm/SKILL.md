---
name: autonomous-tests-swarm
description: 'Run autonomous E2E tests with per-agent Docker isolation. Each agent spins up its own database, API, and services on unique ports — true parallel testing with zero credential conflicts. Args: staged | unstaged | N | working-tree | file:<path> | rescan | guided [description]'
argument-hint: 'staged | unstaged | N | working-tree | file:<path> | rescan | guided'
disable-model-invocation: true
allowed-tools: Bash(*), Read(*), Write(*), Edit(*), Glob(*), Grep(*), Agent(*),
  EnterPlanMode(*), ExitPlanMode(*), AskUserQuestion(*)
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
- Use Agent() to spawn subagents for delegation
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

1. **ExitPlanMode hook** (informational): if absent, inform user it's skill-scoped and works automatically. Continue.
2. **AskUserQuestion hook** (informational): same as above. Continue.

**Step 1: Capabilities Scan** — delegate to Explore agent.

Triggers: `rescan` present, `capabilities` missing, or `lastScanned` older than `rescanThresholdDays` (default 7). If none, use cache.

Spawn ONE Explore agent (`subagent_type: "Explore"`, thoroughness: `"medium"`) for three parallel checks:
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

Spawn ONE general-purpose subagent (foreground). Agent performs:

1. **Production scan**: `.env` files for `productionIndicators`, `*LIVE*SECRET*`, `NODE_ENV=production`, production DB endpoints, non-local URLs. Show variable NAME only.
2. Run `sandboxCheck` commands from config
3. Verify Docker is local
4. **Related project safety scan**: For each `relatedProjects[]` entry with a `path`:
   - Scan `.env` files in the related project path for the same production indicators (`productionIndicators`, `*LIVE*SECRET*`, `NODE_ENV=production`, production DB endpoints, non-local URLs)
   - Show variable NAME + related project name if found
   - Any production indicator in a related project triggers the same **ABORT** gate as the main project
5. Verify Docker context matches `swarm.dockerContext` (switch if needed)
6. Create `/tmp/autonomous-swarm-{sessionId}` (`date -u +%Y%m%d%H%M%S` for sessionId)
7. Scan port ranges from `swarm.portRangeStart` per agent via `ss -tlnp`/`netstat -tlnp` or socket test. Skip conflicts.
8. Reserve and store assignments
9. Validate: compose → `docker compose -f {file} config --quiet`; raw Docker → `docker image inspect || docker pull`; disk space → `docker system df`
10. If `swarm.audit.enabled` (default true): `mkdir -p .../audit/`, write `session.json` (`schemaVersion: "1.0"`, sessionId, timestamp, branch, scope, agent count, limits)

Agent reports: safety assessment, port assignments, validation results, audit status.

Orchestrator: **ABORT** if production detected. Keep port assignments for Phase 3.

## Phase 2 — Discovery

Fully autonomous — derive from code diff, codebase, or guided source. Never ask user what to test.

Spawn ONE Explore agent (`subagent_type: "Explore"`, thoroughness: `"medium"`).

### Standard mode

1. Get changed files from git (include `relatedProjects[].path` for cross-project tracing)
2. If `file:<path>` provided, read `.md` → extract features, criteria, endpoints, edge cases
3. Spawn Explore agent with: changed files, file reference content, `relatedProjects[]`, `testing.contextFiles`, CLAUDE.md paths, `documentation.*` paths. Agent performs:
   - **Feature map**: endpoints, DB operations (MongoDB: `find`/`aggregate`/`insertMany`/`updateOne`/`deleteMany`/`bulkWrite`/`createIndex`, schema changes; SQL: `SELECT`/`INSERT`/`UPDATE`/`DELETE`/`JOIN`/`GROUP BY`/`CREATE TABLE`/`ALTER TABLE`/`CREATE INDEX`, migrations, ORM ops), external services, business logic, auth flows, signal chains
   - **Dependency graph**: callers → changed code → callees, across files and projects
   - **Smart doc analysis**: (a) match paths/features/endpoints against `docs/` tree, (b) `_autonomous/` scan — Summary + Issues Found only, extract prior failures/bugs, (c) fix completion scan — `Status: RESOLVED` + `Verification: PASS` → regression targets, `Ready for Re-test: YES` → priority re-test
   - **Edge case inventory**: error handlers, validation branches, race conditions, retry logic
   - **Cross-project seed map**: For each `relatedProjects[]`, trace which collections/tables in the related project's database are read by the main project's E2E flows (shared users, linked entities, cross-service references). Per dependency: related project name, collection/table, required fields, relationship to main project data, connection command from `relatedProjects[].database.connectionCommand` or inferred from config.
   - **Test flow classification**: Classify each test scenario as `autonomous/api` (API-only, no UI), `autonomous/ui` (browser automation needed), `guided/webapp` (user performs actions in web browser), or `guided/mobile` (user performs actions on physical mobile device). For related projects with `relationship: "mobile"`, trace user flows → classify as `guided/mobile`.
   - **Related project log commands**: Discover log commands per `relatedProjects[]` entry — from `logCommand` field, or inferred from `startCommand`/compose config. Record for post-test log verification.
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

Compile from agent report (do NOT re-read analyzed files). Contains: features, endpoints, DB tables/collections, cross-project seed map (related project DB dependencies with collection/table, required fields, connection commands), test flow classifications, related project log commands, external services, edge cases, prior history, capabilities. Guided mode adds `Mode:` and `Source:` at top. Cascaded to all agents in Phase 4.

### Live E2E Eligibility Analysis (standard mode only — skip in guided and regression)

After the Feature Context Document is compiled, the orchestrator cross-references features with capabilities to determine which external services are both available and relevant to the code being tested:

1. **Extract external service usage from feature map**: Collect all external services referenced by the changed code (webhook handlers, API calls, storage operations). Each entry: service name, operations used, code paths.
2. **Cross-reference with capabilities**: For each service in the feature map, check `externalServices[]` in config:
   - `cli.available && !cli.blocked` → **eligible** (available in sandbox)
   - `cli.available && cli.blocked` → **blocked** (production keys detected)
   - `!cli.available` → **unavailable** (CLI not installed)
   - Also check `capabilities.dockerMcps[]` for relevant sandbox MCPs
3. **Compile eligibility list**: Per eligible service: name, mode, relevant `allowedOperations` matching the feature map, applicable MCP tools. Only services that are both available and relevant to the changed code appear.
4. **Store**: `liveE2eEligibility: { eligible: [...], blocked: [...], unavailable: [...] }` — carried to prompts and Phase 3.

### Post-Discovery Prompts (standard mode only — skip if `guided` arg present or regression mode)

After Feature Context Document and Live E2E Eligibility Analysis, prompt the user before entering plan mode. Use a single `AskUserQuestion` to reduce friction:

```
Based on the discovered features, I have two optional additions:

{IF liveE2eEligibility.eligible is non-empty}
1. **Live E2E Testing** — The changed code interacts with external services available in sandbox mode:
{for each eligible service}
   - {service.name} ({service.mode}): {comma-separated relevant allowedOperations[].command}
{end for}
   These run after the standard autonomous tests, using real CLI/MCP calls. Each service requires your approval again at runtime before any CLI call.
   → Include live E2E suites? (yes/no)
{ELSE}
1. **Live E2E Testing** — No external services are both available and relevant to the changed code. Skipping.
{END IF}

2. **Guided Happy Path** — After all autonomous tests, I can generate a guided test plan where you perform actions on your device/browser while I verify results via DB/API/logs. Happy-path workflows only.
   → Include guided happy-path section? (yes/no)

Reply with your choices (e.g., "yes to both", "live e2e yes, guided no", "no to both").
```

Parse response into two boolean decisions:
- `liveE2eApproved` (forced `false` if eligibility list was empty)
- `guidedHappyPathApproved`

If eligibility list is empty AND `guided` arg present → skip prompt entirely.

## Phase 3 — Plan (Plan Mode)

**Enter plan mode.** Plan starts with:

**Step 0 — Context Reload**: re-read SKILL.md, config, templates (`autonomous-tests/references/templates.md`). Restore: resolved `$ARGUMENTS`, branch, commit range, Phase 2 findings, `userContext`, swarm config, port assignments, init commands, related project map. If regression mode: fix manifest, 1-hop impact zone, original test IDs, Targeted Regression Context Document. If guided: type, source, and full guided test list with per-test seed requirements.
- If live E2E approved: eligibility list (per-service: name, mode, relevant operations, MCP tools), user approval status
- If guided happy path approved: list of happy-path workflows from Feature Context Document with per-test seed requirements, user instructions, verification queries

**Tool loading gate**: If autonomous mode needs agent-browser/Playwright, list tools and prompt user via AskUserQuestion before plan approval. Declined tools excluded from plan. Guided mode: NEVER include browser automation tools — skip this gate entirely.

**Self-containment mandate** — the plan MUST embed directly (not reference "above" or prior phases):
1. All test suites with full details (name, objective, pre-conditions, steps, expected outcomes, teardown, verification)
2. Feature Context Document (condensed but complete)
3. Service Readiness Report from Phase 1 (port assignments, health status)
4. Per-suite agent spawn instructions with resolved values (swarm-{N} spec, ports, Docker context, compose path, capabilities snapshot, Feature Context Document)
5. Config paths: `documentation.*`, `database.connectionCommand`, `testing.unitTestCommand`, `testDataPrefix`
6. Swarm config: port assignments, init commands, related project map
7. If guided: per-test DB seed commands, user-facing step-by-step instructions, and verification queries
8. Seed schema discovery mandate (embedded verbatim for Phase 4 suite agents)
9. If live E2E approved: Live E2E Decision block — per-service: name, mode, relevant `allowedOperations`, applicable MCP tools, `userPromptTemplate` for runtime CLI gate. Embedded verbatim so post-reset orchestrator can prompt and execute.
10. If guided happy path approved: Guided Happy Path Decision block — per-test: name, objective, prerequisites, step-by-step user instructions, DB seed commands, verification queries, expected outcomes.
11. Documentation checklist (always embedded, never conditional) — the post-reset orchestrator needs this to know what files to generate after testing. Include: output directories from config (`documentation.*` paths), template reference path (`references/templates.md`), filename convention (`{timestamp}_{semantic-name}.md`, timestamp from `date -u`), and which doc types this run produces. At minimum: test-results doc. Conditionally: pending-fixes (if failures/findings exist), pending-guided-tests (if guided tests identified or approved), pending-autonomous-tests (if tests queued but not run). Without this embedded checklist, the orchestrator has no way to know about doc generation after context reset — which is why it gets skipped.

- Execution Protocol — autonomous mode (embed verbatim — orchestrator uses this after context reset):
  ```
  SETUP: Spawn general-purpose subagent (foreground). Creates agent dirs, generates modified compose/docker scripts with remapped ports, copies+remaps env files, validates configs, freezes capabilities snapshot, applies resource limits + Docker labels, reads source files, returns specs.
  SCHEMA GATE: Every suite agent MUST complete seed schema discovery (query real doc or read service code) BEFORE any database write. Proceeding without schema analysis is PROHIBITED.
  FLOW: PARALLEL — background subagents:
    1. Set Docker context
    2. Confirm port ranges
    3. Spawn ALL suite subagents simultaneously (run_in_background: true)
    4. Each receives in prompt: pre-generated specs (swarm-{N}, ports, Docker context, compose path), frozen capabilities, Feature Context Document
    5. All subagents execute in parallel — orchestrator notified on completion
  LIVE E2E (conditional): Sequential only. Execute if plan contains liveE2eApproved: true. Follow live E2E execution protocol.
  GUIDED HAPPY PATH (conditional): Sequential only. Execute if plan contains guidedHappyPathApproved: true. Follow guided happy path execution protocol.
  DOCUMENTATION: Follow documentation execution protocol. Generate all applicable doc types. Runs even on all-pass results.
  FAILURE: Spawn replacement background subagent for failed suite
  POST-COMPLETION: Spawn foreground subagent for Docker cleanup + audit merge + temp dir removal
  ```

- Execution Protocol — guided mode (embed verbatim):
  ```
  MODE: User augmentation
  NO BROWSER AUTOMATION: agent-browser and Playwright MUST NOT be loaded
  NO PARALLEL SUBAGENTS: Guided mode overrides parallel protocol. One foreground subagent at a time, sequential.
  CATEGORIES: Happy-path workflows ONLY
  FLOW: For each guided test (in order):
    1. Spawn ONE general-purpose subagent (foreground) for DB seeding + external service setup
    2. Subagent seeds database, configures services, returns readiness status
    3. Orchestrator presents steps to user via AskUserQuestion
    4. User performs actions on real device/browser
    5. Orchestrator verifies results via DB queries/API/logs
    6. Record PASS/FAIL → next test
  PROHIBITED: agent-browser, Playwright, parallel subagents, security/edge-case/validation tests
  ```

- Execution Protocol — live E2E mode (embed verbatim — conditional, only if liveE2eApproved):
  ```
  RUNS AFTER: All parallel autonomous suites complete.
  SEQUENTIAL ONLY: Live E2E does not use swarm Docker isolation — it runs against the shared local stack, one subagent at a time. External services shouldn't receive concurrent conflicting requests.
  SERVICES: {embedded per-service details from Live E2E Decision block}
  FLOW: Sequential — one subagent at a time:
    1. For each live E2E suite:
       a. CLI gate: AskUserQuestion per service using embedded userPromptTemplate (once per service, not per suite)
       b. Declined → skip that service's suites, mark "skipped — user declined at runtime"
       c. Approved → cli.approvedThisRun: true
       d. Sandbox check: agent re-runs modeDetection.command before first CLI call. If production detected → abort live E2E for that service (keys may have changed since Phase 0).
       e. Spawn ONE general-purpose subagent (foreground) with full context + CLI details + allowed/prohibited operations
       f. Record PASS/FAIL → next suite
  ```

- Execution Protocol — guided happy path mode (embed verbatim — conditional, only if guidedHappyPathApproved):
  ```
  RUNS AFTER: All autonomous suites AND live E2E suites (if any). Guided runs last because it requires the user's active participation — pausing autonomous work mid-flow would be disruptive.
  SEQUENTIAL ONLY: Overrides parallel protocol — one foreground subagent at a time.
  NO BROWSER AUTOMATION: The user performs all actions. agent-browser and Playwright are not loaded.
  CATEGORIES: Happy-path workflows only (category 1). Edge cases, security, and validation are autonomous-only — they don't benefit from manual execution.
  FLOW: For each guided test:
    1. Spawn ONE general-purpose subagent (foreground) for DB seeding + service setup
    2. Subagent seeds database (seed schema discovery mandate), returns readiness
    3. Orchestrator presents steps to user via AskUserQuestion
    4. User performs actions on real device/browser
    5. Orchestrator spawns verification subagent — DB/API/log checks
    6. Record PASS/FAIL → next test
  ```

- Execution Protocol — documentation (embed verbatim — always present, never conditional):
  ```
  RUNS AFTER: All test phases (autonomous + live E2E + guided) complete.
  WHY THIS EXISTS IN THE PLAN: After context reset, Phase 5 instructions in the SKILL.md are no longer in context. Without this block, the orchestrator completes suites and stops — no docs get written. This block ensures doc generation happens.
  WHAT TO GENERATE:
    - test-results doc (always — even if every test passed, the record matters for regression tracking and audit trails)
    - pending-fixes doc (when any test failed or findings were reported)
    - pending-guided-tests doc (when guided tests were identified or guidedHappyPathApproved)
    - pending-autonomous-tests doc (when tests were identified but not executed)
  HOW:
    1. Spawn general-purpose subagent (foreground)
    2. Read references/templates.md for structure
    3. Get timestamp: date -u +"%Y-%m-%d-%H-%M-%S"
    4. Filename: {timestamp}_{semantic-name}.md
    5. Write to directories from the documentation checklist embedded in this plan
    6. Include ALL results: autonomous + live E2E (if run) + guided (if run)
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
- Execution protocol: unchanged (same subagent parallel flow, just fewer suites)
- **Swarm efficiency note**: If regression scope produces <=2 suites, swarm Docker isolation overhead may exceed the benefit. The plan should note this but still execute as configured.

**Wait for approval.**

## Phase 4 — Execution (Agent Swarm)

Spawn `general-purpose` subagents (one per suite or grouped). All parallel via `run_in_background: true`. Results returned directly to orchestrator.

**Cascading context**: every agent gets full Feature Context Document from Phase 2.

**Capability-aware execution (autonomous mode ONLY)**: `agent-browser` first for UI if available → Playwright fallback → `mcp-add` safe MCPs → **External CLI gate**: prompt user once per service via `AskUserQuestion`, approved → `allowedOperations` only, declined → mark as "guided". Never use `safe: false` MCPs or `cli.blocked` CLIs.

**Guided mode execution**: No browser automation. No parallel agents. User performs all UI interactions. Swarm Docker isolation NOT used in guided mode — tests run against shared local stack.

**Anomaly detection**: duplicate records, unexpected DB changes, warning/error logs, slow queries, orphaned refs, auth anomalies, response anomalies. **Finding verification mandatory** — read source to confirm. Unconfirmed → `Severity: Unverified` in `### Unverified` subsection.

**API Response Security Inspection**: exposed IDs, leaked credentials, PII, compliance. **Source verification mandatory** — read model/serializer/DTO definitions. Synthetic data findings are false positives.

**Setup agent (MANDATORY)** — spawn first (general-purpose subagent, foreground):
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
11. Return validated specs + Feature Context Document

Orchestrator receives setup results, then spawns suite subagents with pre-generated specs.

**Suite agent tasks (a-l)**:
- **a. Spec**: project name `swarm-{N}`, ports, Docker context, compose path
- **b. Capabilities**: frozen snapshot only
- **c. Compose setup**: verify + `docker compose -p swarm-{N} -f ... up -d`
- **d. Raw Docker setup**: `docker run -d --name swarm-{N}-{service} ...`, create/connect network `swarm-{N}-net`
- **e. npm-dev setup**: `rsync` project (exclude node_modules/.next/dist/.turbo), set up node_modules, resolve env overrides (`{port}`/`{backendPort}`), start in background (capture PID), remap env files
- **f. Health check**: poll remapped ports, 60s timeout, 2 attempts → report failure for redistribution
- **g. Init**: run `swarm.initialization.commands` with namespace resolution. Wait `waitAfterStartSeconds`. Related project init.
- **h. DB seeding**: adapted `migrationCommand`, `seedCommand`, `connectionCommand`, `cleanupCommand` with `swarm-{N}` namespace. **Seed schema analysis gate** (MANDATORY — before ANY database write): Agents must complete schema analysis and report discovered schemas BEFORE executing any insert/seed operation. Proceeding without schema analysis is PROHIBITED. **Seed schema discovery** (mandatory for autonomous seeding — applies to ALL databases in the E2E flow, including related projects): Before inserting into ANY collection/table: (1) query for a real document/row (`findOne`/`SELECT * LIMIT 1` without test prefix filter) to use as schema template, (2) if empty, read the backend service code that creates documents in that collection (look for `insertOne`/`find_one_and_update`/`INSERT`/ORM create calls), (3) mirror the discovered schema exactly — never invent fields or change types (ObjectId vs string, Date vs string, etc.), (4) only add `_testPrefix` marker as extra field, (5) for related project collections: use the connection command from `relatedProjects[]` config or the cross-project seed map in the Feature Context Document. After all seeds (main + related): hit the API read endpoints (via the agent's remapped ports) to verify serialization before proceeding to test execution.
- **i. Execute**: test suites against agent's API (remapped ports)
- **j. Report**: PASS/FAIL + anomalies returned to orchestrator
- **k. Audit** (when enabled): `agent-{N}.json` → `schemaVersion: "1.0"`, agentId, suites, environment, timeline (`{ timestamp, action, target, result }`), configuredLimits (no `docker stats`), teardown status, duration
- **l. Teardown (ALWAYS)**: compose `down -v --remove-orphans` / raw docker stop+rm+network rm / npm-dev kill PIDs / remove agent temp dir / verify no lingering containers

**Execution flow**:
1. Set Docker context
2. Confirm port ranges
3. Spawn all suite subagents (`run_in_background: true`) with pre-generated specs in prompt
4. All parallel — orchestrator notified on completion
5. **Failure redistribution**: failed subagent's suites → spawn replacement background subagent. Failed subagent tears down.
6. **Live E2E suites (conditional — only if plan contains liveE2eApproved: true)**:
   - Runs after all parallel autonomous suites complete and results are recorded
   - Does not use swarm Docker isolation — runs against the shared local stack
   - CLI gate: per service, AskUserQuestion using embedded userPromptTemplate. Declined → skip. Approved → cli.approvedThisRun: true.
   - Sandbox re-verification before first CLI call. Production detected → abort for that service.
   - Sequential: one foreground subagent per suite, full context including CLI details and allowed/prohibited operations
   - Record PASS/FAIL, check related project logs
7. **Guided happy-path tests (conditional — only if plan contains guidedHappyPathApproved: true)**:
   - Runs last — after autonomous and live E2E (if any)
   - Overrides parallel protocol — one foreground subagent at a time
   - For each test: seed DB → present steps to user → user acts → verify via DB/API/logs → PASS/FAIL
   - No browser automation. No parallel agents. Category 1 only.
8. Post-completion Docker cleanup verification (spawn foreground subagent):
   - Name-based: `docker ps -a --filter name=swarm- -q` → empty
   - Label-based: `docker ps -a --filter label=com.autonomous-swarm.session={sessionId} -q` → empty
   - Networks: `docker network ls --filter label=...session={sessionId} -q` → empty
   - Volumes: `docker volume ls --filter label=...session={sessionId} -q` → empty
   - Clean orphans if any
9. Merge audit logs (when enabled) → `audit-summary.json` (`schemaVersion: "1.0"`, metadata, per-agent, totals, cleanup verification)
10. `rm -rf /tmp/autonomous-swarm-{sessionId}`

## Phase 5 — Results & Docs

### Fix cycle
- **Runtime-fixable** (env var, container, stuck job): before attempting any fix, verify the issue is real — re-read error output, check if transient (retry once), confirm root cause in logs/config. Only fix after confirming genuine issue. Fix → re-run → max 3 cycles.
- **Code bug**: document (file, line, expected vs actual) → ask user

### Documentation
Delegate to agent. Dirs from config. Timestamp via `date -u +"%Y-%m-%d-%H-%M-%S"`. Pattern: `{timestamp}_{semantic-name}.md`. Read `autonomous-tests/references/templates.md` for structure.

Doc types: **test-results** (always generated — the record is essential for regression tracking even when all tests pass), **pending-fixes** (bugs/infra), **pending-guided-tests** (browser/visual/device + guided happy-path tests if approved), **pending-autonomous-tests** (identified but not run). If live E2E or guided happy-path tests were executed, include their results in the test-results doc under dedicated suite sections. The documentation subagent receives all test results (autonomous + live E2E + guided) and generates unified output.

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
| Delegate via subagents | Phases 4-5 |
| Model inheritance | Subagents inherit from main conversation — ensure Opus is set |
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
| Guided = single subagent | Override parallel protocol — one foreground subagent at a time in guided mode |
| Seed schema discovery | Before seeding any DB (main or related project): query real doc or read service code for schema. Mirror exactly — never invent fields or change types. Verify via API after seeding |
| Live E2E = sandbox only | Live E2E suites require sandbox/test mode. Re-verified at runtime before CLI calls |
| Live E2E = post-autonomous | Live E2E runs after all autonomous (mocked) suites complete |
| Guided happy path = post-all | Guided happy-path runs last — after autonomous and live E2E |
| Post-discovery prompts | Standard mode only — skipped when `guided` arg or regression mode active |
| Documentation in every run | Test-results doc generated for every run. Embedded in plan execution protocol so it survives context reset |

## Operational Bounds

- **Max agents**: suites + 1 setup, capped at `swarm.maxAgents + 1` (default 6)
- **Max fix cycles**: 3 per suite
- **Health check**: 60s timeout, 2 attempts
- **Capability cache**: `rescanThresholdDays` (default 7)
- **Commands**: only user-approved config commands — no dynamic generation
- **Docker**: local only, Phase 1 aborts on production. Namespaced `swarm-{N}`, original compose untouched.
- **Credentials**: N/A — each agent seeds own data
- **MCPs**: only `safe: true` activated
- **Subagents**: spawn → Docker → execute → teardown → return results. No persistent agents.
- **External CLIs**: `allowedOperations` only, per-run confirmation, blocked when `cli.blocked`. `prohibitedFlags`/`prohibitedOperations` always blocked.
- **System commands**: `which`, `docker compose ps`/`context ls`/`system df`, `docker ps -a --filter label=`, `docker network/volume ls --filter label=`, `git branch`/`diff`/`log`, `test -f`, `find . -maxdepth 3 -name "CLAUDE.md"`, `date -u`, `ss -tlnp`/`netstat -tlnp`, `curl -sf` localhost, `python3 -c` (json/hashlib/re), `cp -al`. `setup-hook.sh` modifies settings once at install only.
- **Downloads**: Docker images from project compose/config only. Playwright browsers if present. No other runtime downloads.
- **Data access**: outside project: `~/.claude/settings.json` (read), `~/.claude/trusted-configs/{hash}.sha256` (read/write), `~/.claude/CLAUDE.md` (read). CLAUDE.md 3 levels deep (read). `.env` scanned for patterns only — values never stored/logged/output. Modified files only in `/tmp/`.
- **Resource limits**: compose `mem_limit`/`cpus`/`read_only`/`tmpfs`, raw Docker `--memory`/`--cpus`/`--read-only`/`--tmpfs`. Non-null only. Per-container. Audit records configured, not runtime.
- **Labels**: `com.autonomous-swarm.managed=true`, `.session=`, `.agent=`. Hardcoded. Secondary cleanup verification.
- **Capabilities freeze**: setup agent snapshot → verbatim to suite agents. No re-scan.
- **Audit**: when enabled, agents write `agent-{N}.json` to `/tmp/.../audit/`, orchestrator merges to `audit-summary.json` (all `schemaVersion: "1.0"`). Only orchestrator copies to `docs/_autonomous/`.
- **Explore agents**: one per Phase 2. Read-only.
- **Trust**: config SHA-256 vs out-of-repo trust store. Untrusted inputs → analysis → Feature Context Document → plan → user approval via ExitPlanMode. No untrusted content in shell commands.
- **Live E2E scope**: Eligible services only (cli.available && !cli.blocked && feature-relevant). allowedOperations only. Runtime sandbox re-verification. Does not use swarm Docker isolation.
- **Guided happy path scope**: Category 1 only. No browser automation. Sequential (overrides parallel protocol). Runs last.
- **Post-discovery prompts**: Standard mode only — skipped for `guided` arg or regression mode.
- **Documentation output**: Minimum 1 doc (test-results) per run. Embedded in execution protocol for post-reset survival.
