# Execution Protocols

Reference protocols for test execution. Embedded verbatim in plans via the self-containment mandate — the post-reset orchestrator uses these blocks to spawn and manage subagents without needing this file.

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
      REPORT BACK: Compiled Feature Context Documents, architecture notes, any corrections to plan assumptions."
  )
  TaskUpdate(phase_4_2, status: "completed")

PHASE 4.3 — INTEGRATION SUITES (sequential, one at a time):
  TaskUpdate(phase_4_3, status: "in_progress")
  For each integration suite [N] in plan (in order):
    Agent(
      subagent_type: "general-purpose",
      prompt: "You are Integration Suite [N] agent.
        Suite: [suite name and objective from plan]
        Feature Context: [condensed Feature Context Document]
        Service Readiness: [updated Service Readiness Report]
        Credential role: [assigned role name]
        Curl commands: [explicit curl commands from plan]
        Security checklist items: [YES/PARTIAL items for this suite]
        Seeding instructions: [table, fields, values, commands from plan]
        Seed schema discovery mandate: [verbatim from plan]
        Log file paths: [from Service Readiness Report]
        DB consistency protocol: [verbatim from plan]
        Tool Inventory: [relevant subset]
        EXECUTION: migrate -> dbBaseline -> seed (schema discovery first) -> POST_SEED -> execute curls + security checks -> POST_TEST -> cleanup -> POST_CLEANUP
        REPORT BACK: PASS/FAIL per test, security observations, log findings, DB consistency results, anomalies."
    )
    After report: check service logs (grep ERROR/WARN --since timestamp). Run DB consistency checks.
  TaskUpdate(phase_4_3, status: "completed")

PHASE 4.4 — E2E SUITES (sequential, one at a time) — skip if frontendType == api-only:
  TaskUpdate(phase_4_4, status: "in_progress")
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
  Fix cycles (max 3 per suite): spawn fix subagent -> re-run suite
  Documentation: Agent(subagent_type: "general-purpose", prompt: "Generate docs per templates.md. Timestamp, all results including guided scenario outcomes, log analysis, DB consistency.")
  Cleanup: Agent(subagent_type: "general-purpose", prompt: "Remove testDataPrefix data. Kill log captures. Remove /tmp/test-logs-{sessionId}/. Verify.")
  DB consistency final check: POST_CLEANUP
  TaskUpdate(phase_5, status: "completed")

PROHIBITED: Orchestrator executing operational work directly. Every action uses Agent() EXCEPT guided happy-path step presentation (AskUserQuestion in main conversation).
```

---

## Integration Execution Protocol

```
SPAWNING: Foreground, sequential — one general-purpose subagent at a time.
FLOW: For each integration suite (in order):
  1. Spawn ONE subagent (foreground) with full context
  2. BLOCK — receive results directly
  3. Record PASS/FAIL, check service logs (grep ERROR/WARN --since timestamp)
  4. Proceed to next suite
AGENT CONTEXT:
  - Feature Context Document, Service Readiness Report, credential role name
  - Explicit curl commands (never batch scripts), security checklist subset (YES/PARTIAL only)
  - Seeding instructions (table, fields, values), seed schema discovery mandate
  - Log file paths, DB consistency protocol, Tool Inventory subset
AGENT EXECUTION: migrate → capture dbBaseline → seed (after schema discovery) → POST_SEED check → execute curls + security checks → POST_TEST check → cleanup → POST_CLEANUP check
REPORTS: PASS/FAIL per test, security observations, log findings, DB consistency, anomalies
RULES: No batch scripts, no guessing schemas, schema discovery mandatory, finding verification mandatory
PROHIBITED: concurrent subagents, parallel execution, main-conversation execution
```

---

## E2E Execution Protocol

```
SPAWNING: Foreground, sequential — one general-purpose subagent at a time.
BROWSER TOOLS (skipping without attempting is PROHIBITED):
  1. agent-browser (PRIMARY) — open → snapshot -i → click/fill @ref → re-snapshot
  2. Playwright (FALLBACK) — if agent-browser unavailable/errors
  3. Direct HTTP/API (LAST RESORT) — mark untestable parts as "guided"
CHROME-DEVTOOLS (when chromeDevtools is true):
  Baseline network before navigation → check after each action → capture console errors → report
FLOW: For each E2E suite (in order):
  1. Spawn ONE subagent (foreground) with full context
  2. BLOCK — receive results directly
  3. Record PASS/FAIL, check service logs, proceed to next
AGENT CONTEXT:
  - User journey steps, browser tool config, chrome-devtools protocol (if enabled)
  - Log file paths, Service Readiness Report, Feature Context Document
  - Credential role name, Tool Inventory subset (browser + DB + service MCPs)
WEBAPP: Navigate → snapshot → execute journey (click/fill/submit) → re-snapshot + devtools check → verify backend via curl → verify DB
MOBILE: Present guided steps via AskUserQuestion → user acts → verify backend via curl/DB/logs
REPORTS: PASS/FAIL per step, screenshots, network/console findings, backend verification, logs
PROHIBITED: concurrent subagents, parallel execution
```

---

## Guided Execution Protocol

```
MODE: User augmentation. NO BROWSER AUTOMATION (agent-browser/Playwright MUST NOT load).
CATEGORIES: Happy-path only (category 1). Categories 2-9 autonomous-only.
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
RUNS AFTER: All test phases (integration + E2E + guided) complete.
WHY: After context reset, Phase 5 instructions are lost. This block ensures doc generation.
GENERATE:
  - test-results (always), pending-fixes (if failures), pending-guided-tests (if guided identified), pending-autonomous-tests (if tests queued but not run)
HOW:
  1. Spawn subagent (foreground), read references/templates.md
  2. Timestamp: date -u +"%Y-%m-%d-%H-%M-%S", filename: {timestamp}_{semantic-name}.md
  3. Write to directories from documentation checklist in plan
  4. Include ALL results (integration + E2E + guided), service log analysis, DB consistency (if WARN/FAIL)
ALWAYS RUNS: Even on all-pass — test-results needed for regression tracking.
```

---

## Regression Protocol

```
RUNS AFTER: All integration and E2E suites complete (LAST testing step).
PURPOSE: Execute existing unit tests via testing.unitTestCommand.
EXECUTION: Single invocation → capture stdout/stderr → parse total/passed/failed/skipped → report
REPORT: Total | Passed | Failed (with names) | Skipped | Overall PASS/FAIL
SCOPE: Run ONCE. Never interleaved. Never repeated unless fix cycle applies.
```
