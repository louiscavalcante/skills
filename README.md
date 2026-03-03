[![Release](https://img.shields.io/github/v/release/louiscavalcante/skills?include_prereleases&sort=semver)](https://github.com/louiscavalcante/skills/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

# Skills for Claude Code

Reusable, project-agnostic skills that extend Claude Code with specialized autonomous workflows.

## Available Skills

| Skill | Description | Model | Install |
|---|---|---|---|
| [autonomous-tests](autonomous-tests/) | Autonomous E2E test runner — analyzes diffs, generates test plans, and executes suites in parallel via Agent Teams | Opus 4.6 | `npx skills add louiscavalcante/skills --skill autonomous-tests` |
| [autonomous-fixes](autonomous-fixes/) | Autonomous fix runner — reads test findings, applies fixes via Agent Teams, and updates docs for re-testing (test-fix loop) | Opus 4.6 | `npx skills add louiscavalcante/skills --skill autonomous-fixes` |
| [autonomous-tests-swarm](autonomous-tests-swarm/) | Autonomous E2E test runner with per-agent Docker isolation — each agent spins up its own database, API, and services on unique ports for true parallel testing | Opus 4.6 | `npx skills add louiscavalcante/skills --skill autonomous-tests-swarm` |

## Getting Started

### Using skills.sh (Recommended)

```bash
# Install skills
npx skills add louiscavalcante/skills --skill autonomous-tests
npx skills add louiscavalcante/skills --skill autonomous-fixes

# Run the setup script to configure required settings
bash ~/.claude/skills/louiscavalcante-skills/autonomous-tests/scripts/setup-hook.sh
# Or for autonomous-fixes (also configures AskUserQuestion hook):
bash ~/.claude/skills/louiscavalcante-skills/autonomous-fixes/scripts/setup-hook.sh
```

### Manual Installation

See the [autonomous-tests README](autonomous-tests/README.md#manual-install) for step-by-step manual setup.

## What Are Skills?

Skills are markdown-defined capabilities that teach Claude Code new workflows. They live in `~/.claude/skills/` and are invoked with slash commands (e.g., `/autonomous-tests`). Skills can orchestrate multi-step tasks, spawn agent teams, and produce structured output — all while keeping the human in the loop for approval.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on adding skills, commit conventions, and versioning.

## Changelog

See [RELEASE-NOTES.md](RELEASE-NOTES.md) for the full release history.

## License

[MIT](LICENSE)
