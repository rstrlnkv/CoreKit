# CoreKit — Claude Code skills and templates

## Skills
- `skills/new-project/` — start a new project to one standard: interview, stack and architecture
  analysis, recorded decisions, skeleton with docs in the private `Core` repo and code in its own repo.

## Install (Claude Code on this Mac)
```bash
bash ~/Projects/CoreKit/install.sh
```
Copies every skill to `~/.claude/skills/`. Start a new Claude Code session afterwards.

**Cowork / claude.ai:** these do not read `~/.claude/skills/`
(https://code.claude.com/docs/en/skills). To use a skill there, zip its folder
(`cd skills && zip -r ~/Desktop/new-project.zip new-project`) and upload it as a skill in your
claude.ai account settings.

## Requirements
git, GitHub CLI (`brew install gh` + `gh auth login`); the stack's own tools are checked when needed.

## Tests
```bash
bash tests/run.sh
```

## Docs
- `docs/specs/` — design specs · `docs/plans/` — implementation plans
