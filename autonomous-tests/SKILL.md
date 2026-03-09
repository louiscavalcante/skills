---
name: autonomous-tests
description: 'Run autonomous E2E tests. Args: staged | unstaged | N (last N commits) | working-tree
  | file:<path> | rescan | guided [description] (default: working-tree with smart doc analysis). Example: /autonomous-tests guided "payment checkout flow"'
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
- Config: !`test -f .claude/autonomous-tests.json && echo "YES" || echo "NO -- first run"`
- Capabilities: !`python3 -c "import json;c=json.load(open('.claude/autonomous-tests.json'));caps=c.get('capabilities',{});mcps=len(caps.get('dockerMcps',[]));ab='Y' if caps.get('frontendTesting',{}).get('agentBrowser') else 'N';pw='Y' if caps.get('frontendTesting',{}).get('playwright') else 'N';ec=sum(1 for s in c.get('externalServices',[]) if s.get('cli',{}).get('available'));print(f'MCPs:{mcps} agent-browser:{ab} playwright:{pw} ext-clis:{ec} scanned:{caps.get(\"lastScanned\",\"never\")}')" 2>/dev/null || echo "NOT SCANNED"`

## Role

Project-agnostic autonomous E2E test runner. Exercise features against the live LOCAL stack, verify state at every step, produce documentation, never touch production.

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

User performs all actions on their real device/browser. Claude provides step-by-step instructions and verifies results via DB queries/API/logs. Only happy-path workflows in guided mode. Categories 2-9 handled exclusively in autonomous mode — NEVER in guided session. No agent-browser, no Playwright — guided mode never loads or uses browser automation tools.

`guided` alone prompts via `AskUserQuestion` to pick a doc or describe a feature. Combinable with `rescan` but NOT with `staged`/`unstaged`/`N`/`working-tree` (git-scope args incompatible — guided bypasses git diff).

Smart doc analysis always active in standard mode: match `docs/` files to changed code by path, feature name, cross-references — read only relevant docs.

Print resolved scope, then proceed without waiting.

---

## Phase 0 — Bootstrap

**Config hash method**: `python3 -c "import json,hashlib;d=json.load(open('.claude/autonomous-tests.json'));[d.pop(k,None) for k in ('_configHash','lastRun','capabilities')];print(hashlib.sha256(json.dumps(d,sort_keys=True).encode()).hexdigest())"` — referenced throughout as "Config hash method".

**Step 0: Prerequisites Check** — Read `~/.claude/settings.json`:
1. **ExitPlanMode hook** (informational): if missing → inform user the skill-scoped hook handles it automatically; global setup available via the script. Continue.
2. **AskUserQuestion hook** (informational): same as above. Continue.

**Step 1: Capabilities Scan** — Triggers: `rescan` arg, `capabilities` missing, or `lastScanned` older than `rescanThresholdDays` (default 7 days). If none → use cache.

Spawn **Explore agent** (`subagent_type: "Explore"`, thoroughness: `"medium"`) to perform:
1. **Docker MCP Discovery**: `mcp-find` for MCPs matching service names and generic queries. Record `name`, `description`, `mode`; `safe: true` only for known sandbox MCPs. If unavailable → empty array.
2. **Frontend Testing**: `which agent-browser`, `which playwright`/`npx playwright --version` → set `frontendTesting` booleans.
3. **External Service CLI Detection**: Load `references/external-services-catalog.json`. Scan CLAUDE.md files for `claudeMdKeywords`. Per match: run `detectionCommand` → if unavailable, `cli.available: false` → if available, run `modeDetection.command` → pattern-match: production → `live`/blocked, sandbox → `sandbox`/unblocked, else → `unknown`/unblocked → warn if blocked → populate `allowedOperations`/`prohibitedFlags` → merge into `externalServices[]`.

Agent reports back. Orchestrator writes to `capabilities` with `lastScanned` = UTC time (`date -u`).

**CLAUDE.md deep scan** (Phase 0 + Phase 2): `find . -maxdepth 3 -name "CLAUDE.md" -type f` + `~/.claude/CLAUDE.md` + `.claude/CLAUDE.md`. Cache list for: capabilities scan, auto-extract, Phase 2 enrichment, Feature Context Document. Read each once.

**Step 2: Config Check** — `test -f .claude/autonomous-tests.json && echo "CONFIG_EXISTS" || echo "CONFIG_MISSING"`. Schema: `references/config-schema.json`.

### If `CONFIG_EXISTS` (returning run):
1. Read config.
2. **Version validation**: require `version: 5` + fields `project`, `database`, `testing`. v4→v5: migrate `*Cli` fields from `capabilities` to `externalServices[].cli`. v3→v4→v5: add empty `capabilities` first. <3 or missing fields → warn, re-run first-run.
   - Missing `database.seedStrategy` → default `"autonomous"`, inform user.
   - Missing `documentation.fixResults` → add `"docs/_autonomous/fix-results"`.
   - Legacy `userContext.credentialType` → delete silently.
3. **Config trust**: Compute hash using **Config hash method**. Check trust store `~/.claude/trusted-configs/{project-hash}.sha256` (project hash: `python3 -c "import hashlib,os;print(hashlib.sha256(os.path.realpath('.').encode()).hexdigest()[:16])"`). Mismatch → show config (redact `testCredentials` values as `"********"`) → `AskUserQuestion` for approval → write hash.
4. **Testing priorities**: Show `userContext.testingPriorities`. `AskUserQuestion`: "Pain points or priorities?" with "None" option to clear. Update config.
5. **Re-scan services**: Delegate to Explore agent (same as Step 1). Update config if needed.
6. `date -u +"%Y-%m-%dT%H:%M:%SZ"` → update `lastRun`.
7. Empty `userContext` → run questionnaire below, save.
8. **Re-stamp trust**: if config modified → recompute using **Config hash method**, write to trust store.
9. Skip to Phase 1.

### If `CONFIG_MISSING` (first run):
Spawn **Explore agent** (`subagent_type: "Explore"`, thoroughness: `"medium"`) for auto-extraction:
1. **Auto-extract** from CLAUDE.md files (deep scan) + compose + env + package manifests. Detect `migrationCommand`/`cleanupCommand` from compose, `scripts/`, Makefiles, package.json (`manage.py migrate`, `npx prisma migrate deploy`, `knex migrate:latest`, etc.). Detect seed commands.
   **DB type**: MongoDB (`mongosh`/`mongo`, `mongoose`/`mongodb`/`@typegoose`, `mongodb://`, mongo containers) vs SQL (`psql`/`mysql`/`sqlite3`, `pg`/`mysql2`/`sequelize`/`prisma`/`knex`/`typeorm`/`drizzle`/`sqlalchemy`/`django.db`, `postgres://`/`mysql://`/`sqlite:///`, SQL containers). Both found → ask user.
2. **Topology**: `single` | `monorepo` (workspace configs, multiple `package.json`, `backend/`+`frontend/`) | `multi-repo` (CLAUDE.md cross-refs, sibling `.git`, shared docker-compose).
3. **Related projects**: scan sibling dirs, grep for external paths → ask user per candidate → populate `relatedProjects`.

Agent reports. Orchestrator proceeds:
4. **Capabilities scan** — delegate (Step 1).
5. **Seeding strategy** via `AskUserQuestion`: autonomous (recommended, agents create per-suite data) or command (global seed command).
6. **User Context Questionnaire** (all at once, partial OK): flaky areas? credentials (env var/role names only)? priorities? notes? → store in `userContext`.
7. **Propose config** → STOP for confirmation → write.
8. **Stamp trust**: compute using **Config hash method** → write to trust store.
9. If CLAUDE.md < 140 lines and lacks startup instructions → append max 10 lines.

## Phase 1 — Safety & Environment

**Objective**: Verify the environment is safe and ready for testing.

Spawn ONE **general-purpose subagent** (foreground) to perform:
1. **Production scan**: `.env` files for `productionIndicators`, `*LIVE*SECRET*`, `NODE_ENV=production`, production DB endpoints (RDS, Atlas without dev/stg/test), non-local URLs. Show variable NAME only.
2. Run `sandboxCheck` commands from config.
3. Verify Docker is local.
4. **Related project safety scan**: For each `relatedProjects[]` entry with a `path`:
   - Scan `.env` files in the related project path for the same production indicators (`productionIndicators`, `*LIVE*SECRET*`, `NODE_ENV=production`, production DB endpoints, non-local URLs)
   - Show variable NAME + related project name if found
   - Any production indicator in a related project triggers the same **ABORT** gate as the main project
5. **Service startup**: per service in config + related projects with `startCommand`: health check → healthy: `already-running` → unhealthy: start + poll 5s/30s → `started-this-run` or report failure.
6. Start webhook listeners.
7. **Service Readiness Report**: per service — name, URL/port, health status, health check endpoint, source (`config`|`relatedProject`).

Agent reports: safety assessment + Service Readiness Report. Gates: **ABORT** if production. **STOP** if unhealthy. Keep report for Phase 3.

## Phase 2 — Discovery

Fully autonomous — derive from code diff, codebase, or guided source. Never ask what to test.

**Delegation**: ONE Explore agent (`subagent_type: "Explore"`, thoroughness: `"medium"`).

### Standard mode
1. Changed files from git (scope args) — include `relatedProjects[].path` for cross-project deps.
2. If `file:<path>` → read `.md`, extract features/criteria/endpoints/edge cases (supplements diff).
3. **Spawn Explore agent** with: changed files, file reference content, `relatedProjects[]`, `testing.contextFiles`, CLAUDE.md paths, `documentation.*` paths. Agent performs:
   - **Feature map**: API endpoints, DB ops (MongoDB: `find`/`aggregate`/`insertMany`/`updateOne`/`deleteMany`/`bulkWrite`/`createIndex`/schema changes; SQL: `SELECT`/`INSERT`/`UPDATE`/`DELETE`/`JOIN`/`GROUP BY`/`CREATE TABLE`/`ALTER TABLE`/`CREATE INDEX`/migrations/ORM), external services, business logic, auth flows, signal/event chains
   - **Dependency graph**: callers → changed code → callees, cross-file/project imports
   - **Smart doc analysis**: (a) match paths/features/endpoints against `docs/` (read relevant only), (b) `_autonomous/` scan (Summary + Issues Found only, extract prior failures/bugs), (c) fix completion scan (`RESOLVED`+`PASS` → regression targets, `Ready for Re-test: YES` → priority)
   - **Edge case inventory**: error handlers, validation branches, race conditions, retry logic
   - **Cross-project seed map**: For each `relatedProjects[]`, trace which collections/tables in the related project's database are read by the main project's E2E flows (shared users, linked entities, cross-service references). Per dependency: related project name, collection/table, required fields, relationship to main project data, connection command from `relatedProjects[].database.connectionCommand` or inferred from config.
   - **Test flow classification**: Classify each test scenario as `autonomous/api` (API-only, no UI), `autonomous/ui` (browser automation needed), `guided/webapp` (user performs actions in web browser), or `guided/mobile` (user performs actions on physical mobile device). For related projects with `relationship: "mobile"`, trace user flows → classify as `guided/mobile`.
   - **Related project log commands**: Discover log commands per `relatedProjects[]` entry — from `logCommand` field, or inferred from `startCommand`/compose config. Record for post-test log verification.
4. Receive structured report.

### Guided mode (user augmentation)
**Validate first**: `guided` + `staged`/`unstaged`/`N`/`working-tree` → STOP with combinability error.
1. **Resolve source**: `guided file:<path>` → doc-based | `guided "desc"` → description-based | `guided` alone → `AskUserQuestion` (pick doc or describe).
2. **Spawn Explore agent** with: source content, mode type, `relatedProjects[]`, `testing.contextFiles`, CLAUDE.md paths, `documentation.*` paths. Agent performs: deep feature analysis (keywords, endpoints, models, workflows via Glob/Grep, import tracing) + same feature map/dependency/doc analysis/edge cases as standard. Agent also identifies: DB seed requirements per test, external service setup needs, prerequisite state for each happy-path workflow.
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
Compile from Explore report (do NOT re-read files). Contents: features, endpoints, DB collections/tables, cross-project seed map (related project DB dependencies with collection/table, required fields, connection commands), test flow classifications, related project log commands, external services, edge cases, test history, file reference content, capabilities. Guided mode adds `Mode` + `Source` at top. Cascaded to every Phase 4 agent.

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

**Enter plan mode (/plan).** Plan starts with:

**Step 0 — Context Reload** (for post-approval reconstruction):
- Re-read: SKILL.md, config, `references/templates.md`
- Scope: `$ARGUMENTS`, branch, commit range
- Findings: Phase 2 discoveries (modules, endpoints, dependencies, test flow classifications, related project log commands)
- User context: flaky areas, priorities, notes
- Service Readiness Report from Phase 1 (Phase 3 agents MUST NOT start services or re-check health — service restoration occurs at Phase 4 start)
- If regression mode: fix manifest, 1-hop impact zone, original test IDs, Targeted Regression Context Document
- If guided: type, source, and full guided test list with per-test seed requirements
- If live E2E approved: eligibility list (per-service: name, mode, relevant operations, MCP tools), user approval status
- If guided happy path approved: list of happy-path workflows from Feature Context Document with per-test seed requirements, user instructions, verification queries

**Tool loading gate**: If autonomous mode needs agent-browser/Playwright, list tools and prompt user via AskUserQuestion before plan approval. Declined tools excluded from plan. Guided mode: NEVER include browser automation tools — skip this gate entirely.

**Self-containment mandate** — the plan MUST embed directly (not reference "above" or prior phases):
1. All test suites with full details (name, objective, pre-conditions, steps, expected outcomes, teardown, verification)
2. Feature Context Document (condensed but complete)
3. Service Readiness Report from Phase 1 (used by Phase 4 service restoration agent to re-verify/restart services after context reset)
4. Per-suite agent spawn instructions with resolved values (env, steps, verification, credential role name, DB lifecycle, browser priority chain)
5. Config paths: `documentation.*`, `database.connectionCommand`, `testing.unitTestCommand`, `testDataPrefix`
6. Credential role names from `testCredentials`
7. If guided: per-test DB seed commands, user-facing step-by-step instructions, and verification queries
8. Seed schema discovery mandate (embedded verbatim for Phase 4 agents)
9. If live E2E approved: Live E2E Decision block — per-service: name, mode, relevant `allowedOperations`, applicable MCP tools, `userPromptTemplate` for runtime CLI gate. Embedded verbatim so post-reset orchestrator can prompt and execute.
10. If guided happy path approved: Guided Happy Path Decision block — per-test: name, objective, prerequisites, step-by-step user instructions, DB seed commands, verification queries, expected outcomes.
11. Documentation checklist (always embedded, never conditional) — the post-reset orchestrator needs this to know what files to generate after testing. Include: output directories from config (`documentation.*` paths), template reference path (`references/templates.md`), filename convention (`{timestamp}_{semantic-name}.md`, timestamp from `date -u`), and which doc types this run produces. At minimum: test-results doc. Conditionally: pending-fixes (if failures/findings exist), pending-guided-tests (if guided tests identified or approved), pending-autonomous-tests (if tests queued but not run). Without this embedded checklist, the orchestrator has no way to know about doc generation after context reset — which is why it gets skipped.

- Execution Protocol — autonomous mode (embed verbatim — orchestrator uses this after context reset):
  ```
  SERVICE RESTORATION: Spawn general-purpose subagent (foreground). Re-verify all services from Service Readiness Report using healthCheck from config. Unhealthy → restart via startCommand + poll 5s/30s. Start webhook listeners. STOP if any service unreachable. Returns updated Service Readiness Report.
  SETUP: Spawn general-purpose subagent (foreground). Reads source files, compiles Feature Context Document, returns results.
  FLOW: STRICTLY SEQUENTIAL — one subagent at a time:
    1. For each suite (in order):
       a. Spawn ONE general-purpose subagent (foreground)
       b. Provide in prompt: full context (env, steps, verification, teardown, Feature Context Document, credentials, Service Readiness Report, DB lifecycle, browser priority chain, related project log commands, test flow type)
       c. BLOCK — foreground = automatic blocking
       d. Receive results directly
       e. Record PASS/FAIL
       f. Next suite
  LIVE E2E (conditional): Execute if plan contains liveE2eApproved: true. Follow live E2E execution protocol.
  GUIDED HAPPY PATH (conditional): Execute if plan contains guidedHappyPathApproved: true. Follow guided happy path execution protocol.
  DOCUMENTATION: Follow documentation execution protocol. Generate all applicable doc types from the embedded documentation checklist. This step runs even if all tests passed — the test-results record is needed for regression tracking.
  PROHIBITED: multiple concurrent subagents, parallel execution, main-conversation execution
  AUDIT: agents spawned count, suites executed, cleanup status
  ```

- Execution Protocol — guided mode (embed verbatim):
  ```
  MODE: User augmentation
  NO BROWSER AUTOMATION: agent-browser and Playwright MUST NOT be loaded
  CATEGORIES: Happy-path workflows ONLY
  SERVICE RESTORATION: Spawn general-purpose subagent (foreground). Re-verify all services from Service Readiness Report using healthCheck from config. Unhealthy → restart via startCommand + poll 5s/30s. Start webhook listeners. STOP if any service unreachable. Returns updated Service Readiness Report.
  FLOW: For each guided test (in order):
    1. Spawn ONE general-purpose subagent (foreground) for DB seeding + external service setup
    2. Subagent seeds database, configures services, returns readiness status
    3. Orchestrator presents steps to user via AskUserQuestion
    4. User performs actions on real device/browser
    5. Orchestrator verifies results via DB queries/API/logs
    6. Record PASS/FAIL → next test
  PROHIBITED: agent-browser, Playwright, security/edge-case/validation tests
  ```

- Execution Protocol — live E2E mode (embed verbatim — conditional, only if liveE2eApproved):
  ```
  RUNS AFTER: All autonomous (mocked) suites complete. Live E2E tests real external services in sandbox — running them first would risk polluting the mocked test environment.
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

1. **Happy path** — normal expected flows end-to-end
2. **Invalid inputs & validation** — malformed data, missing fields, wrong types, boundary values
3. **Duplicate/idempotent requests** — rapid same-call repetition, verify no duplicate records/charges/side-effects
4. **Error handling** — trigger every error branch (network failures, invalid states, auth failures, permission denials)
5. **Unexpected DB changes** — orphaned records, missing refs, unintended mutations, index-less slow queries
6. **Race conditions & timing** — concurrent writes, out-of-order webhooks, expired tokens mid-flow
7. **Security** — injection (SQL/NoSQL/command/LDAP/XPath/SSTI/header/log), XSS (stored/reflected/DOM)/CSRF/clickjacking, auth bypass/broken access/privilege escalation/session mgmt/JWT manipulation, data exposure (sensitive responses/stack traces/metadata/timing), input attacks (file uploads: sizes/zip bombs/polyglots/path traversal; payloads: oversized/nested/type confusion/prototype pollution; params: injection/pollution/encoding; headers: host injection/SSRF; volume: rate limiting/ReDoS), infrastructure (SSRF/path traversal/deserialization/known vulns/misconfig/logging), compliance (data minimization/PII/consent/retention). Findings → `### Vulnerabilities` in test-results. Each: risk, exploit scenario, impact, mitigation, priority (data leaks > credentials > escalation > DoS > compliance).
8. **Edge cases from code reading** — test every `if/else`, `try/catch`, guard clause, fallback
9. **Regression** — existing unit tests + re-verify previously broken flows

Each suite: name, objective, pre-conditions, steps + expected outcomes, teardown, verification queries.

**Regression mode scoping**: When the plan receives a Targeted Regression Context Document:
- Suite 1 "Fix Verification" (always): one test per fixed item — re-execute the exact original failure scenario using original test IDs as reference
- Suite 2 "Impact Zone" (conditional): tests for 1-hop callers/callees — only categories where modified code is relevant (e.g., validation fix → Category 2; auth fix → Categories 4, 7; DB fix → Category 5). Skip categories with no code path overlap.
- No other suites — unaffected areas excluded
- State in plan: "Targeted regression re-test — scope limited to fix verification and 1-hop impact zone"
- Execution protocol: unchanged (same subagent sequential flow, just fewer suites)

**Wait for user approval.**

## Phase 4 — Execution (Subagents)

Spawn `general-purpose` subagents sequentially (foreground). Each subagent receives full context in its prompt and returns results directly.

**Service restoration agent** (mandatory, runs FIRST): Spawn one general-purpose subagent (foreground) before any other Phase 4 work. Context reset kills background processes from Phase 1 — services must be re-established. For each service in the embedded Service Readiness Report and config:
1. Run `healthCheck` — if healthy → `verified-post-reset`
2. If unhealthy → run `startCommand` → poll health check 5s/30s → `restarted-post-reset` or `failed-post-reset`
3. Related projects: same check using `relatedProjects[]` healthCheck/startCommand
4. Start webhook listeners from `externalServices[].webhookListener`
5. **Gate**: any `failed-post-reset` → **STOP**, report to user
6. Return updated Service Readiness Report — all subsequent agents use this

**Setup agent** (mandatory): spawn after service restoration (general-purpose subagent, foreground) to read source files, compile Feature Context Document, return results. Proceeds after completion.

**Credential assignment**: Rotate role names from `testCredentials` across suites. Task descriptions include only the **role name** — never values or env var refs. Agents resolve at runtime.

**Cascading context**: Every agent receives full Feature Context Document from Phase 2.

**Capability-aware execution**: Agents leverage detected capabilities from config.

**Browser test enforcement (autonomous mode ONLY)** — priority order (skipping without attempting is PROHIBITED):
1. `agent-browser` (PRIMARY) if available — `open <url>` → `snapshot -i` → `click/fill @ref` → re-snapshot
2. Playwright (FALLBACK) if agent-browser unavailable/errors
3. Direct HTTP/API (LAST RESORT) — mark untestable parts as "guided"

**Guided mode**: No browser automation. User performs all UI interactions. Agents only seed DB, configure services, and verify outcomes.

- `mcp-add` for `safe: true` MCPs relevant to suite. NEVER `safe: false`.
- **External CLI gate**: per `externalServices[]` where `cli.available && !cli.blocked` and plan depends on it → `AskUserQuestion` once per service using `userPromptTemplate`. Declined → "guided". Approved → `cli.approvedThisRun: true`, only `allowedOperations`. NEVER use when `cli.blocked`.

**Anomaly detection** — agents watch for: duplicate records, unexpected DB changes, warning/error logs, slow queries/missing indexes, orphaned references, auth token anomalies, unexpected response fields/status codes.

**Finding verification** (mandatory): Before reporting any finding: (1) identify source code, (2) read to confirm real behavior vs test artifacts, (3) distinguish real vs agent-created, (4) report only confirmed. Unconfirmed → `Severity: Unverified` in `### Unverified` subsection.

**API Response Security Inspection** — analyze ALL responses for:
- *Exposed identifiers*: internal DB IDs, sequential/guessable IDs, sensitive refs (paths, internal URLs)
- *Leaked secrets*: API keys, tokens beyond scope, passwords/hashes, env vars in errors, cloud secrets
- *Personal data* (multi-regulation): PII (names, emails, phones, addresses, govt IDs, DOB), sensitive (health/financial/biometric/racial/political/religious/sexual/genetic), regulations (LGPD, GDPR, CCPA/CPRA, HIPAA, others)

Verify against source: read model/serializer/DTO to confirm field exists in real schema — not test data. False positives MUST NOT be reported. Each finding: Severity, Regulatory impact, Exploitability, Compliance risk → `### API Response Security` subsection.

**Execution flow**:
1. For each suite, prepare prompt including: env details, steps, verification queries, teardown, Feature Context Document, credential **role name**, browser tools/status, Service Readiness Report (updated by service restoration agent), related project log commands, test flow type, DB lifecycle:
   - Pre-test: `migrationCommand` → seed (`autonomous`: create with `testDataPrefix`; `command`: run `seedCommand`)
   - **Seed schema analysis gate** (MANDATORY — before ANY database write): The plan MUST embed the seed schema discovery protocol. Agents must complete schema analysis and report discovered schemas BEFORE executing any insert/seed operation. Proceeding without schema analysis is PROHIBITED.
   - **Seed schema discovery** (mandatory for autonomous seeding — applies to ALL databases in the E2E flow, including related projects): Before inserting into ANY collection/table: (1) query for a real document/row (`findOne`/`SELECT * LIMIT 1` without test prefix filter) to use as schema template, (2) if empty, read the backend service code that creates documents in that collection (look for `insertOne`/`find_one_and_update`/`INSERT`/ORM create calls), (3) mirror the discovered schema exactly — never invent fields or change types (ObjectId vs string, Date vs string, etc.), (4) only add `_testPrefix` marker as extra field, (5) for related project collections: use the connection command from `relatedProjects[]` config or the cross-project seed map in the Feature Context Document. After all seeds (main + related): hit the API read endpoints to verify serialization before proceeding.
   - Verification: `connectionCommand` for queries
   - Post-test: `cleanupCommand` or clean `testDataPrefix` data. Order: migrate → seed → test → cleanup.
   - Browser: include workflow + priority chain. "Do NOT skip browser suites."
2. Strictly sequential:
   ```
   for each suite in approved_suites (in order):
       1. Spawn ONE general-purpose subagent (foreground)
       2. Provide full context in prompt
       3. BLOCK — foreground = automatic blocking
       4. Receive results directly
       5. Record PASS/FAIL
       6. Check related project logs for errors (using log commands from Phase 2, with --since timestamp)
       7. Proceed to next
   ```
   Prohibited: multiple concurrent subagents, parallel execution, main-conversation execution.
3. PASS/FAIL + anomalies after each suite
4. **Live E2E suites (conditional — only if plan contains liveE2eApproved: true)**:
   - Runs after all autonomous suites complete and results are recorded
   - CLI gate: per service, AskUserQuestion using embedded userPromptTemplate. Declined → skip. Approved → cli.approvedThisRun: true.
   - Sandbox re-verification before first CLI call. Production detected → abort for that service.
   - Sequential: one foreground subagent per suite, full context including CLI details and allowed/prohibited operations
   - Record PASS/FAIL, check related project logs
5. **Guided happy-path tests (conditional — only if plan contains guidedHappyPathApproved: true)**:
   - Runs last — after autonomous and live E2E (if any)
   - For each test: seed DB → present steps to user → user acts → verify via DB/API/logs → PASS/FAIL
   - No browser automation. No parallel agents. Category 1 only.
6. **Audit summary**: agents spawned, suites executed, docker exec count, cleanup status

## Phase 5 — Results & Docs

**Objective**: Process results, generate documentation, clean up test data.

**Fix cycle**: Runtime-fixable (env/container/stuck job) → before attempting any fix, verify the issue is real: re-read error output, check if the failure is transient (retry once), confirm root cause in logs/config. Only proceed with a fix after confirming the issue genuinely requires intervention. Spawn general-purpose subagent (foreground) to fix → re-run suite → max 3 cycles. Code bug → document (file, line, expected vs actual) → ask user.

**Documentation**: Spawn general-purpose subagent (foreground). Timestamp via `date -u +"%Y-%m-%d-%H-%M-%S"`. Pattern: `{timestamp}_{semantic-name}.md`. Read `references/templates.md` first. Four doc types: test-results (always generated — the record is essential for regression tracking even when all tests pass), pending-fixes (bugs/infra issues), pending-guided-tests (browser/visual/physical + guided happy-path tests if approved), pending-autonomous-tests (identified but not run). Re-runs → append "Re-run" section. If live E2E or guided happy-path tests were executed, include their results in the test-results doc under dedicated suite sections. The documentation subagent receives all test results (autonomous + live E2E + guided) and generates unified output.

**Cleanup**: Spawn general-purpose subagent (foreground). Remove `testDataPrefix` data only. Never touch pre-existing. Log actions. Verify with DB query.

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
| Strictly sequential | One agent at a time in Phases 4-5. Spawn → complete → shut down → next |
| Explore agents read-only | No file edits or state-modifying commands |
| UTC timestamps | Via `date -u` only, never guess |
| No unsafe MCPs | Never activate `safe: false` MCPs |
| External CLI gating | Blocked when `cli.blocked`. Per-run user confirmation. `allowedOperations` only. `prohibitedFlags`/`prohibitedOperations` always blocked |
| No dynamic commands | Only execute verbatim config commands — no generation/concatenation/interpolation |
| Finding verification | Verify against source code before reporting any finding |
| Idempotent test data | Prefix with `testDataPrefix`. Skip or reset if exists |
| Seed schema discovery | Before seeding any DB (main or related project): query real doc or read service code for schema. Mirror exactly — never invent fields or change types. Verify via API after seeding |
| External API care | Delays between calls, sandbox modes, minimize requests |
| `_autonomous/` reading | Summary + Issues Found sections only |
| Capabilities auto-detected | Never ask user to configure manually |
| Guided = user augmentation | No browser automation in guided mode — user performs all actions |
| Guided = happy path only | Category 1 only in guided mode — categories 2-9 autonomous-only |
| Tool loading gate | Browser tools need pre-plan approval in autonomous mode, never in guided |
| Plan self-containment | All context embedded in plan for post-reset survival — no "see above" references |
| Live E2E = sandbox only | Live E2E suites require sandbox/test mode. Re-verified at runtime before CLI calls |
| Live E2E = post-autonomous | Live E2E runs after all autonomous (mocked) suites complete |
| Guided happy path = post-all | Guided happy-path runs last — after autonomous and live E2E |
| Post-discovery prompts | Standard mode only — skipped when `guided` arg or regression mode active |
| Documentation in every run | Test-results doc generated for every run. Embedded in plan execution protocol so it survives context reset |

## Operational Bounds

| Bound | Constraint |
|---|---|
| Max agents | Approved test suites + one service restoration agent + one setup agent |
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
| Data access | Outside project: `~/.claude/settings.json` (RO), `~/.claude/trusted-configs/` (RW, one hash), `~/.claude/CLAUDE.md` (RO). `.env` scanned for patterns only — values never stored/logged |
| Trust boundaries | Config SHA-256 verified out-of-repo. Untrusted inputs → analysis only → plan → user approval. No interpolation into commands |
| Live E2E scope | Eligible services only (cli.available && !cli.blocked && feature-relevant). allowedOperations only. Runtime sandbox re-verification |
| Guided happy path scope | Category 1 only. No browser automation. Sequential. Runs last |
| Post-discovery prompts | Standard mode only — skipped for `guided` arg or regression mode |
| Documentation output | Minimum 1 doc (test-results) per run. Embedded in execution protocol for post-reset survival |
