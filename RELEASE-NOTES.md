# Release Notes

## v1.0.0 (2026-03-02)

Initial public release of autonomous-tests.

### Added
- 8-phase execution pipeline (config → safety → services → discovery → plan → execute → fix → docs → cleanup)
- Config schema v4 with capabilities detection (Docker MCPs, agent-browser, Playwright, Stripe CLI)
- Smart doc analysis via `file:<path>` argument
- Test history scanning from `_autonomous/` folders
- Config trust store with SHA-256 hashing (`~/.claude/trusted-configs/`)
- Credential safety: env var references only, redacted display, per-agent isolation
- Production safety: auto-abort on live key detection
- Four structured output types: test-results, pending-fixes, pending-guided-tests, pending-autonomous-tests
- Cross-project dependency tracing
- setup-hook.sh installer for ExitPlanMode hook, Agent Teams flag, Opus model
- agent-browser prioritized over Playwright for web/frontend testing
