# Execution Protocols — Swarm

Reference protocols for swarm (parallel) test execution. Embedded verbatim in plans via the self-containment mandate — the post-reset orchestrator uses these blocks without needing this file.

Key difference from sequential skill: integration suites run in PARALLEL with isolated Docker stacks. E2E and guided suites remain SEQUENTIAL.

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
MODE: User augmentation. NO BROWSER AUTOMATION. NO PARALLEL SUBAGENTS (overrides parallel protocol).
CATEGORIES: Happy-path only (category 1). SWARM ISOLATION NOT USED — shared local stack.
FLOW: For each guided test:
  1. Spawn ONE subagent (foreground) for DB seeding + service setup → returns readiness
  2. Present steps via AskUserQuestion (MANDATORY — text output PROHIBITED):
     Options: ["Done - ready to verify", "Skip this test", "Issue encountered"]
  3. User acts → spawn verification subagent → Record PASS/FAIL
PROHIBITED: agent-browser, Playwright, parallel subagents, security/edge-case/validation tests
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
