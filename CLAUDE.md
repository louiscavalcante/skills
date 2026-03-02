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
├── hooks/                 ← Discoverable hook configurations
│   └── hooks.json
└── tests/                 ← Skill-triggering tests
    └── skill-triggering/
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
5. Add trigger tests in `tests/skill-triggering/`

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

## Testing

Run skill-triggering tests (requires Claude Code CLI):

```bash
bash tests/skill-triggering/run-all.sh
```

These tests verify that natural language prompts correctly trigger the intended skill.

## Rules

- No secrets, API keys, or credentials in `.md` files — use env var references
- Keep this file under 150 lines
- Follow existing patterns when adding skills
- Always update RELEASE-NOTES.md when making changes
- Test trigger prompts before submitting new skills
