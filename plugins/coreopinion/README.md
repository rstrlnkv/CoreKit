# coreopinion

A Claude Code plugin in the `corekit` marketplace. Its skill `second-opinion` lets Claude ask
OpenAI's GPT, through the Codex CLI, for a second opinion or a review, then shows you GPT's answer
next to Claude's own assessment: what Claude agrees with, what it disputes and why.

Claude stays the main agent and the only one that edits files. Nothing GPT suggests is applied
until you say yes; then Claude makes the change itself.

## Requirements

- The Codex CLI (`codex --version`), installed with `npm install -g @openai/codex` or
  `brew install codex`.
- Signed in with a ChatGPT plan (Plus or higher): run `codex login` once in a normal terminal;
  `codex login status` shows it. **Each review counts against that plan's Codex usage.**

## Install

```
/plugin marketplace add rstrlnkv/CoreKit
/plugin install coreopinion@corekit
```

It does not depend on `corecrew` or `coremodel`.

## Usage

- `/coreopinion:second-opinion` — reviews your uncommitted changes (`git diff HEAD`), or the last
  commit when there are none. You see the file list and confirm first.
- `/coreopinion:second-opinion the error handling in sync.sh` — reviews what you name.
- Or just say "get a second opinion from GPT", "ask ChatGPT about this plan", "review with GPT".
  Ask for a "deep" or "detailed" review to use a higher reasoning effort (slower, uses more of
  your plan).

An answer takes about 10–60 seconds, sometimes longer; Claude waits up to 5 minutes.

## What is sent, and what GPT can read

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

## If it fails

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
  read-only sandbox still applies). No allow rule is needed: the skill pre-approves its own run
  script, so your yes to the file list is the only question. See
  [Run commands outside the sandbox](https://code.claude.com/docs/en/sandbox-environments.md#run-commands-outside-the-sandbox-with-excludedcommands).
  Also do not start Claude Code from inside Codex's own app.
- **No answer in 5 minutes**: ask about a smaller piece.

## Later

The plugin name is neutral on purpose: other providers can be added as more skills.
