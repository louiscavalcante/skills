# autonomous-tests-swarm

Autonomous E2E test runner with **per-agent Docker isolation** for Claude Code.

Each test agent spins up its own fully isolated Docker environment — database, API, and related services — on unique ports. Agents run migrations, seed their own test data, execute test suites, and tear down independently. No shared state, no credential conflicts, true parallel testing.

## Table of Contents

- [Token Usage](#token-usage)
- [How It Differs from autonomous-tests](#how-it-differs-from-autonomous-tests)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Configuration](#configuration)
- [Output](#output)
- [How It Works](#how-it-works)
- [Troubleshooting](#troubleshooting)
- [Project Structure](#project-structure)

## Token Usage

> **Note:** This skill is **token-intensive by design**. It uses **Claude Opus 4.6** for both the orchestrator and every spawned agent. Each agent also starts its own Docker environment, so resource consumption scales with the number of parallel agents. The tradeoff is true isolation — no credential conflicts, no shared state, no flaky parallel failures.

## How It Differs from autonomous-tests

| Feature | autonomous-tests | autonomous-tests-swarm |
|---|---|---|
| **Environment** | Shared local stack | Per-agent isolated Docker stacks |
| **Credentials** | Shared (token-based ‖, session-based →) | Not needed — each agent seeds own data |
| **Parallelism** | Limited by credential type | Always fully parallel |
| **Port management** | Uses existing ports | Auto-assigns unique port ranges |
| **Docker overhead** | None (uses running stack) | N copies of the stack (one per agent) |
| **Cleanup** | Test data only | Full Docker teardown + test data |
| **Best for** | Projects with established test users | Projects where spinning up fresh environments is preferred |

Use `autonomous-tests` when you have pre-existing test credentials and a running local stack. Use `autonomous-tests-swarm` when you want complete isolation and can afford the Docker overhead.

[Back to top](#autonomous-tests-swarm)

## Prerequisites

| Requirement | Purpose | Check |
|---|---|---|
| Claude Code CLI | Runtime | `claude --version` |
| python3 | Config hashing, validation | `python3 --version` |
| Docker + Compose | Per-agent environment isolation | `docker --version && docker compose version` |
| git | Diff analysis | `git --version` |
| Agent Teams flag | Parallel agent coordination | Setup script handles this |
| Sufficient disk space | N copies of Docker images/volumes | `docker system df` |

## Installation

### Quick Install

```bash
npx skills add louiscavalcante/skills --skill autonomous-tests-swarm
```

Then run the setup script to configure required settings:

```bash
bash ~/.claude/skills/louiscavalcante-skills/autonomous-tests-swarm/scripts/setup-hook.sh
```

The setup script configures four things in `~/.claude/settings.json`:
1. **ExitPlanMode hook** — forces plan approval even in `dontAsk` mode
2. **AskUserQuestion hook** — forces user prompts even in `dontAsk`/bypass mode
3. **Agent Teams flag** — enables `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` for parallel execution
4. **Model** — sets `claude-opus-4-6` as the default model

### Manual Install

If you prefer not to use [skills.sh](https://skills.sh/):

1. Clone the repo and copy the `autonomous-tests-swarm/` directory into your Claude Code skills directory
2. Enable Agent Teams and set the model — add to `~/.claude/settings.json`:
   ```json
   {
     "env": {
       "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
     },
     "model": "claude-opus-4-6"
   }
   ```
3. (Optional) Add the global hooks — add to `~/.claude/settings.json` under `hooks.PreToolUse`:
   ```json
   [
     {
       "matcher": "ExitPlanMode",
       "hooks": [{
         "type": "command",
         "command": "echo '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\"}}'"
       }]
     },
     {
       "matcher": "AskUserQuestion",
       "hooks": [{
         "type": "command",
         "command": "echo '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\"}}'"
       }]
     }
   ]
   ```
   The skill already includes these as skill-scoped hooks, so the global version is optional.

### Verify Installation

Run `/autonomous-tests-swarm` in any project with code changes. The skill will walk you through first-run configuration including Docker swarm setup.

[Back to top](#autonomous-tests-swarm)

## Quick Start

### 1. Install & Setup

Install the skill and run the setup script (see [Installation](#installation) above).

### 2. Run the Skill

Navigate to your project that has code changes, then invoke:

```
/autonomous-tests-swarm
```

### 3. Configure Your Project

On first run, the skill auto-detects your project topology, services, database, and Docker setup. It asks about compose vs raw Docker mode, initialization commands, and related projects. Review the proposed config and approve.

### 4. Review & Execute

The skill enters plan mode with a full test plan — review and approve. Each agent spins up its own environment, runs its suites, reports results, and tears down.

[Back to top](#autonomous-tests-swarm)

## Usage

```
/autonomous-tests-swarm [argument]
```

| Argument | Meaning |
|---|---|
| _(empty)_ | Default: working-tree (staged + unstaged) with smart doc analysis |
| `staged` | Staged changes only |
| `unstaged` | Unstaged changes only |
| `N` (number) | Last N commits (e.g., `1` = last commit, `3` = last 3) |
| `working-tree` | Staged + unstaged changes (same as default) |
| `file:<path>` | Use a `.md` doc as additional test context (path relative to project root) |
| `rescan` | Force re-scan of capabilities regardless of cache |
| `guided` | Feature/workflow-centric mode — prompts to pick a doc or describe a feature |
| `guided "description"` | Test a feature by description — happy path + security only |
| `guided file:<path>` | Test a feature from a spec doc — full 9-category coverage |

Arguments are combinable:
```
/autonomous-tests-swarm staged file:docs/payments.md
/autonomous-tests-swarm 3 rescan
/autonomous-tests-swarm guided "payment checkout flow"
/autonomous-tests-swarm guided file:docs/payments.md
/autonomous-tests-swarm guided rescan
```

### Guided Mode

Use `guided` to test existing features or workflows without needing code changes. This bypasses git diff analysis and instead traces a described feature through the codebase.

| Sub-mode | Trigger | Test Coverage |
|---|---|---|
| Doc-based | `guided file:docs/spec.md` or pick from `docs/`/`_autonomous/pending-guided-tests/` when prompted | Full 9-category coverage |
| Description-based | `guided "payment checkout flow"` or describe when prompted | Happy path + security analysis |

**How it works:**
- `guided` alone prompts you to pick a doc or describe a feature
- `guided "description"` uses the description to search the codebase for related files, endpoints, models, and services
- `guided file:<path>` reads the spec doc and extracts features, endpoints, and acceptance criteria

**Combinability:**
- Combinable with `rescan`: `/autonomous-tests-swarm guided rescan`
- **NOT** combinable with `staged`, `unstaged`, `N`, or `working-tree` — guided mode bypasses git diff analysis

**Examples:**
```
/autonomous-tests-swarm guided
/autonomous-tests-swarm guided "user registration and onboarding"
/autonomous-tests-swarm guided file:docs/payments-feature.md
```

[Back to top](#autonomous-tests-swarm)

## Configuration

The skill reuses `.claude/autonomous-tests.json` with an additional `swarm` section. On first run (or first swarm run), the skill walks you through setup.

### Base Config

Same as [`autonomous-tests` configuration](../autonomous-tests/README.md#configuration) — project, database, services, documentation paths, capabilities.

### Swarm Section

| Field | Description |
|---|---|
| `dockerContext` | Docker context to use (auto-detected, Docker Desktop prioritized) |
| `mode` | `compose`, `raw-docker`, or `npm-dev` — how to spin up agent environments |
| `composeFile` | Path to compose file (compose mode only) |
| `composePath` | Directory containing the compose file |
| `rawDockerServices` | Service definitions for raw Docker mode |
| `portRangeStart` | First port in the allocation range (default: 9000) |
| `portStep` | Port range size per agent (default: 100) |
| `maxAgents` | Maximum parallel agents (default: 5) |
| `portMappings` | Service-to-port mappings with health checks |
| `initialization` | Commands to run after services start (migrations, seeds) |
| `envFiles` | List of env files to copy and remap per agent — `scope` (primary or related service), `source` (compose `env_file:`, auto-detected, user-configured) |
| `envPortMappings` | Maps env var names to services for port remapping — `direct` (bare port) or `url` (port within URL) |
| `relatedServices` | Additional projects to include in each agent's stack (supports `compose`, `raw-docker`, and `npm-dev` modes per service) |
| `relatedServices.*.nodeModulesStrategy` | `symlink` (default), `hardlink` (Turbopack-compatible), or `copy` (universal) — auto-detected from bundler |
| `resourceLimits` | Container resource constraints — `memory` (`512m`, `1g`), `cpus` (`0.5`, `1`), `readOnlyRootfs` (bool), `tmpfsMounts` (writable paths). All default to null/false (opt-in) |
| `audit` | Per-agent structured audit logs — `enabled` (default: true), `logDir`, `schemaVersion` (`"1.0"`). Logs command timelines, resource config, and cleanup verification per agent |
| `cleanup` | Teardown options (remove volumes, orphans) |

See [`references/config-schema-swarm.json`](references/config-schema-swarm.json) for the full schema.

### Template Placeholders

Resolved per-agent at runtime:

| Placeholder | Resolves To |
|---|---|
| `{projectName}` | `swarm-{N}` (agent's compose project name) |
| `{port}` | Assigned host port for that service |
| `{containerName}` | `swarm-{N}-{service}` |
| `{backendPort}` | Assigned host port for the backend service (primary compose stack) |
| `{sessionId}` | Unique session identifier (timestamp-based) |
| `{auditDir}` | Per-session audit log directory |
| `{resourceFlags}` | Resolved `--memory`, `--cpus`, `--read-only`, `--tmpfs` flags |

### No Credentials Needed

Unlike `autonomous-tests`, swarm agents don't need shared test credentials. Each agent:
1. Starts its own database
2. Runs migrations and seeds against its own DB
3. Creates its own test data
4. Tests against its own isolated API

This eliminates credential conflicts entirely.

### Security Posture

The skill enforces explicit operational bounds to constrain resource usage and prevent unsafe operations:

| Bound | Limit |
|---|---|
| Max agents | Equal to approved test suites, capped at `maxAgents` (default 5) |
| Max fix cycles | 3 per suite |
| Health check timeout | 60 seconds per service, 2 attempts |
| Command execution | Only commands from user-approved config — no dynamic shell generation |
| Docker scope | Local containers only — aborts on production indicators, namespaced compose projects |
| MCP activation | Only `safe: true` MCPs — `safe: false` are never activated |
| Agent lifecycle | One suite per agent — start env, execute, teardown, shut down |
| External service CLIs | Sandbox only — blocked on production keys, per-run confirmation, catalog-defined allowlist |
| System commands | Explicit allowlist — only read-only/idempotent commands beyond user config |
| External downloads | Docker images from user's compose files only — no arbitrary downloads |
| Data access | `settings.json` and `.env` for safety checks only — values never logged or output |
| Resource limits | Opt-in `memory`, `cpus`, `read_only`, `tmpfs` constraints per container — configured via `swarm.resourceLimits` |
| Network labels | All Docker resources labeled `com.autonomous-swarm.*` with session and agent IDs — hardcoded, not configurable |
| Capabilities freeze | Setup agent captures capabilities snapshot at setup time — suite agents use frozen snapshot, never re-scan |
| Audit trail | Per-agent structured JSON audit logs with command timeline, resource config, cleanup verification — `schemaVersion: "1.0"` |
| Trust boundaries | Untrusted inputs (diffs, docs) gated by mandatory plan approval before execution |

[Back to top](#autonomous-tests-swarm)

## Output

Same output format as autonomous-tests. Documents are generated in `docs/_autonomous/`:

| Document | When Generated | Location |
|---|---|---|
| Test Results | Always | `test-results/` |
| Pending Fixes | When bugs found | `pending-fixes/` |
| Guided Tests | When browser/visual testing needed | `pending-guided-tests/` |
| Pending Autonomous Tests | When tests deferred | `pending-autonomous-tests/` |

See [`autonomous-tests/references/templates.md`](../autonomous-tests/references/templates.md) for exact output formats.

[Back to top](#autonomous-tests-swarm)

## How It Works

```
Phase 0: Config          ← Setup, validate, scan capabilities, detect Docker context
Phase 1: Safety          ← Block if production detected
Phase 2: Port Discovery  ← Scan ports, validate Docker environment
Phase 3: Discovery       ← Analyze diff (or guided feature), file refs, history
Phase 4: Plan            ← Generate test plan with per-agent env specs (you approve)
Phase 5: Swarm Execute   ← Each agent: start env → init → test → teardown
Phase 6: Fix             ← Auto-fix runtime issues, document bugs
Phase 7: Docs            ← Generate markdown reports
Phase 8: Cleanup         ← Remove test data, verify Docker cleanup
Phase 9: Advisory        ← Remind user to /clear before next skill
```

### Targeted Regression Mode

When re-running after `autonomous-fixes` has applied fixes (fix-results with `Ready for Re-test: YES`), the skill automatically activates **regression mode**. Instead of re-testing the entire feature blast radius, it generates only 2 targeted suites: **Fix Verification** (re-run the exact failing scenarios) and **Impact Zone** (test direct dependencies of modified files). Previously validated areas unaffected by the fix are excluded, reducing token usage. If the fix's blast radius exceeds 60% of the feature map, the skill falls back to full-scope testing. Note: for small regression scopes (<=2 suites), the swarm Docker isolation overhead may exceed the benefit — the plan will note this.

### Phase 5 Detail — Per-Agent Lifecycle

Each agent follows this sequence:

1. **Generate environment** — create modified compose file (or docker run commands) with remapped ports in `/tmp/autonomous-swarm-{sessionId}/agent-{N}/`. Copy and remap `.env` files per agent. For `npm-dev` related services, copy the project to the agent's temp dir (set up `node_modules` via configured strategy) and start with unique port assignments
2. **Start stack** — `docker compose -p swarm-{N} ... up -d` (or `docker run` commands)
3. **Health check** — poll each service until healthy (60s timeout, 2 attempts)
4. **Initialize** — run migrations, seeds, and setup commands
5. **Execute tests** — run assigned suites against own API (using remapped ports)
6. **Report** — send PASS/FAIL per suite via `SendMessage`
7. **Teardown** — stop and remove all containers, volumes, networks, `npm-dev` processes, temp files

If an agent's environment fails to start, its suites are redistributed to a healthy agent.

[Back to top](#autonomous-tests-swarm)

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| "Working tree is clean" | No changes with default scope | Use `/autonomous-tests-swarm N` for commits |
| "Agent teams not enabled" | Missing feature flag | Run `bash scripts/setup-hook.sh` |
| Port conflicts | Other services using the port range | Change `portRangeStart` in config |
| Docker disk space warning | Not enough space for N stacks | Free Docker space: `docker system prune` |
| Compose startup fails | Invalid compose file or missing images | Check `docker compose config` and pull images |
| Orphaned containers after failure | Teardown didn't complete | Run `docker ps -a --filter name=swarm- -q \| xargs docker rm -f` |
| "Docker Desktop context not found" | Docker Desktop not installed | Use `default` context — skill will auto-detect |
| Health check timeout | Services slow to start | Increase `waitAfterStartSeconds` in config |
| Suite redistribution | Agent env failed to start | Normal — suites move to healthy agents |
| `.next` / build lock conflicts | `npm-dev` service running from original dir | Set related service `mode: "npm-dev"` — agents copy the project to `/tmp/` for isolation |
| Env vars still have original ports | `envPortMappings` missing or incomplete | Add all port-containing env vars to `swarm.envPortMappings` — use `direct` for bare ports, `url` for ports in URLs |
| Turbopack fails with symlinked `node_modules` | Turbopack can't resolve through symlinks | Set `nodeModulesStrategy: "hardlink"` on the related service — uses `cp -al` for real directory that bundlers can resolve |
| Browser tests hit host services instead of agent stack | Env file remapping not configured or node_modules strategy incompatible | Check `swarm.envFiles` and `swarm.envPortMappings` are configured, and `nodeModulesStrategy` is `hardlink` for Next.js/Turbopack projects |
| Container OOM killed | `resourceLimits.memory` too low for service | Increase `memory` limit or set to `null` (no limit) |
| Read-only rootfs failures | Service writes to paths not in `tmpfsMounts` | Add writable paths to `tmpfsMounts` (e.g., `/tmp`, `/var/run`, `/var/log`) or disable `readOnlyRootfs` |
| Orphaned volumes after failure | Dynamic volumes not caught by name-based cleanup | Run label-based cleanup: `docker volume ls --filter label=com.autonomous-swarm.session={sessionId} -q \| xargs docker volume rm` |
| "guided cannot be combined with git-scope args" | `guided` used with `staged`/`unstaged`/`N`/`working-tree` | Use `guided` alone or with `rescan` only — guided bypasses git diffs |

### Emergency Cleanup

If a run is interrupted and Docker resources remain:

```bash
# Stop and remove all swarm containers (name-based)
docker ps -a --filter name=swarm- -q | xargs docker rm -f 2>/dev/null

# Stop and remove all swarm containers (label-based — catches dynamically named containers)
docker ps -a --filter label=com.autonomous-swarm.managed=true -q | xargs docker rm -f 2>/dev/null

# Remove swarm networks
docker network ls --filter name=swarm- -q | xargs docker network rm 2>/dev/null
docker network ls --filter label=com.autonomous-swarm.managed=true -q | xargs docker network rm 2>/dev/null

# Remove swarm volumes (label-based — catches dynamically created volumes)
docker volume ls --filter label=com.autonomous-swarm.managed=true -q | xargs docker volume rm 2>/dev/null

# Clean up temp files
rm -rf /tmp/autonomous-swarm-*
```

[Back to top](#autonomous-tests-swarm)

## Project Structure

```
autonomous-tests-swarm/
├── README.md                        ← You are here
├── SKILL.md                         ← Claude-facing skill definition
├── references/
│   └── config-schema-swarm.json     ← Swarm config section schema
└── scripts/
    └── setup-hook.sh                ← Settings installer
```

Output templates are shared with autonomous-tests: see [`autonomous-tests/references/templates.md`](../autonomous-tests/references/templates.md).
