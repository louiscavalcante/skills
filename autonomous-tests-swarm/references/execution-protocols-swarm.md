# Execution Protocols — Swarm

Reference protocols for swarm (parallel) test execution. Embedded verbatim in plans via the self-containment mandate — the post-reset orchestrator uses these blocks without needing this file.

Key difference from sequential skill: integration suites run in PARALLEL with isolated Docker stacks. E2E and guided suites remain SEQUENTIAL.

---

## Phase Orchestration Protocol

Master execution block embedded verbatim in plans. The post-reset orchestrator follows this step-by-step.

```
POST-RESET STARTUP:
  1. Re-read: SKILL.md, config, plan text
  2. Create ALL phase tasks via TaskCreate (see Task Tracking Block in plan)
  3. Chain task dependencies sequentially
  4. Begin Phase 4.1

PHASE 4.1 — SERVICE RESTORATION:
  TaskUpdate(phase_4_1, status: "in_progress")
  Agent(
    subagent_type: "general-purpose",
    prompt: "You are the Service Restoration agent. Context reset killed background processes.
      Services to restore: [Service Readiness Report from plan]
      For each service: run healthCheck -> if healthy: verified-post-reset -> if unhealthy: startCommand + poll 5s/30s.
      Related projects: same check via relatedProjects[].
      Start webhook listeners.
      Re-start log captures per log-monitoring-protocol for all services with logCommand.
      Recreate per-agent directories at /tmp/autonomous-swarm-{sessionId}/agent-{N}/logs/
      GATE: any failed-post-reset -> report STOP with service name and error.
      REPORT BACK: Updated Service Readiness Report with new log file paths and PIDs."
  )
  If STOP -> TaskUpdate with reason, halt. Else -> TaskUpdate(phase_4_1, status: "completed")

PHASE 4.2 — SETUP:
  TaskUpdate(phase_4_2, status: "in_progress")
  Agent(
    subagent_type: "general-purpose",
    prompt: "You are the Setup agent.
      Read source files: [file list from plan].
      Compile Feature Context Documents from plan findings.
      Read CLAUDE.md files: [list from plan].
      Generate per-agent specs: swarm-{N}, remapped ports, compose paths. Freeze capabilities snapshot.
      REPORT BACK: Compiled Feature Context Documents, per-agent specs, frozen capabilities snapshot, architecture notes, any corrections to plan assumptions."
  )
  TaskUpdate(phase_4_2, status: "completed")

PHASE 4.3 — INTEGRATION SUITES (PARALLEL — up to maxAgents concurrent):
  TaskUpdate(phase_4_3, status: "in_progress")
  Spawn ALL integration suite agents simultaneously (run_in_background: true):
  For each integration suite [N] in plan:
    Agent(
      subagent_type: "general-purpose",
      run_in_background: true,
      prompt: "You are Integration Suite [N] agent (swarm-[N]).
        Suite: [suite name and objective from plan]
        Pre-generated spec: swarm-[N], ports [port range], compose path [path]
        Frozen capabilities snapshot: [from setup agent]
        Feature Context: [condensed Feature Context Document with remapped curl commands]
        Service Readiness: [updated Service Readiness Report]
        Credential role: [assigned role name]
        Curl commands: [explicit curl commands with remapped ports]
        Security checklist items: [YES/PARTIAL items for this suite]
        Seeding instructions: [table, fields, values, commands from plan]
        Seed schema discovery mandate: [verbatim from plan]
        Per-agent log paths: /tmp/autonomous-swarm-{sessionId}/agent-[N]/logs/
        DB consistency protocol: [verbatim from plan]
        Tool Inventory: [relevant subset]
        EXECUTION (swarm-agent-tasks.md lifecycle a-l):
          Verify compose -> start stack -> health check (60s, 2 attempts) -> init commands ->
          capture dbBaseline -> seed (schema discovery first) -> POST_SEED -> execute curls + security checks ->
          POST_TEST -> cleanup -> POST_CLEANUP -> teardown (docker compose down -v --remove-orphans)
        REPORT BACK: PASS/FAIL per test, security observations, log findings, DB consistency results, anomalies, teardown status."
    )
  Wait for ALL parallel agents to complete (notified on completion).
  Failure redistribution: failed agent's suites -> spawn replacement background subagent.
  Audit merge: merge all parallel agent results per Audit Merge Protocol.
  TaskUpdate(phase_4_3, status: "completed")

PHASE 4.4 — E2E SUITES (sequential, one at a time) — skip if frontendType == api-only:
  TaskUpdate(phase_4_4, status: "in_progress")
  Runs against shared local stack (NOT swarm-isolated).
  For each E2E suite [N] in plan:
    Agent(
      subagent_type: "general-purpose",
      prompt: "You are E2E Suite [N] agent.
        Suite: [suite name and objective]
        Journey steps: [from plan]
        Browser tools: agent-browser (PRIMARY) -> Playwright (FALLBACK) -> Direct HTTP (LAST RESORT)
        Chrome DevTools: [protocol if chromeDevtools: true]
        Service Readiness: [report]
        Feature Context: [document]
        Log file paths: [paths]
        Credential role: [assigned role name]
        Tool Inventory: [browser + DB + service MCPs]
        WEBAPP: Navigate -> snapshot -i -> execute journey -> re-snapshot + devtools -> verify backend via curl -> verify DB
        MOBILE: Present guided steps via AskUserQuestion -> user acts -> verify
        REPORT BACK: PASS/FAIL per step, screenshots, network/console findings, backend verification, logs."
    )
  TaskUpdate(phase_4_4, status: "completed")

PHASE 4.5 — REGRESSION:
  TaskUpdate(phase_4_5, status: "in_progress")
  Agent(
    subagent_type: "general-purpose",
    prompt: "You are the Regression agent.
      Command: [testing.unitTestCommand from config]
      Run the command. Capture stdout/stderr. Parse: total/passed/failed/skipped.
      REPORT BACK: Total | Passed | Failed (with names) | Skipped | Overall PASS/FAIL."
  )
  TaskUpdate(phase_4_5, status: "completed")

PHASE 4.6 — GUIDED HAPPY-PATH (optional, skip if not approved — RUNS IN MAIN CONVERSATION):
  TaskUpdate(phase_4_6, status: "in_progress")
  Swarm isolation NOT used — shared local stack.
  For each happy-path scenario [M] in plan:
    TaskUpdate(phase_4_6_M, status: "in_progress")
    Seed: Agent(
      subagent_type: "general-purpose",
      prompt: "Seed DB for guided scenario [M]: [scenario name].
        Seed commands: [from plan]. Run schema discovery first.
        Set up prerequisites: [prerequisite state from plan].
        REPORT BACK: Seed confirmation, baseline DB state snapshot."
    )
    Record step_start_timestamp = current time
    For each step [S] in scenario [M]:
      AskUserQuestion(
        question: "## Guided Test: [scenario] — Step [S]\n\n**Setup**: [summary]\n\n**Action**:\n[step instructions]\n\n**Expected**: [expected result]",
        options: ["Done - ready to verify", "Skip this step", "Issue encountered"]
      )
      If "Done": Agent(
        subagent_type: "general-purpose",
        prompt: "Verify step [S] of guided scenario [M].
          Step description: [what the user just did]
          Expected result: [expected DB/API state]
          Log file paths: [paths from Service Readiness Report]
          Check logs since [step_start_timestamp]: grep ERROR/WARN
          DB verification queries: [from plan]
          API verification calls: [from plan]
          REPORT BACK: PASS/FAIL + log findings + DB state analysis (before vs after)."
      )
      Record step_start_timestamp = current time (for next step)
      If "Skip": record SKIPPED
      If "Issue encountered": record user description
    TaskUpdate(phase_4_6_M, status: "completed")
  TaskUpdate(phase_4_6, status: "completed")

PHASE 5 — RESULTS & DOCS:
  TaskUpdate(phase_5, status: "in_progress")
  Audit merge (if not done in Phase 4.3): merge all parallel agent results.
  Fix cycles (max 3 per suite): spawn fix subagent -> re-run suite
  Documentation: Agent(subagent_type: "general-purpose", prompt: "Generate docs per templates.md. Timestamp, all results including guided scenario outcomes, log analysis, DB consistency. Append Execution Audit section if audit enabled.")
  Docker cleanup verification: Agent(subagent_type: "general-purpose", prompt: "Verify no lingering swarm containers, networks, volumes. Clean orphans. Remove /tmp/autonomous-swarm-{sessionId}/.")
  Cleanup: Agent(subagent_type: "general-purpose", prompt: "Remove testDataPrefix data. Kill log captures. Verify.")
  DB consistency final check: POST_CLEANUP
  TaskUpdate(phase_5, status: "completed")

PROHIBITED: Orchestrator executing operational work directly. Every action uses Agent() EXCEPT guided happy-path step presentation (AskUserQuestion in main conversation).
```

---

## Integration Execution Protocol (Parallel)

```
SPAWNING: Background, parallel — up to maxAgents concurrent subagents.
ISOLATION: Each agent gets its own Docker stack (remapped ports, namespaced containers, isolated DB).
PER-AGENT PATHS:
  - Dir: /tmp/autonomous-swarm-{sessionId}/agent-{N}/
  - Logs: /tmp/autonomous-swarm-{sessionId}/agent-{N}/logs/
  - Compose: /tmp/autonomous-swarm-{sessionId}/agent-{N}/docker-compose.yml
FLOW:
  1. Set Docker context, confirm port ranges
  2. Spawn ALL integration suite subagents (run_in_background: true)
  3. Each receives: pre-generated spec (swarm-{N}, ports, compose path), frozen capabilities,
     Feature Context Document, curl commands (remapped ports), security checklist subset,
     seeding instructions, seed schema discovery mandate, per-agent log paths,
     DB consistency protocol, credential role name, Tool Inventory subset
  4. All execute in parallel — orchestrator notified on completion
  5. Failure redistribution: failed agent's suites → spawn replacement background subagent
AGENT EXECUTION (see swarm-agent-tasks.md for full a-l lifecycle):
  Verify compose → start stack → health check (60s, 2 attempts) → init commands →
  capture dbBaseline → seed (after schema discovery) → POST_SEED → execute curls →
  POST_TEST → cleanup → POST_CLEANUP → teardown (docker compose down -v --remove-orphans)
REPORTS: PASS/FAIL per test, security observations, log findings, DB consistency, anomalies, teardown status
RULES: Never modify original compose/env, never bind used ports, max 2 compose attempts,
  never init against shared stack, Docker labels: com.autonomous-swarm.managed/session/agent
```

---

## E2E Execution Protocol (Sequential)

```
SPAWNING: Foreground, sequential — browser automation cannot parallelize.
DOES NOT USE swarm Docker isolation — runs against the shared local stack.
BROWSER TOOLS (skipping without attempting PROHIBITED):
  1. agent-browser (PRIMARY) — open → snapshot -i → click/fill @ref → re-snapshot
  2. Playwright (FALLBACK) — if agent-browser unavailable/errors
  3. Direct HTTP/API (LAST RESORT) — mark untestable parts as "guided"
CHROME-DEVTOOLS (when chromeDevtools is true):
  Baseline network before navigation → check after each action → capture console errors → report
FLOW: For each E2E suite:
  1. Spawn ONE subagent (foreground) with journey steps, browser config, chrome-devtools protocol,
     log paths, Service Readiness Report, Feature Context Document
  2. BLOCK → receive results → Record PASS/FAIL → next suite
REPORTS: PASS/FAIL per step, screenshots, network/console findings, backend verification, logs
```

---

## Guided Execution Protocol

```
MODE: User augmentation. NO BROWSER AUTOMATION (agent-browser/Playwright MUST NOT load).
CATEGORIES: Happy-path only (category 1). Categories 2-9 autonomous-only.
SWARM ISOLATION NOT USED — shared local stack.
RUNS IN: Main conversation — orchestrator drives. NOT delegated to a single subagent.
EACH SCENARIO: Gets its own task (Phase 4.6.{M}).

FLOW: For each happy-path scenario:
  1. TaskUpdate(scenario_task, status: "in_progress")
  2. Spawn ONE subagent (foreground) for DB seeding + prerequisite setup → returns readiness
  3. PER-STEP LOOP (for each step in the scenario):
     a. Orchestrator presents step via AskUserQuestion (MANDATORY — text output PROHIBITED):
        Question: "## Guided Test: {scenario} — Step {S}\n\n**Setup**: {summary}\n\n**Action**:\n{step instructions}\n\n**What to verify**: {expected result}"
        Options: ["Done - ready to verify", "Skip this step", "Issue encountered"]
     b. If "Done": spawn verification subagent (foreground):
        - Check service logs since step start timestamp (grep ERROR/WARN)
        - Run DB queries to verify expected state changes
        - Run API calls to confirm expected responses
        - Report: PASS/FAIL + log findings + DB state before/after
     c. If FAIL: record finding with details, continue to next step
     d. If "Skip": record SKIPPED, continue
     e. If "Issue encountered": record user description, continue
  4. TaskUpdate(scenario_task, status: "completed")
  5. Next scenario

PROHIBITED: agent-browser, Playwright, parallel subagents, security/edge-case/validation tests
WHY MAIN CONVERSATION: Orchestrator must interact with user between steps and spawn verification
  subagents with step-specific log timestamps and DB queries. A single delegated subagent cannot
  interleave AskUserQuestion with per-step log/DB analysis reliably.
```

---

## Documentation Protocol

```
RUNS AFTER: All test phases (parallel integration + sequential E2E + guided) complete.
GENERATE: test-results (always), pending-fixes (if failures), pending-guided-tests (if identified), pending-autonomous-tests (if queued)
HOW:
  1. Spawn subagent (foreground), read references/templates.md
  2. Timestamp: date -u +"%Y-%m-%d-%H-%M-%S", filename: {timestamp}_{semantic-name}.md
  3. Write to documentation checklist dirs, include ALL results + log analysis + DB consistency
SWARM-SPECIFIC: When audit enabled → append "Execution Audit" section (agent count, durations, limits, cleanup). Only orchestrator copies audit-summary.json to docs output dir.
ALWAYS RUNS: Even on all-pass.
```

---

## Audit Merge Protocol

```
RUNS AFTER: All parallel agents complete, before documentation.
FLOW:
  1. Collect PASS/FAIL from all background subagents
  2. Merge per-agent: findings, security observations, DB consistency, log findings
  3. When audit enabled: merge agent-{N}.json → audit-summary.json
     (schemaVersion "1.0", metadata, per-agent details, totals, cleanup verification)
CONFLICTS: Duplicate findings → keep highest severity. Contradictory results → report both, flag.
```

---

## Docker Cleanup Verification

```
RUNS AFTER: All agents complete + audit merge.
SPAWN: Foreground subagent.
CHECKS:
  1. docker ps -a --filter name=swarm- -q → empty
  2. docker ps -a --filter label=com.autonomous-swarm.session={sessionId} -q → empty
  3. docker network ls --filter label=...session={sessionId} -q → empty
  4. docker volume ls --filter label=...session={sessionId} -q → empty
  5. Clean orphans if any remain
  6. rm -rf /tmp/autonomous-swarm-{sessionId}
FAILURE: Report lingering resources. Never leave orphaned containers.
```

---

## Regression Protocol

```
RUNS AFTER: All integration and E2E suites (LAST testing step). Runs against shared local stack.
PURPOSE: Execute existing unit tests via testing.unitTestCommand.
EXECUTION: Single invocation → capture stdout/stderr → parse total/passed/failed/skipped → report
SCOPE: Run ONCE. Never interleaved. Never repeated unless fix cycle applies.
```
