# Chrome DevTools Protocol

Reference protocol for chrome-devtools-mcp integration during E2E testing. Provides network/console observation complementary to agent-browser interaction.

---

## Detection

During Phase 0 capabilities scan:

1. Run `mcp-find` — check output for `chrome-devtools`
2. Scan `~/.claude.json` for `mcpServers` containing `chrome-devtools`
3. Scan `~/.claude/settings.json` for `mcpServers` containing `chrome-devtools`

Store result in config:

```json
"capabilities": {
  "frontendTesting": {
    "agentBrowser": true,
    "playwright": false,
    "chromeDevtools": true
  }
}
```

---

## Relationship to agent-browser

These tools are **complementary**, not alternatives:

- **agent-browser** = Interaction — navigate, click, fill, snapshot
- **chrome-devtools-mcp** = Observation — monitor network, console, capture evidence

Both can be active simultaneously during E2E suites. agent-browser drives the user flow while chrome-devtools observes what happens under the hood.

---

## E2E Observation Protocol

### Before Navigation

- `list_network_requests` — capture baseline of existing requests
- `list_console_messages` — capture baseline console state

### After Each Action

- `list_network_requests` — observe:
  - API calls triggered by the action
  - HTTP status codes (watch for unexpected 4xx/5xx)
  - Response times (flag >2s as performance observation)
  - Request/response payloads (watch for sensitive data)
- `list_console_messages` — observe:
  - JavaScript errors (any `error` level)
  - Warnings that indicate issues
  - Failed resource loads

### After Suite Completion

- `take_screenshot` — optional, for documentation purposes
- Compile observations into finding format

---

## Finding Generation

Observations from chrome-devtools produce findings when anomalies are detected:

| Observation | Severity | Finding Type |
|-------------|----------|-------------|
| JavaScript error in console | Medium | Frontend Error |
| Failed network request (non-test) | Correlate | Cross-reference with backend logs |
| Slow response (>2s) | Low | Performance Observation |
| Sensitive data in network payload | High | API Response Security |
| CORS errors | Medium | Security Misconfiguration |
| Mixed content warnings | Medium | Data Protection |

### Correlation Rules

- Failed network requests → check backend logs for corresponding error → report as correlated finding
- JS errors → check if reproducible across actions → transient errors are Low, persistent are Medium
- Slow responses → check if backend or network → report with timing data

---

## Graceful Degradation

If chrome-devtools-mcp is **unavailable**:

- E2E tests still work via agent-browser alone
- Network observation falls back to backend log inspection
- Console monitoring is skipped — rely on visual/functional verification
- No blocking — tests proceed without devtools observation
- Note in test results: "Chrome DevTools observation unavailable — backend-only verification"
