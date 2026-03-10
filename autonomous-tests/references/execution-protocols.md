# Execution Protocols

Reference protocols for test execution. Embedded verbatim in plans via the self-containment mandate — the post-reset orchestrator uses these blocks to spawn and manage subagents without needing this file.

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
FLOW: For each guided test:
  1. Spawn ONE subagent (foreground) for DB seeding + service setup → returns readiness
  2. Present steps via AskUserQuestion (MANDATORY — text output PROHIBITED):
     Question: "## Guided Test: {name}\n\n**Setup complete**: {summary}\n\n**Steps**:\n1. ...\n\n**What to verify**: {expected}"
     Options: ["Done - ready to verify", "Skip this test", "Issue encountered"]
  3. User performs actions → spawn verification subagent → Record PASS/FAIL
PROHIBITED: agent-browser, Playwright, security/edge-case/validation tests, parallel subagents
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
