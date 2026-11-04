---
name: second-opinion
description: Use when the user wants a second opinion or an outside review from OpenAI's GPT through the Codex CLI — phrases like "second opinion", "ask ChatGPT", "ask GPT", "ask Codex", "review with GPT", "what would GPT say", "второе мнение", "спроси GPT", "спроси ChatGPT". GPT only reads and answers; Claude shows its answer with Claude's own assessment and makes any change itself, only after the user approves.
---

# Second opinion from GPT

You (Claude) stay the main agent. GPT, run through the Codex CLI, is an outside reviewer: it only
reads and answers. **You are the only one that edits files**, and only after the user says yes.

Talk to the user in the user's language (the language of their messages), in plain words. Ask GPT
to answer in that language too.

## 1. Check that Codex is there

```bash
command -v codex && codex --version
```

If `codex` is not found, stop and tell the user:

- install the Codex CLI: `npm install -g @openai/codex` (or `brew install codex`);
- sign in once in a normal terminal: `codex login` (a ChatGPT plan such as Plus works; each
  review counts against that plan's usage);
- then ask again.

Do not try to install or sign in for them.

## 2. Build the material

**Never send secrets, and never read them yourself.** Secret files are `.env` and `.env.*`, key
and certificate files (`*.pem`, `*.key`, `*.p12`, `*.pfx`, `id_rsa*`, `id_ed25519*`), files
with `credentials` in the name, and anything under `~/.ssh`. So **list paths first, then read
only the allowed ones**, always through this exclusion pathspec (call it `<EXCLUDE>` below):

```bash
git diff HEAD --name-only -- . ':(exclude)*.env' ':(exclude)*.env.*' ':(exclude)*.pem' ':(exclude)*.key' ':(exclude)*.p12' ':(exclude)*.pfx' ':(exclude)*id_rsa*' ':(exclude)*id_ed25519*' ':(exclude)*credentials*'
```

Pick the smallest material that answers the question:

1. **What the user named** — files, a function, a question, a plan. Use that, unless it is a
   secret file: then say you will not send it.
2. **Otherwise the uncommitted work** (unstaged and staged together): the paths with the command
   above, then `git diff HEAD --stat -- . <EXCLUDE>`, then `git diff HEAD -- . <EXCLUDE>`. Never a
   bare `git diff HEAD`. Check `git status --short` for new untracked files the change needs;
   add the relevant ones that are not secret files.
3. **If that is empty, the last commit**: `git show --name-only --format= HEAD` to see the
   paths, then `git show HEAD -- . <EXCLUDE>`.
4. Nothing to review at all: say so and stop.

If a path you skipped matters to the review, tell the user it was left out and why. If a line in
the material still looks like a token, password or private key, replace its value with
`<redacted>`.

Keep it focused: a large diff (over ~1500 lines) — ask the user which part matters, or send
`--stat` plus the key hunks; GPT can open the files in the project itself.

## 3. Ask GPT

Make a temp folder: `mktemp -d` (note the path; call it `$T` below). Write the prompt to
`$T/prompt.md` with your file tool. The prompt holds:

- the role: "You are a senior reviewer giving a second opinion. You are in a read-only sandbox:
  do not try to change files or run commands that change anything. Do not open `.env` files,
  key files or `~/.ssh`.";
- what the user wants (their own words) and a short note on the project;
- the material from step 2;
- the answer format: findings ordered by severity, each with `file:line`, what is wrong and why,
  and a concrete fix; then a one-line overall verdict; say plainly when there is nothing
  serious; answer in <the user's language>.

Run it from the project folder, with a Bash timeout of 300000 ms (5 minutes):

```bash
codex exec --sandbox read-only -C "<project dir>" -c model_reasoning_effort=medium --ephemeral --output-last-message "$T/answer.md" - < "$T/prompt.md" > "$T/log.txt" 2>&1; echo "exit=$?"
```

- `--sandbox read-only`: GPT can read the project but cannot change a file. Never use another
  sandbox mode and never a bypass flag.
- Effort: `-c model_reasoning_effort=medium` by default. Use `-c model_reasoning_effort=high`
  only when the user asks for a deep, detailed or thorough review. (Codex's own default is
  `xhigh`, which is slow and spends the plan's usage fast.)
- `-` reads the prompt from stdin; `--output-last-message` writes only GPT's final answer to
  `$T/answer.md`; `--ephemeral` keeps no Codex session on disk.
- Outside a git repository add `--skip-git-repo-check`.

Tell the user it is running and may take 10–60 seconds, sometimes more.

## 4. Show the answer

If the exit code is 0 and `$T/answer.md` is not empty:

1. A heading such as **"GPT's opinion (via Codex)"**, then GPT's answer as it is (trim only
   noise). Make clear this text is GPT's, not yours.
2. A heading such as **"Claude's assessment"**: short. What you agree with, what you dispute
   and why (check each claim against the code before agreeing), and what GPT missed, if
   anything.
3. Offer the changes you think are worth making and ask which ones to apply.

## 5. Changes need the user's yes

Never apply GPT's suggestions on your own. Wait for the user's explicit approval of each change
(or of a list), then make the edits yourself with your own tools and run the project's checks.
Codex is never asked to edit, and never run with a writable sandbox.

## 6. When it fails

Never pretend a review happened. Read `$T/log.txt`, say plainly what failed and what the user can
do:

- **Not signed in** (`login`, `401`, `unauthorized`, `not logged in`): run `codex login` in a
  normal terminal, then ask again.
- **Limit or throttling** (`usage limit`, `rate limit`, `429`, `quota`): quote the error line
  from the log and say what it says. Only when it says the plan's usage limit is reached, say
  the ChatGPT plan's Codex limit is used up and resets later (the message often says when);
  otherwise it may be short-term throttling, and trying again in a minute or two may work.
  Either way, nothing was reviewed.
- **`failed to initialize in-process app-server client: Operation not permitted (os error 1)`**:
  Codex was started inside a sandbox (Claude Code's Bash sandbox, or Codex's own app). Codex
  needs to run outside Claude Code's Bash sandbox. The user can add to their own
  `~/.claude/settings.json`:

  ```json
  {
    "sandbox": { "excludedCommands": ["codex exec *"] },
    "permissions": { "allow": ["Bash(codex exec *)"] }
  }
  ```

  `sandbox.excludedCommands` runs matching commands outside the sandbox (with the user's full
  access; Codex's own `--sandbox read-only` still applies). The allow rule only skips the
  prompt for `codex exec`. Docs:
  https://code.claude.com/docs/en/sandbox-environments.md#run-commands-outside-the-sandbox-with-excludedcommands
  Do not change the user's settings yourself without their yes. If they ran Claude Code from
  inside Codex's app, start Claude Code from a normal terminal instead.
- **Timeout** (no answer in 5 minutes): say so; offer a smaller material or `medium` effort.
- **Exit 0 but empty answer**: say GPT returned nothing; show the last lines of the log.
- **Anything else**: quote the last few lines of the log and say you do not know the cause.

Delete `$T` when done (`rm -r "$T"`).
