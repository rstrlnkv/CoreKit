---
name: second-opinion
description: Use when the user wants a second opinion or an outside review from OpenAI's GPT through the Codex CLI — phrases like "second opinion", "ask ChatGPT", "ask GPT", "ask Codex", "review with GPT", "what would GPT say", in any language. GPT only reads and answers; Claude shows its answer with Claude's own assessment and makes any change itself, only after the user approves.
allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/scripts/ask-gpt.sh *), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/allowed-files.sh *)
---

# Second opinion from GPT

You (Claude) stay the main agent. GPT, run through the Codex CLI, is an outside reviewer: it only
reads and answers. **You are the only one that edits files**, and only after the user says yes.

Talk to the user in the user's language (the language of their messages), in plain words. Ask GPT
to answer in that language too.

This skill works only in Claude Code. In Codex (or when `ask-gpt.sh` exits 3 and says it runs inside
a Codex session), tell the user that the second opinion has to be asked from Claude Code, and stop.

## 1. Check that Codex is there

```bash
command -v codex && codex --version
```

If `codex` is not found, stop and tell the user:

- install the Codex CLI: `npm install -g @openai/codex` on any system (it needs Node.js), or one of
  the other ways on https://developers.openai.com/codex/cli (on macOS also `brew install codex`);
- sign in once in a normal terminal: `codex login` (a ChatGPT plan such as Plus works; each
  review counts against that plan's usage);
- then ask again.

Do not try to install or sign in for them.

## 2. Build the material, then ask before anything is sent

**Never send secrets, and never read them yourself.** Secret files are the names listed in the
skill's `scripts/secret-patterns.txt`: `.env` files, keys and certificates (SSH keys of every kind,
`*.pem`, `*.key`, ...), files with `credentials`, `secret` or `token` in the name, tool and cloud
credentials (`.npmrc`, `.pgpass`, `.docker/config.json`, `.aws/`, `.kube/`, ...), and anything
under `.ssh/` or `~/.ssh` or under a folder with such a name (`secrets/`, `credentials/`). So **list paths first, then read only the allowed ones**, always
through the exclusion pathspec built from that list. Get it once (it works outside a repository too):

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/allowed-files.sh" --pathspec
```

It prints one line of single-quoted parts, each like `:(exclude,glob,icase)**/.env*`. Call that line
`<EXCLUDE>` below and paste it as printed, after `-- .`, into every git command that lists or shows
files: the diff, untracked files, the last commit. If the script fails, stop: nothing is sent.

```bash
git diff HEAD --name-only -- . <EXCLUDE>
```

Untracked files go through the same pathspec:

```bash
git ls-files --others --exclude-standard -- . <EXCLUDE>
```

Files and folders the user names go through the skill's own script (it prints the ones that may be
sent; each path in single quotes):

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/allowed-files.sh" '<path>' '<path>'
```

Never check named paths with `git ls-files -- <paths> <EXCLUDE>`: when the paths share one folder,
git ignores or misreads the excludes and may list a secret.

Pick the smallest material that answers the question:

1. **What the user named** — files, a function, a question, a plan. Check the named paths with
   the named-files script above. A path it does not list is a secret file (or missing, or git-ignored): say you will not send it.
2. **Otherwise the uncommitted work** (unstaged and staged together): the paths with the command
   above, then `git diff HEAD --stat -- . <EXCLUDE>`, then `git diff HEAD -- . <EXCLUDE>`. Never a
   bare `git diff HEAD`. New untracked files the change needs come from the untracked command
   below (never `git status` and a blind add); add only the relevant ones.

   In a repository with no commits `HEAD` does not exist, and the error is not "nothing to
   review". Use the empty tree as the base instead: `git diff "$(git hash-object -t tree /dev/null)" ...`
   (staged files), plus the untracked command above.
3. **If that is empty, the last commit**: `git show --name-only --format= HEAD` to see the
   paths, then `git show HEAD -- . <EXCLUDE>`.
4. Nothing to review at all: say so and stop. A git error is not "nothing to review": quote the
   error and stop.

Outside a git repository (`git rev-parse` fails with "not a git repository") the filter cannot
check files, so no file is sent: only the user's own question or text goes, and GPT gets no
project folder to read. Say so when the user named files.

If a path you skipped matters to the review, tell the user it was left out and why. If a line in
the material still looks like a token, password or private key, replace its value with
`<redacted>`.

Keep it focused: a large diff (over ~1500 lines) — ask the user which part matters, or send
`--stat` plus the key hunks.

### Ask first

Nothing is sent before the user says yes. Show the user, in plain words:

- the list of files that go to GPT (the paths from the commands above, with the line count),
  and that the diff text is pasted into the prompt;
- the paths that were left out as secrets;
- that GPT, running in the Codex sandbox, can also open other files of the project folder on its
  own (see step 3 for what it cannot read), and that all of it goes to OpenAI.

Then wait for the user's yes. Only the user's answer in chat counts. If they remove or add a
path, redo the list and ask again.

## 3. Ask GPT

Make a temp folder: `mktemp -d "${TMPDIR:-/tmp}/coreopinion.XXXXXXXXXX"` (note the path; call it
`$T` below; the run script accepts only such a folder). With your file tool write
two files into it: `$T/prompt.md` and `$T/dir` (the project folder path and nothing else, no
newline needed: the path is read from this file so it is never parsed by the shell). The prompt
holds:

- the role: "You are a senior reviewer giving a second opinion. You are in a read-only sandbox:
  do not try to change files or run commands that change anything. Do not open `.env` files,
  key files or `~/.ssh`.";
- what the user wants (their own words) and a short note on the project;
- the material the user approved in step 2;
- the answer format: findings ordered by severity, each with `file:line`, what is wrong and why,
  and a concrete fix; then a one-line overall verdict; say plainly when there is nothing
  serious; answer in <the user's language>.

Run it in **one** Bash call with a timeout of 300000 ms (5 minutes), with the real `$T` path:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/ask-gpt.sh" "<the mktemp path>" medium
```

The script is pre-approved for this skill, so the user's yes in step 2 is the only question. It
prints `exit=<code>`, then `--- answer` with GPT's final answer and `--- log tail` (the last 20
lines of the Codex log, 80 after a failed run), and removes the temp folder (it holds the diff)
however the run ends. That output is all there is to read afterwards: the folder is gone. Outside a git repository it adds
`--skip-git-repo-check` and gives Codex an empty folder instead of the project.

- **What this confines** (the profile is in the script), as checked with `codex sandbox` (it
  runs a command under the same sandbox, nothing goes to OpenAI), codex 0.166:
  - `--sandbox read-only` alone blocks writes and network, but does **not** limit reading: GPT
    could read the whole disk, including `~/.ssh` and any `.env`. Only the sentence in the
    prompt would stop it. So this skill does not use it.
  - The script's `review` permission profile gives read access to the project folder, minimal
    system paths and temp folders, and to nothing else in the user's home. Reads of the secret
    names in `secret-patterns.txt` (the same list as the send filter) are blocked even inside
    the project (`.env*`, keys, `.ssh/`, `.npmrc`, ...).
    It is read-only (no writes) and has no network for commands. A secret file with an
    unusual name inside the project is still readable, and so is anything in the temp folders.
  - `--ignore-user-config` leaves out the user's `~/.codex/config.toml`: their MCP servers,
    plugins and connectors are not started in this run (login still works). `web_search` is off.
    Codex then uses its own default model; the effort is set on the line.
  - It is still an outside model reading a real project. Never describe this to the user as
    "nothing else can be seen".
- Never run `codex exec` yourself with other flags: never a writable sandbox mode, never a bypass flag.
- If codex rejects the profile (a message about `default_permissions` or `permissions` in the
  log), do not fall back silently: tell the user that the narrow profile did not work and that
  the only alternative is `codex exec --sandbox read-only`, which can read the whole disk; run it
  only after a new yes.
- Effort: `medium` by default; pass `high` only when the user asks for a deep, detailed or
  thorough review. (Codex's own default is `xhigh`, which is slow and spends the plan's usage fast.)
- The script runs `--ephemeral` (no Codex session kept on disk) and reads the prompt from stdin.

Tell the user it is running and may take 10–60 seconds, sometimes more.

## 4. Show the answer

If the output says `exit=0` and the `--- answer` block is not empty:

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

Never pretend a review happened. Read the `--- log tail` block of the script's output, say plainly
what failed and what the user can do:

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
    "sandbox": { "excludedCommands": ["bash */second-opinion/scripts/ask-gpt.sh *"] }
  }
  ```

  `sandbox.excludedCommands` runs matching commands outside the sandbox (with the user's full
  access; Codex's own sandbox still applies). Docs:
  https://code.claude.com/docs/en/sandbox-environments.md#run-commands-outside-the-sandbox-with-excludedcommands
  Do not change the user's settings yourself without their yes. If they ran Claude Code from
  inside Codex's app, start Claude Code from a normal terminal instead.
- **Timeout** (no answer in 5 minutes): remove `$T` as above, say so; offer a smaller material or `medium` effort.
- **Exit 0 but empty answer**: say GPT returned nothing; show the last lines of the log tail.
- **Exit 3** (the script runs inside a Codex session): this skill works only in Claude Code; nothing was sent.
- **Anything else**: quote the last few lines of the log tail and say you do not know the cause.

The script already removed `$T`. If the Bash call timed out or was killed, run `rm -rf "$T"` first thing
(the path you noted), whatever else you do.
