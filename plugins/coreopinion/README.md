# coreopinion

A Claude Code plugin that asks OpenAI's GPT, through the Codex CLI, for a second opinion or a review, and shows it next to Claude's own assessment.

![platform](https://img.shields.io/badge/platform-Claude%20Code%202.1.271%2B-lightgrey) ![release](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Frstrlnkv%2FCoreKit%2Fmain%2Fplugins%2Fcoreopinion%2F.claude-plugin%2Fplugin.json&query=%24.version&label=release) ![licence](https://img.shields.io/github/license/rstrlnkv/CoreKit)

## Install

```
/plugin marketplace add rstrlnkv/CoreKit
/plugin install coreopinion@corekit
```

It is in the `corekit` marketplace and does not depend on `corecrew` or `coremodel`. Update:
`claude plugin marketplace update corekit`, `claude plugin update coreopinion@corekit`, then restart Claude Code.

## Features

| Feature | What it does |
|---|---|
| `/coreopinion:second-opinion` | Reviews your uncommitted changes (`git diff HEAD`), or the last commit when there are none; you see the file list and confirm first |
| Review of what you name | `/coreopinion:second-opinion the error handling in sync.sh` reviews what you name |
| Plain-words trigger | Say "get a second opinion from GPT", "ask ChatGPT about this plan" or "review with GPT"; ask for a "deep" or "detailed" review for a higher reasoning effort (slower, uses more of your plan) |
| Claude stays in charge | Claude shows GPT's answer next to its own assessment: what it agrees with, what it disputes and why. Only Claude edits files, and only after your yes |
| Secret filter | Keys, `.env` files and other secret names never go to GPT (list below) |
| Narrow Codex profile | GPT's commands can read the project folder and minimal system paths, and cannot write |

An answer takes about 10–60 seconds, sometimes longer; Claude waits up to 5 minutes. The plugin
name is neutral on purpose: other providers can be added as more skills.

### What is sent, and what GPT can read

**Before anything is sent, Claude shows you the list of files** that go to GPT (and the paths left
out as secrets) and waits for your yes. The default material is your uncommitted diff plus new
untracked files; the diff text is pasted into the prompt and goes to OpenAI.

Claude never sends `.env` files, keys, certificates, `.npmrc`, `.netrc`, `.pypirc`,
`.git-credentials`, `*.tfvars`, `*.tfstate`, keystores, `kubeconfig`, `.aws/*`, service-account
JSON, or files with `credentials`, `secret` or `token` in the name. The same filter covers
untracked files and files you name.

**What the Codex sandbox really confines** (checked with `codex sandbox`, codex 0.166, which runs a
command under the same sandbox without contacting OpenAI):

- `codex exec --sandbox read-only` on its own blocks writes and network, but **does not limit
  reading**: GPT could read the whole disk, including `~/.ssh` and `.env` files. The only barrier
  would be a sentence in the prompt. The plugin therefore does not rely on it.
- The plugin runs Codex with a narrow permission profile instead: GPT's commands can read the
  project folder and minimal system paths, nothing else in your home folder, and cannot write.
  Files matching the secret patterns above are blocked even inside the project. A secret with an
  unusual name inside the project is still readable, and so are temp folders.
- `--ignore-user-config` keeps your `~/.codex/config.toml` out of the run: your Codex MCP servers,
  plugins and connectors are not started, and web search is off. Codex then uses its default model.
- Two agents editing the same files would step on each other, and an outside model's advice
  deserves a check before it lands, so only Claude edits, after your yes.

Reasoning effort is `medium` (`high` on request). Not verified end to end: the profile was tested
with `codex sandbox`, not with a real review request (that would send data to OpenAI).

### If it fails

Claude says what failed and never pretends a review happened:

- **Not signed in**: run `codex login` in a terminal.
- **Usage limit or throttling**: Claude quotes the error; a plan limit resets later, short throttling passes in a minute or two.
- **`Operation not permitted (os error 1)`**: Codex was started inside a sandbox. If you turned on
  Claude Code's Bash sandbox, let the skill's run script run outside it in your own
  `~/.claude/settings.json`:

  ```json
  {
    "sandbox": { "excludedCommands": ["bash */second-opinion/scripts/ask-gpt.sh *"] }
  }
  ```

  `sandbox.excludedCommands` runs matching commands outside Claude Code's sandbox (Codex's own
  permission profile still applies). No allow rule is needed: the skill pre-approves its own run
  script, so your yes to the file list is the only question. See
  [Run commands outside the sandbox](https://code.claude.com/docs/en/sandbox-environments.md#run-commands-outside-the-sandbox-with-excludedcommands).
  Also do not start Claude Code from inside Codex's own app.
- **No answer in 5 minutes**: ask about a smaller piece.

## Requirements

- **OS:** macOS or Linux, wherever the Codex CLI runs; the run script is portable bash.
- **Claude Code** 2.1.271 or newer (`claude --version`), as for corecrew: the skill's commands use
  `${CLAUDE_SKILL_DIR}`.
- **The Codex CLI** (`codex --version`), installed with `npm install -g @openai/codex` or
  `brew install codex`.
- **A ChatGPT plan** (Plus or higher): run `codex login` once in a normal terminal;
  `codex login status` shows it. **Each review counts against that plan's Codex usage.**
- **Network:** OpenAI, through the Codex CLI only, with the files you confirmed. The plugin makes no other network call.
- **Permissions:** Codex runs with a narrow read-only profile (see "What is sent" above). If you turned on Claude Code's Bash sandbox, the skill's run script has to be allowed outside it (see "If it fails").
- **Changes outside its own folder:** none that stay. The run script creates a temp folder with the prompt and removes it however the run ends. Your `~/.codex/config.toml` is not read and not changed.

## Build from source

```bash
bash tests/test_coreopinion.sh              # the manifest, the skill, its run script and docs
claude plugin validate plugins/coreopinion
claude plugin eval plugins/coreopinion --ablation none --no-publish   # trigger evals in plugins/coreopinion/evals/ (real model calls, not part of tests/run.sh)
```
The skill is `plugins/coreopinion/skills/second-opinion/`; the run script is `scripts/ask-gpt.sh` in it.

## Licence

MIT — see [LICENSE](../../LICENSE).
