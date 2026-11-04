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

It does not depend on `corecrew` or `coreeffort`.

## Usage

- `/coreopinion:second-opinion` — reviews your uncommitted changes (`git diff HEAD`), or the last
  commit when there are none.
- `/coreopinion:second-opinion the error handling in sync.sh` — reviews what you name.
- Or just say "get a second opinion from GPT", "ask ChatGPT about this plan", "review with GPT".
  Ask for a "deep" or "detailed" review to use a higher reasoning effort (slower, uses more of
  your plan).

An answer takes about 10–60 seconds, sometimes longer; Claude waits up to 5 minutes.

## Read-only by design

Codex runs as `codex exec --sandbox read-only` with reasoning effort `medium` (`high` on
request). In that sandbox GPT can read the project but cannot change a file or run a command
that changes anything. Two agents editing the same files would step on each other, and an outside
model's advice deserves a check before it lands, so only Claude edits, after your yes.

Claude never sends `.env` files, keys or `~/.ssh` in the material. Read-only still means GPT can
*read* files in the project folder; it is told not to open secrets, but that is an instruction,
not a lock.

## If it fails

Claude says what failed and never pretends a review happened:

- **Not signed in**: run `codex login` in a terminal.
- **Usage limit or throttling**: Claude quotes the error; a plan limit resets later, short throttling passes in a minute or two.
- **`Operation not permitted (os error 1)`**: Codex was started inside a sandbox. If you turned on
  Claude Code's Bash sandbox, let `codex exec` run outside it in your own
  `~/.claude/settings.json`:

  ```json
  {
    "sandbox": { "excludedCommands": ["codex exec *"] },
    "permissions": { "allow": ["Bash(codex exec *)"] }
  }
  ```

  `sandbox.excludedCommands` runs matching commands outside Claude Code's sandbox (Codex's own
  read-only sandbox still applies); the allow rule only skips the permission prompt for
  `codex exec`. See
  [Run commands outside the sandbox](https://code.claude.com/docs/en/sandbox-environments.md#run-commands-outside-the-sandbox-with-excludedcommands).
  Also do not start Claude Code from inside Codex's own app.
- **No answer in 5 minutes**: ask about a smaller piece.

## Later

The plugin name is neutral on purpose: other providers can be added as more skills.
