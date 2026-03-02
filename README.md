[![Release](https://img.shields.io/github/v/release/louiscavalcante/skills?include_prereleases&sort=semver)](https://github.com/louiscavalcante/skills/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

# Skills for Claude Code

Reusable, project-agnostic skills that extend Claude Code with specialized autonomous workflows.

## Available Skills

| Skill | Description | Model | Install |
|---|---|---|---|
| [autonomous-tests](autonomous-tests/) | Autonomous E2E test runner — analyzes diffs, generates test plans, and executes suites in parallel via Agent Teams | Opus 4.6 | `npx skills add louiscavalcante/skills --skill autonomous-tests` |

## Getting Started

### Using skills.sh (Recommended)

```bash
# Install the skill
npx skills add louiscavalcante/skills --skill autonomous-tests

# Run the setup script to configure required settings
bash ~/.claude/skills/louiscavalcante-skills/autonomous-tests/scripts/setup-hook.sh
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
