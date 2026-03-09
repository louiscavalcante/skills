# Release Notes

## v2.3.0

### Added
- **Inline DB consistency checks** (all 3 skills): Verification now runs within each database-modifying phase while data is present (POST_SEED, POST_TEST, POST_CLEANUP for test skills; POST_FIX for fixes), replacing the standalone post-cleanup check that trivially passed against an empty database. Agents capture a `dbBaseline` before first DB write and verify record counts, schema conformance, referential integrity, orphans, mutations, and cleanup completeness at each check point. Results (PASS/WARN/FAIL) reported alongside suite PASS/FAIL and included in test-results/fix-results documentation. Protocol defined once in `autonomous-tests/references/db-consistency-protocol.md` and referenced by all three skills via self-containment mandate.

## v2.2.0 (2026-03-09)

### Added
- **Stripe Test Clock support** (autonomous-tests + swarm): Live E2E tests can now simulate time progression for subscription lifecycle testing (renewals, trials, billing cycles). Phase 2 detects test clock need via `testClockSupport.triggerKeywords` in the external services catalog. Phase 3 embeds a 10-step Stripe Test Clock sub-protocol in the Live E2E execution block — create clock, attach customer, create subscription, advance time, verify state via MCP, check webhooks, cleanup. CLI required for test clock operations (MCP lacks these endpoints); MCP used for complementary operations (customer creation, subscription verification).
- **AskUserQuestion enforcement for guided tests** (autonomous-tests + swarm): Guided test step presentation now uses a structured `AskUserQuestion` call with formatted question and explicit options ("Done - ready to verify", "Skip this test", "Issue encountered"). Text-only output is PROHIBITED — ensures consistent UX and proper response routing (verify, skip, or record issue). Applied to guided mode, guided happy-path mode, and Phase 4 execution flow.
- **Always-run Tool Inventory scan** (all 3 skills): Phase 0 now includes a Tool Inventory step that runs every session (no caching). Orchestrator extracts available skills and agent types from context; Explore agent scans for MCP servers and CLIs. Compiled inventory includes per-phase recommendations. Embedded in Phase 3 self-containment mandate and passed to subagents via `TOOL CONTEXT` lines in all execution protocols.
- **External services catalog — Stripe test clocks** (autonomous-tests): Added `testClockSupport` object to Stripe entry with CLI operations, MCP complement operations, and trigger keywords. Added `stripe test_clocks create/advance/delete` to `allowedOperations` (sandbox scope). Extended `claudeMdKeywords` with subscription/billing terms.

## v2.1.0 (2026-03-09)

### Added
- **Live E2E testing prompt** (autonomous-tests + swarm): When external service CLIs/MCPs are available and relevant to the tested code, offers sandbox live E2E testing after autonomous suites. Phase 2 cross-references the feature map with detected capabilities to build an eligibility list, then prompts the user before plan mode. Live E2E runs sequentially after all mocked autonomous suites, with per-service CLI gate and runtime sandbox re-verification.
- **Guided happy-path prompt** (autonomous-tests + swarm): Offers manual testing opt-in during standard mode runs. User performs actions on device/browser while Claude verifies via DB/API/logs. Runs last — after autonomous and live E2E suites. Skipped when `guided` arg or regression mode is active.
- **Post-discovery prompts** (autonomous-tests + swarm Phase 2): Single `AskUserQuestion` after Feature Context Document compilation presents both live E2E and guided happy-path options. Standard mode only — skipped for `guided` arg or regression mode.
- **Live E2E eligibility analysis** (autonomous-tests + swarm Phase 2): Orchestrator cross-references feature map external service usage with `externalServices[]` capabilities to classify services as eligible, blocked, or unavailable.
- **Execution protocols for live E2E, guided happy path, and documentation** (autonomous-tests + swarm Phase 3): Three new protocol blocks embedded in plans — survive context reset and provide post-reset orchestrator with complete execution instructions.
- **Self-containment items 9-11** (autonomous-tests + swarm Phase 3): Plans now embed Live E2E Decision block (item 9), Guided Happy Path Decision block (item 10), and Documentation checklist (item 11) for post-reset survival.
- **Rules and operational bounds** (autonomous-tests + swarm): New entries for live E2E scope, guided happy path scope, post-discovery prompts, and documentation output requirements.

### Fixed
- **Documentation generation after context reset** (autonomous-tests + swarm): Added `DOCUMENTATION` as an explicit step in the autonomous execution protocol block. Previously, the protocol ended at `AUDIT` — after context reset, the orchestrator followed the protocol verbatim and never generated docs because Phase 5 instructions in the SKILL.md were no longer in context. The documentation protocol block is now always embedded in every plan, ensuring test-results docs are generated for every run.

### Changed
- **Phase 5 documentation paragraph** (autonomous-tests + swarm): Updated to clarify test-results docs are always generated (even on all-pass), and live E2E / guided happy-path results are included under dedicated suite sections in unified output.
- **Phase 4 execution flow** (autonomous-tests + swarm): Added numbered steps for live E2E suites and guided happy-path tests after autonomous suite execution.

## v2.0.1 (2026-03-06)

### Fixed
- **Service restoration after context reset** (autonomous-tests): Phase 4 now spawns a mandatory service restoration agent FIRST — re-verifies all services from the embedded Service Readiness Report, restarts unhealthy ones via `startCommand` + poll, starts webhook listeners, and gates on failures before any test execution. Fixes background processes dying when context resets on plan approval.
- **Strengthened seed schema analysis gate** (autonomous-tests + swarm): Seed schema discovery is now a mandatory gate (PROHIBITED to proceed without completing schema analysis). Added to self-containment mandate for plan embedding, execution protocols, and Phase 4 agent instructions in both testing skills.
- **Fix verification double-check** (all 3 skills): Runtime fix cycles (autonomous-tests + swarm) now verify issues are real before attempting fixes — re-read error output, check if transient, confirm root cause. Code fix agents (autonomous-fixes) double-check that the issue still exists in current code before writing any fix, with `FALSE_POSITIVE` status for misidentified findings.

## v2.0.0 (2026-03-06)

### Breaking Changes
- **Agent Teams → Built-in Subagents** (all three skills): Replaced experimental Agent Teams (`TeamCreate`/`TaskCreate`/`TaskUpdate`/`SendMessage`/`TeamDelete`) with built-in subagents via `Agent()`. Tools removed from `allowed-tools`: `TaskCreate`, `TaskUpdate`, `TaskList`, `TaskGet`, `TeamCreate`, `SendMessage`, `TeamDelete`. Env var `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` no longer required.
- **Setup scripts install 3 items** (down from 4): Removed Agent Teams flag installation. Scripts now configure: ExitPlanMode hook, AskUserQuestion hook, and Model.

### Added
- **Test flow classification** (autonomous-tests + swarm Phase 2): Explore agent classifies each test scenario as `autonomous/api`, `autonomous/ui`, `guided/webapp`, or `guided/mobile`. Related projects with `relationship: "mobile"` produce `guided/mobile` classifications.
- **Related project log verification** (autonomous-tests Phase 4): After each subagent completes, orchestrator checks related project logs for errors using discovered log commands with `--since` timestamp.
- **Related project log commands** (autonomous-tests + swarm Phase 2): Explore agent discovers log commands per `relatedProjects[]` entry for post-test verification.
- **Mobile test planning** (autonomous-tests Phase 5): `guided/mobile` tests included in pending-guided-tests output with physical device steps and verification commands.
- **Explore agent thoroughness levels**: Explicit thoroughness guidance (`"quick"`, `"medium"`, `"very thorough"`) for Explore agent spawns.

### Changed
- **Subagent execution model** (autonomous-tests + autonomous-fixes): Sequential execution uses foreground subagents — spawn one at a time, results return directly, no shutdown protocol needed.
- **Subagent execution model** (autonomous-tests-swarm): Parallel execution uses background subagents (`run_in_background: true`) — orchestrator notified on completion.
- **Feature Context Document** (both testing skills): Now includes test flow classifications and related project log commands.
- **CLAUDE.md**: "Task Execution via Agent Team" section rewritten as "Task Execution via Subagents" with updated spawning rules.

## v1.14.0 (2026-03-05)

### Added
- **Cross-project seed map** (autonomous-tests + swarm Phase 2): Explore agent now traces which collections/tables in related project databases are read by the main project's E2E flows (shared users, linked entities, cross-service references). Per dependency: related project name, collection/table, required fields, relationship to main project data, connection command.
- **Seed schema discovery for related projects** (autonomous-tests + swarm Phase 4): The seed schema discovery protocol now explicitly covers all databases in the E2E flow, including related projects. New step (5): use connection command from `relatedProjects[]` config or the cross-project seed map in the Feature Context Document. Verification changed from "before user interaction" to "before proceeding" to cover both autonomous and guided modes.
- **Seed schema discovery rule** (autonomous-tests-swarm): New rule row in the Rules table — previously only existed in autonomous-tests.

### Changed
- **Feature Context Document** (both testing skills): Now includes cross-project seed map (related project DB dependencies with collection/table, required fields, connection commands) — cascaded to all Phase 4 agents.
- **Seed schema discovery rule wording** (autonomous-tests): Updated from "Before seeding" to "Before seeding any DB (main or related project)" for clarity.

## v1.13.0 (2026-03-05)

### Added
- **Resume Detection** (autonomous-fixes Phase 0 Step 4): When invoked after a manual fix, `git diff --name-only` is cross-referenced against finding source files. If fixes are already applied in the working tree, skips directly to Phase 4 (Verification & Documentation) — executing all substeps (4a → 4b → 4c) without shortcuts.
- **Post-Fix Checklist** (autonomous-fixes Phase 2): Every plan now embeds a verbatim checklist of all post-fix steps (4a verification, 4b documentation, 4c loop signal + cleanup + finalize). Survives context compression and ensures no step is skipped after fixes are applied.
- **Related project production safety scan** (autonomous-tests + swarm Phase 1): The environment safety agent now scans `.env` files in every `relatedProjects[]` path for the same production indicators checked in the main project. A production indicator in any related project triggers the same ABORT gate. Previously, only the main project's environment was checked.

### Changed
- **Merged Phase 5 into Phase 4c** (autonomous-fixes): Phase 4c "Loop Signal", Phase 4d "Source Document Cleanup", and Phase 5 "Finalize" consolidated into a single **4c. Loop Signal & Finalize** step. Phase 4c is now explicitly the LAST step — there is no Phase 5.
- **Hard rule: never stop after docs** (autonomous-fixes): New rule in the Rules section — "Documentation (4b) is NOT the end — 4c (loop signal + cleanup + finalize) is MANDATORY. Never stop after generating docs."

## v1.12.0 (2026-03-05)

### Added
- **Targeted regression mode** (autonomous-tests + swarm): When re-running after `autonomous-fixes` applies fixes (`Ready for Re-test: YES`), the testing skills now automatically activate regression mode. Instead of re-testing the entire feature/workflow blast radius, they analyze the fix scope (files modified, 1-hop callers/callees) and generate only 2 targeted suites: "Fix Verification" (re-execute exact original failure scenarios) and "Impact Zone" (test direct dependencies for side-effects). Previously validated areas unaffected by the fix are excluded.
- **Regression Scope Analysis** (Phase 2, both testing skills): New conditional step after the Explore agent returns. Detects re-test indicators, compiles a fix manifest, computes 1-hop impact zone, cross-references prior test results for pass/fail mapping, and produces a Targeted Regression Context Document that replaces the Feature Context Document for Phase 3.
- **Blast radius escape hatch**: If modified files' 1-hop zone covers >60% of the feature map, regression mode falls back to full-scope testing automatically.
- **`Original Test IDs` field** (autonomous-fixes fix-results template): Fix-results now record the original test IDs from source findings, enabling direct cross-referencing during regression scope analysis. Backward-compatible — legacy fix-results without this field fall back to `Source` path cross-referencing.
- **Swarm efficiency note** (autonomous-tests-swarm): Regression mode plans note when <=2 suites make swarm Docker overhead potentially excessive.

## v1.11.0 (2026-03-04)

### Changed
- **Guided mode redesign** (autonomous-tests + swarm): Guided mode is now strictly user augmentation — user performs actions on real device/browser while Claude provides step-by-step instructions and verifies results via DB queries/API. No agent-browser or Playwright in guided mode. Before each test, an agent seeds the database and configures external services. Only happy-path workflows (category 1) in guided sessions; categories 2-9 are autonomous-only.
- **Guided mode single-agent** (autonomous-tests-swarm): Guided mode overrides parallel execution — spawns one agent at a time sequentially, since user can't benefit from parallel agents.
- **Tool loading gate** (autonomous-tests + swarm): Browser automation tools (agent-browser, Playwright) now require explicit user approval before plan finalization. Never prompted in guided mode.
- **Plan self-containment mandate** (all three skills): Plans must embed all context needed for post-context-reset survival: test suites/fix items with full details, Feature Context/Fix Context Documents (condensed), per-suite/per-item agent spawn instructions with resolved values, config paths, and service readiness data. No references to "above" or prior phases.
- **autonomous-fixes plan enrichment**: Setup agent's Fix Context Documents must be embedded in plan text. Plan now requires concrete per-item spawn instructions with file paths, fix steps, verification commands, and expected outcomes.

## v1.10.1 (2026-03-04)

### Fixed
- **Execution Protocol in plans** (all three skills): Plans now embed a verbatim Execution Protocol block in Step 0 Context Reload. After context reset on plan approval, the orchestrator retains the full agent team workflow (TeamCreate, spawning pattern, sequential/parallel flow, shutdown) without needing to re-read SKILL.md. Fixes orchestrator skipping Agent Team creation post-reset.

## v1.10.0 (2026-03-04)

### Changed
- **Orchestrator Protocol** (all three skills): Added explicit section defining orchestrator boundaries — MUST delegate operational work (bash commands, source reading, file generation, test/fix execution) to agents. MAY only coordinate, gate, and interact with user.
- **Phase restructuring** (all three skills): Consolidated from 9-10 phases to 7 (phases 0-6). Merged Safety + Service Startup → Safety & Environment. Merged Fix Cycle + Documentation + Cleanup → Results & Docs. Context Reset → Finalize. Each phase now has a single clear objective.
- **Mandatory setup agent** (autonomous-tests + autonomous-fixes): Setup agent is now required for ALL suite/item counts. Removed "for 1-2 items, orchestrator may prepare context directly" exception.
- **Strictly sequential execution** (autonomous-fixes): Removed parallel group logic and dependency analysis. Execution is always sequential — one agent at a time, same pattern as autonomous-tests.
- **Removed `credentialType` handling** (autonomous-fixes): Since execution is always sequential, token-based vs session-based credential classification is unnecessary. Removed prompt and associated logic.
- **Config version alignment** (autonomous-fixes): Updated config version check from 4 to 5, aligning with autonomous-tests schema.
- **Operational delegation** (all three skills): Capabilities scan, CLAUDE.md deep scan, findings scan, document parsing, safety checks, service startup, port scanning, doc generation, and cleanup all delegated to agents instead of orchestrator executing directly.
- **Hash computation deduplication** (all three skills): SHA-256 config hash defined once as "Config hash method" in Phase 0, referenced by label throughout instead of repeated verbatim (~7 occurrences eliminated per skill).
- **Rules consolidation** (all three skills): Converted verbose prose rules to compact tables. Removed rules that restated phase instructions. Deduplicated overlapping constraints.
- **Templates deduplication**: Removed fix-results template from `autonomous-tests/references/templates.md` — canonical copy in `autonomous-fixes/references/templates.md`.

## v1.9.0 (2026-03-04)

### Changed
- **Phase 3 — Explore agent delegation** (autonomous-tests + swarm): Feature identification and discovery is now delegated to a single Explore agent (`subagent_type: "Explore"`) instead of running inline Glob/Grep/Read in the main context. The Explore agent performs feature map building, dependency graph tracing, smart doc analysis (all 3 sub-steps), and edge case inventory, then returns structured findings. The orchestrator compiles the Feature Context Document from the agent's report without re-reading files. Spawned without `team_name` since Phase 3 runs before team creation.
- **Phase 2 — Service Readiness Report** (autonomous-tests): Phase 2 now produces a structured Service Readiness Report (one entry per service: name, URL/port, health status, health check endpoint, source). The report flows through Phase 4 Context Reload into Phase 5 task descriptions — agents receive correct service URLs/ports and are prohibited from starting services or re-checking health.
- **Phase 5 — Sequential execution enforcement** (autonomous-tests): Replaced prose description with an explicit pseudocode loop and prohibited patterns list. The loop enforces: spawn one agent → block → wait for completion → shut down → only then proceed. Prohibited patterns include spawning multiple agents before any completes, spawning agent N+1 before agent N shuts down, and any parallel or overlapping agent execution.

## v1.8.0 (2026-03-04)

### Added
- **Guided mode** (autonomous-tests + swarm): `guided` argument enables testing existing features or workflows without code changes. Bypasses git diff analysis and traces a described feature through the codebase using keyword search (Glob for filenames, Grep for routes/models/handlers).
- **Two guided sub-modes**: doc-based (`guided file:<path>` — full 9-category coverage) and description-based (`guided "description"` — happy path + security only). `guided` alone prompts via `AskUserQuestion` to pick a doc or describe a feature.
- **Guided combinability rules**: `guided` is combinable with `rescan` but NOT with `staged`, `unstaged`, `N`, or `working-tree` — validated at Phase 3 start with a clear error message.
- **Trigger tests** for guided mode: `guided-test-feature.txt` (autonomous-tests) and `guided-swarm-test-feature.txt` (autonomous-tests-swarm).

### Changed
- **Phase 3** (autonomous-tests + swarm): split into conditional branches — standard mode (git diff, unchanged) and guided mode (resolve source → deep feature analysis → common steps). Both converge at the feature map building step.
- **Phase 4** (autonomous-tests + swarm): test category scope is now conditional — standard or guided doc-based uses all 9 categories; guided description-based uses only happy path + security. Context Reload Step 0 includes guided mode type and source when applicable.
- **Feature Context Document**: includes `Mode: guided (doc-based|description-based)` and `Source:` header when guided mode is active.
- **Smart doc analysis**: clarified as "always active in standard mode" — guided mode has its own deep feature analysis that replaces diff-based discovery.

## v1.7.0 (2026-03-04)

### Changed
- **Always-sequential execution** (autonomous-tests): Execution is now always sequential — one agent at a time, one suite at a time. Removes token/session credential type logic that determined parallel vs sequential execution. The `autonomous-tests-swarm/` skill handles true parallel execution with isolated Docker environments.
- **Removed `credentialType` config field** (autonomous-tests): `userContext.credentialType` removed from config schema. Existing configs with `credentialType` are silently cleaned up on next run.
- **Removed credential type prompting** (autonomous-tests): First-run questionnaire and returning-run ensure block no longer ask about token-based vs session-based credentials.
- **Simplified credential assignment** (autonomous-tests): Agents receive role names from `userContext.testCredentials` directly, rotated across suites if multiple roles exist. Sequential execution prevents conflicts regardless of credential type.
- **Phase 4 Context Reload** (autonomous-tests): Removed "Credential assignment plan" line — no longer needed with always-sequential execution.
- **Phase 5 description** (README): Updated to describe sequential execution model — spawn agent, assign suite, wait, shut down, repeat.
- **Troubleshooting** (README): "Shared credentials between agents" → "Credential misconfiguration" with updated fix guidance.
- **Setup script** (autonomous-tests): "parallel test execution" → "agent team orchestration" in output messaging.

## v1.6.0 (2026-03-04)

### Added
- **Container resource limits** (autonomous-tests-swarm): opt-in `swarm.resourceLimits` config — `memory` (`--memory`), `cpus` (`--cpus`), `readOnlyRootfs` (`--read-only`), and `tmpfsMounts` (`--tmpfs`). Injected into generated compose files (`mem_limit`, `cpus`, `read_only`, `tmpfs`) and raw Docker `docker run` commands. All defaults are null/false — limits are opt-in, not enforced by default.
- **Docker resource labeling** (autonomous-tests-swarm): all containers, networks, and volumes are labeled with `com.autonomous-swarm.managed=true`, `com.autonomous-swarm.session={sessionId}`, and `com.autonomous-swarm.agent={N}`. Labels are hardcoded (not configurable) and enable reliable secondary cleanup verification alongside name-based filtering.
- **Per-agent structured audit logs** (autonomous-tests-swarm): `swarm.audit` config section — enabled by default with `schemaVersion: "1.0"`. Each suite agent writes `agent-{N}.json` with command timeline, port assignments, health check results, configured resource limits, teardown verification, and duration. Orchestrator merges into `audit-summary.json` with session metadata and totals.
- **Capabilities freeze** (autonomous-tests-swarm): setup agent captures a capabilities snapshot at setup time (MCPs, frontend testing tools, external service CLI approvals). Snapshot is distributed verbatim to all suite agents. Suite agents must not re-scan — prevents drift during long-running swarm executions.
- **Label-based emergency cleanup** commands in README: `docker ps/network/volume` filters using `com.autonomous-swarm.managed=true` label — catches dynamically created resources missed by name-based filters.
- **`{auditDir}` and `{resourceFlags}` template placeholders** in config schema.

### Changed
- **Phase 0 Swarm Questionnaire**: new Q7 asks about container resource limits (memory, cpus, read-only rootfs) with defaults.
- **Phase 2 Port Discovery**: new step 6 initializes audit directory and writes `session.json` manifest when audit is enabled.
- **Phase 5 setup agent**: new substeps — freeze capabilities snapshot (6b), inject resource limits into compose/Docker files (6c), apply Docker labels to all resources (6d).
- **Phase 5 suite agents**: receive frozen capabilities snapshot (substep b) — no re-scanning allowed. New substep h2 writes per-agent audit log after test results.
- **Phase 5 post-execution**: label-based secondary cleanup verification for containers, networks, and volumes. New step 7b merges audit logs into summary.
- **Phase 7 Documentation**: appends "Execution Audit" section to test-results when audit enabled — only the orchestrator writes to `docs/_autonomous/`.
- **Phase 8 Cleanup**: label-based verification added alongside name-based checks (containers, networks, volumes).
- **Operational Bounds**: 4 new bounds (resource limits scope, network labeling scope, capabilities freeze scope, audit scope). System command allowlist includes `docker ps/network/volume --filter label=` commands.
- **Security Posture** (README): 4 new rows — resource limits, network labels, capabilities freeze, audit trail.
- **Troubleshooting** (README): 3 new entries — OOM killed containers, read-only rootfs failures, orphaned volumes.

## v1.5.0 (2026-03-03)

### Added
- **Env file port remapping** (autonomous-tests-swarm): `.env` / `.env.local` files are copied to each agent's temp directory and port values are remapped per agent. Supports `direct` ports (`PORT=8000`) and `url`-embedded ports (`DATABASE_URL=postgres://localhost:5432/db`). Original files are never modified.
- **`swarm.envFiles`** config field: lists env files to copy and remap per agent, with `scope` (primary or related service) and `source` (compose `env_file:`, auto-detected, or user-configured).
- **`swarm.envPortMappings`** config field: maps env var names to services for port remapping — `direct` type replaces bare port values, `url` type replaces ports within URLs.
- **Bundler-compatible `node_modules` strategy** (autonomous-tests-swarm): `nodeModulesStrategy` config field on related services — `symlink` (default, fast), `hardlink` (`cp -al`, Turbopack/rspack compatible), or `copy` (`cp -r`, universal). Auto-detected from `package.json` bundler during Swarm Configuration Questionnaire.
- **`{backendPort}` template placeholder**: resolves to the assigned host port for the backend service in the primary compose stack.

### Changed
- **Phase 0 Swarm Questionnaire**: detects env files from compose `env_file:` directives and directory scans, identifies port-related variables via heuristics, and presents mappings for user confirmation.
- **Phase 5 setup agent**: copies and remaps env files per agent before suite agents start — updates compose `env_file:` paths and npm-dev project env files.
- **Phase 5 npm-dev mode**: node_modules setup uses `nodeModulesStrategy` instead of always symlinking — hardlink mode resolves Turbopack symlink incompatibility.
- **Operational Bounds**: system command allowlist includes `python3 -c` with `re` stdlib for env file remapping and `cp -al` for hardlink node_modules. Data access scope documents env file copies.

## v1.4.0 (2026-03-03)

### Added
- **Finding verification before reporting** (autonomous-tests + swarm): Agents must read source code to confirm findings reflect real application behavior before reporting. Prevents false positives from synthetic test data artifacts.
- **Deep CLAUDE.md scanning** (all three skills): Discovers CLAUDE.md files up to 3 levels deep from project root. Subdirectory files provide service-specific setup, architecture, and environment context.
- **Setup agent delegation** (all three skills): Orchestrator spawns a dedicated setup agent for environment preparation and source file reading before suite/fix agents start. Reduces main agent context usage.

### Changed
- **Anomaly detection** and **API Response Security** require source verification before reporting
- **autonomous-fixes Phase 2**: Explicit step to verify findings still reproduce before fixing
- **System command allowlist** includes `find` for CLAUDE.md deep scan
- **Data access scope** documents CLAUDE.md deep scan
- **Max agents bounds** account for setup agent

## v1.3.0 (2026-03-03)

### Added
- **External services catalog** (`references/external-services-catalog.json`): Maps known services to CLI tools, production indicators, sandbox patterns, and allowed operations. Add new services to the catalog — no SKILL.md changes needed.
- **CLAUDE.md scanning for external services** (Phase 0): Scans project, global, and local CLAUDE.md files for service keywords from the catalog. Auto-detects relevant CLIs.
- **Generic external service CLI gating** (Phase 5): Per-service user confirmation using catalog-defined prompt templates.
- **Config schema v5**: `externalServices[].cli` sub-object replaces `capabilities.stripeCli`. Includes `source`, `allowedOperations`, `prohibitedFlags`, `approvedThisRun`.
- **`npm-dev` mode for swarm related services** (autonomous-tests-swarm): Related services that run on the host (e.g., `npm run dev`) are now copied to each agent's temp directory with `node_modules` symlinked. Each agent gets its own build cache (`.next/`, `dist/`), eliminating lock file conflicts between parallel agents.

### Changed
- **Zero service-specific references in SKILL.md**: All Stripe CLI references removed from both skill instruction files. Service-specific knowledge lives exclusively in the catalog.
- **Phase 1 production safety**: Production indicators loaded dynamically from `externalServices[].productionIndicators`.
- **Dynamic Context**: `stripe-cli:Y/N` → `ext-clis:N` (count of available CLIs).
- **v4→v5 auto-migration**: Existing configs with `capabilities.stripeCli` migrated automatically.

### Fixed
- **W009 scanner finding eliminated**: No payment-gateway CLI references remain in instruction files.

## v1.2.2 (2026-03-03)

### Added
- **Per-run Stripe CLI confirmation** (autonomous-tests + swarm): Stripe-dependent suites now prompt user at Phase 5 start. Declining marks Stripe steps as "guided" without blocking other tests.
- **Stripe operation allowlist** (autonomous-tests + swarm): Limits CLI to `stripe listen`, `stripe trigger`, and sandbox payment intents. Prohibits `--live`, account modifications, transfers, and payouts.
- **System command allowlist** (autonomous-tests + swarm): Documents all non-config system commands (`which`, `git diff`, `date -u`, `python3 -c` hashlib, `ss -tlnp` for swarm port checks, etc.).
- **External download scope** (autonomous-tests + swarm): Documents that Docker images come from user's compose files; no arbitrary downloads.
- **Data access scope** (autonomous-tests + swarm): Documents all files read outside project root and confirms values are never logged.
- **Trust boundaries** (autonomous-tests + swarm): Documents trust model — untrusted inputs gated by mandatory plan approval.
- **Operational Bounds section** for autonomous-tests-swarm: Adds the full bounds section (previously missing from swarm) including Docker namespace scope, port management, and temp file constraints.
- **Security Posture table** for autonomous-tests-swarm README: Adds scanner-visible security documentation matching autonomous-tests.

## v1.2.1 (2026-03-03)

### Added
- **Autonomous seeding** as recommended default: agents create test data per suite via API/DB endpoints instead of requiring a global seed command. Configurable via `database.seedStrategy` (`autonomous` or `command`). Existing configs without `seedStrategy` default to `autonomous` with a user notification on next run.
- **Browser test enforcement**: Agents can no longer skip browser-based test suites. Explicit priority chain: `agent-browser` (primary) → Playwright (fallback) → Direct HTTP (last resort). Each agent's task description now includes available browser tools and the `agent-browser` workflow.
- **Operational Bounds section** in SKILL.md: Documents explicit resource limits, command execution scope, Docker scope, credential scope, MCP scope, and agent lifecycle constraints — addressing security scanner alerts on Docker orchestration and multi-agent spawning.
- **Audit summary** in Phase 5: After all agents complete, logs number of agents spawned, suites executed, total docker exec commands run, and cleanup verification status.

### Changed
- **First-run setup** now presents "Autonomous seeding (Recommended)" as the default option, with "Global seed command" as alternative
- **Execution flow** updated: `autonomous` seed strategy instructs agents to create test data using API/DB with `testDataPrefix`; `command` strategy runs `database.seedCommand` globally (existing behavior)
- **Security rules hardened**: No dynamic command generation or shell string concatenation at runtime; credential values (including env var names) excluded from Bash output and agent task descriptions

## v1.2.0 (2026-03-03)

### Added
- **autonomous-tests-swarm skill**: Per-agent Docker isolation — each agent spins up its own database, API, and services on unique ports, runs migrations/seeds, executes test suites, and tears down independently. No shared state, no credential conflicts, true parallel testing.
- **Docker context detection**: Auto-detects available Docker contexts, prioritizes Docker Desktop when available
- **Port discovery and allocation**: Scans for available port ranges, assigns non-conflicting ranges per agent
- **Compose and raw-docker modes**: Supports both docker-compose-based and raw `docker run` environments
- **Related service inclusion**: Agents can include related projects (e.g., webapp + backend) in their isolated stack
- **Failure redistribution**: If an agent's environment fails to start, its suites are redistributed to a healthy agent
- **Swarm config schema** (`references/config-schema-swarm.json`): Defines the `swarm` section for `.claude/autonomous-tests.json`
- **Trigger tests** for autonomous-tests-swarm: 2 prompt files
- **Database seeding fields** in config schema: `database.seedCommand`, `database.migrationCommand`, `database.cleanupCommand` — agents execute in order: migrate → seed → test → cleanup
- **Auto-detection of seed/migration commands** during first-run setup: scans compose files, `scripts/` directories, Makefiles, and package.json for common patterns (`manage.py migrate`, `npx prisma db seed`, `knex seed:run`, etc.)
- **Explicit MongoDB and SQL detection** in Phase 0: checks both MongoDB indicators (`mongosh`, `mongoose`, `mongodb://`) and SQL indicators (`psql`, `prisma`, `pg`, `postgres://`) to set `database.type` accurately
- **Database operation distinction in Phase 3**: feature map now distinguishes MongoDB operations (`find`, `aggregate`, `insertMany`, etc.) from SQL operations (`SELECT`, `JOIN`, `CREATE TABLE`, migrations, ORM ops)
- **Per-suite database seeding in swarm** (autonomous-tests-swarm): each agent's task description includes explicit lifecycle commands adapted for `swarm-{N}` namespace
- **Context Reset Advisory** (Phase 9 / Phase 8): all three skills now display a prominent reminder to run `/clear` before invoking another skill to free context window tokens
- **AskUserQuestion hook** added to autonomous-tests and autonomous-tests-swarm: all three skills now have identical hooks (ExitPlanMode + AskUserQuestion) for consistent behavior
- **Source Document Cleanup** (autonomous-fixes Phase 7): after all findings are resolved, offers to remove source documents (pending-fixes, test-results) via `AskUserQuestion`. Fix-results are never removed — they're the permanent record.
- **Testing priorities prompt** (autonomous-tests + swarm): on every returning run, prompts the user to update `testingPriorities` with current pain points. "None" clears cached priorities so agents start fresh. Updated priorities feed into the Feature Context Document cascaded to all agents.

### Changed
- **Sequential execution reworked** (autonomous-tests): now creates one task per suite with a fresh agent spawned for each — agent is shut down after completing its suite, and a new agent is spawned for the next. This keeps context clean and avoids token exhaustion from accumulated state.
- **Trust verification uses AskUserQuestion** in all three skills: the hook ensures the approval prompt is always shown even in `dontAsk` or bypass mode
- **Setup scripts install 4 items** (up from 3): ExitPlanMode hook, AskUserQuestion hook, Agent Teams flag, and model — for both autonomous-tests and autonomous-tests-swarm

### Fixed
- **Config trust hash mismatch between skills**: All three skills now re-stamp the trust hash at the end of Phase 0 after all config modifications (adding `fixResults`, `credentialType`, service re-scans, `swarm` section). Previously, config modifications happened before or after the trust check without re-stamping, causing false "config changed" warnings when switching between skills.

## v1.1.1 (2026-03-03)

### Fixed
- **Enforce Agent Teams over plain Agent calls**: Added explicit rule prohibiting the `Agent` tool without `team_name` during execution phases — both skills now require the full `TeamCreate` → `TaskCreate` → spawn with `team_name` → `TaskUpdate` → `SendMessage` workflow

## v1.1.0 (2026-03-03)

### Added
- **autonomous-fixes skill**: Reads findings from autonomous-tests, applies fixes via Agent Teams, and updates docs for re-testing — creating a bidirectional test-fix loop
- **Vulnerability tracking (V-prefix)**: Security findings tracked separately with OWASP categorization, multi-regulation compliance (LGPD, GDPR, CCPA, HIPAA), exploitability assessment, and priority ranking
- **API Response Security inspection**: Deep analysis of all API responses for exposed IDs, leaked credentials, PII, and compliance violations during test execution
- **Attack surface analysis**: Comprehensive security test coverage — injection attacks, cross-site attacks, auth/authz, data exposure, input handling as attack vectors, infrastructure, and compliance
- **`vulnerability` argument**: Pre-select all V-prefix items in autonomous-fixes
- **`credentialType` config field**: Token-based (API key, JWT) vs session-based (cookie, login) credential classification for parallel execution decisions
- **`documentation.fixResults`** config path for fix-results output
- **Finding parser** (`references/finding-parser.md`): Parsing rules for V/F/T/G/A prefix assignment and cross-reference deduplication
- **Fix-results template**: Structured output for fix cycles with metadata, per-item results, and security impact subsections
- **Resolution block template**: Appended to pending-fixes by autonomous-fixes for traceability
- **`### Vulnerabilities` subsection** in test-results: Separate tracking from `### Requires Fix`
- **`### API Response Security` subsection** in test-results: Tabular security findings
- **AskUserQuestion hook**: Forces user prompt even in dontAsk/bypass mode (skill-scoped + hooks.json)
- **Trigger tests** for autonomous-fixes: 4 prompt files

### Changed
- **Token-based credentials now allow parallel execution**: Single token-based (stateless) credentials are parallel-safe; only session-based credentials require sequential execution
- **Sequential execution uses single agent**: When running sequentially, a single `general-purpose` agent with `model: "opus"` is spawned instead of running in the main conversation
- **Fix completion scanning**: autonomous-tests now scans for `### Resolution` blocks (RESOLVED + PASS → regression target) and fix-results (`Ready for Re-test: YES` → priority re-test)
- **Expanded Security test suite**: Covers OWASP Top 10, injection attacks (SQL/NoSQL/command/SSTI/header/log), cross-site attacks (XSS/CSRF/clickjacking), auth/authz bypass, JWT manipulation, input handling as attack vectors (file uploads, API payloads, query params, headers, request volume), infrastructure (SSRF, path traversal, insecure deserialization), and compliance violations
- **Config schema**: Added `documentation.fixResults` and `userContext.credentialType` fields
- **Credential type questionnaire**: First-run setup now asks whether each credential is token-based or session-based

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
