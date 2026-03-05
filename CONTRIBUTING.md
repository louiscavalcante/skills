# Contributing

Thanks for your interest in contributing to Skills for Claude Code!

## Getting Started

1. Fork and clone the repo
2. Read `CLAUDE.md` for the development workflow
3. Explore `autonomous-tests/` as a reference skill

## Skill Structure

Every skill must include:

```
<skill-name>/
├── SKILL.md           ← Required: Claude-facing skill definition
├── README.md          ← Required: Human-facing documentation
├── references/        ← Optional: Schemas, templates, reference docs
└── scripts/           ← Optional: Setup scripts, hooks
```

- **SKILL.md**: Contains the frontmatter (name, description, allowed-tools, hooks) and the full prompt that Claude Code follows when the skill is invoked.
- **README.md**: Explains what the skill does, prerequisites, installation, usage, and troubleshooting for humans.

## Making Changes

1. Create a feature branch: `git checkout -b feat/your-change`
2. Make your changes following existing patterns
3. Update `RELEASE-NOTES.md` with your changes
4. Submit a pull request with a clear description

## Commit Conventions

Use descriptive commit messages that explain the "why":
- `Add <skill-name> skill: <what it does>`
- `Fix <skill-name>: <what was broken>`
- `Update <skill-name>: <what changed and why>`

## Versioning

Changes are versioned using [Semantic Versioning](https://semver.org/):

| Change Type | Version Bump | Example |
|---|---|---|
| Bug fix, doc tweak | PATCH (1.0.x) | Fix typo in SKILL.md |
| New feature, new skill | MINOR (1.x.0) | Add code-review skill |
| Breaking interface change | MAJOR (x.0.0) | Config schema v4 → v5 |

## Guidelines

- No secrets, API keys, or credentials in any `.md` file
- Keep skills project-agnostic — they should work in any repo
- Follow the patterns established by existing skills
- Include a setup script if the skill requires Claude Code settings changes
