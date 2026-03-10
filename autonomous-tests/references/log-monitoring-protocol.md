# Log Monitoring Protocol

Reference protocol for capturing and monitoring service logs during test execution. Embedded verbatim in plans via the self-containment mandate — agents configure and check logs without needing this file post-reset.

---

## Setup (During Environment Phase)

1. Create log directory: `/tmp/test-logs-{sessionId}/`
2. For each service, start log capture based on service type:

**Docker services**:
```bash
docker logs -f {container} > /tmp/test-logs-{sessionId}/{service-name}.log 2>&1 &
echo $!  # Record PID
```

**npm-dev / process services**:
```bash
# Redirect stdout/stderr from running process to log file
# If service started by skill: redirect at start time
# If service already running: use docker logs or tail existing log file
```

3. Record all capture PIDs and log file paths for later cleanup
4. Return log file paths to orchestrator for distribution to suite agents

---

## Usage During Execution

Each suite agent receives log paths in its prompt:

```
LOG MONITORING:
  Service logs:
    - {service-name}: /tmp/test-logs-{sessionId}/{service-name}.log
    - {service-name}: /tmp/test-logs-{sessionId}/{service-name}.log
  Check after suite: grep -i "ERROR\|WARN\|Exception\|Traceback" {log-path}
  Correlate: match timestamps of errors with test execution times
```

### Per-Suite Agent Responsibilities

1. Note the start timestamp before test execution
2. Execute test suite
3. After suite completion, check logs for ERROR/WARN entries since start timestamp
4. Correlate log errors with test failures — matching errors strengthen findings
5. Report uncorrelated errors as anomalies (unexpected errors not triggered by tests)

---

## Orchestrator Log Check

Between suites, the orchestrator checks logs for cross-suite errors:

1. Read log files for ERROR entries since last check
2. Errors that span multiple suites may indicate systemic issues
3. Persistent errors across suites → escalate severity
4. New errors appearing mid-run → note for investigation

---

## Cleanup

After all testing and documentation completes:

1. Kill all log capture PIDs: `kill {pid1} {pid2} ...`
2. Remove log directory: `rm -rf /tmp/test-logs-{sessionId}/`
3. Verify cleanup: `ls /tmp/test-logs-{sessionId}/ 2>/dev/null && echo "CLEANUP FAILED" || echo "CLEANUP OK"`

---

## Swarm Variant

For `autonomous-tests-swarm` (parallel execution), logs are isolated per agent:

- Base directory: `/tmp/autonomous-swarm-{sessionId}/`
- Per-agent logs: `/tmp/autonomous-swarm-{sessionId}/agent-{N}/logs/`
- Each agent captures its own service logs independently
- Orchestrator consolidates findings from all agent log directories after completion
- Cleanup removes the entire swarm directory: `rm -rf /tmp/autonomous-swarm-{sessionId}/`
