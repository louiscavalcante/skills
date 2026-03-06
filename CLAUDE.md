# Skills — Developer Guide

## Overview

This repo contains reusable, project-agnostic skills for Claude Code. Each skill is a self-contained directory with a `SKILL.md` (Claude-facing definition) and supporting files.

## Directory Structure

```
skills/
├── .gitignore
├── CLAUDE.md              ← You are here
├── CONTRIBUTING.md        ← How to contribute
├── LICENSE                ← MIT
├── README.md              ← User-facing docs
├── RELEASE-NOTES.md       ← Changelog (keep updated)
├── autonomous-tests/      ← Skill: autonomous E2E test runner
│   ├── README.md          ← Human-facing docs
│   ├── SKILL.md           ← Claude-facing skill definition
│   ├── references/        ← Config schema, templates
│   └── scripts/           ← Setup scripts
├── autonomous-fixes/      ← Skill: autonomous fix runner (test-fix loop)
│   ├── README.md          ← Human-facing docs
│   ├── SKILL.md           ← Claude-facing skill definition
│   ├── references/        ← Finding parser, templates
│   └── scripts/           ← Setup scripts
└── hooks/                 ← Discoverable hook configurations
    └── hooks.json
```

## Development Workflow

### Modifying a skill

1. Edit `<skill>/SKILL.md` for behavior changes
2. Edit `<skill>/README.md` for user-facing docs
3. Update `<skill>/references/` for schema or template changes
4. Update `RELEASE-NOTES.md` with changes under a new version heading

### Adding a new skill

1. Create a new directory: `<skill-name>/`
2. Add required files: `SKILL.md`, `README.md`
3. Add optional dirs: `references/`, `scripts/`
4. Update root `README.md` skills table

## Versioning

This project uses [Semantic Versioning](https://semver.org/):

- **PATCH** (1.0.x): Bug fixes, doc improvements, minor tweaks
- **MINOR** (1.x.0): New features, new skills, backward-compatible changes
- **MAJOR** (x.0.0): Breaking changes to skill interfaces or config schema

When releasing:

1. Update `RELEASE-NOTES.md` with the new version and changes
2. Commit with message: `Release vX.Y.Z`
3. Tag: `git tag -a vX.Y.Z -m "vX.Y.Z — <summary>"`
4. Push: `git push origin main --tags`

## Rules

- No secrets, API keys, or credentials in `.md` files — use env var references
- Keep this file under 150 lines
- Follow existing patterns when adding skills
- Always update RELEASE-NOTES.md when making changes
- Test trigger prompts before submitting new skills

---

### Architecture and Agent Responsibilities

- The **main agent** acts strictly as the **Orchestrator**.
- The Orchestrator must never execute operational work.
- Every phase of a skill must be executed by spawning an `Agent()`.
- All spawned agents must report their findings or results back to the Orchestrator.
- The Orchestrator is responsible only for synthesizing reports and generating the plan.

### Exploration Phase Rules

When a skill needs to explore information within its scope:

- It must spawn one or more `Explore()` agents.
- Each `Explore()` agent gathers findings and reports back to the Orchestrator.
- The Orchestrator consolidates findings and creates the plan.
- No exploration work should be done directly by the Orchestrator.

### Plan Mode and Context Reset

When the plan is accepted:

- The system context is cleared.
- The Orchestrator retains only what is explicitly written inside the plan.
- Therefore, all relevant discoveries, assumptions, constraints, and prior findings must be embedded at the beginning of the plan.
- The plan must contain sufficient context to prevent duplicated exploration or repeated actions after reset.

### Task Execution via Subagents

Once in plan execution mode:

- Tasks must be executed using **built-in subagents** via `Agent()`.
- Each skill integrates with subagents differently—respect those differences.

Subagent spawning rules per skill:

- **autonomous-tests** → Sequential. One foreground subagent at a time.
- **autonomous-fixes** → Sequential. One foreground subagent at a time.
- **autonomous-tests-swarm** → Parallel. Multiple background subagents (`run_in_background: true`).

Only **autonomous-tests-swarm** may run concurrent subagents. The other two operate one-by-one.

### Additional Constraints

- Maintain functional parity with the original skills.
- Remove duplicated phases or overlapping responsibilities.
- Ensure each phase has a single clear objective.
- Keep wording concise and execution-oriented.
- Ensure reporting hierarchy is always: Agent → Orchestrator → Plan.

The final skills should be structurally clean, operationally strict, and optimized for deterministic, efficient execution.
