# Security policy

## Supported versions

Only the latest release of each plugin gets security fixes. Each plugin's version is in its
manifests (`plugins/<name>/.claude-plugin/plugin.json`, and `.codex-plugin/plugin.json` where the
plugin has one) and in the first `## [X.Y.Z]` heading of its CHANGELOG, below `## [Unreleased]`.

To see the version you run:

- Claude Code: `claude plugin list`.
- Codex: `codex plugin list`.

To update:

- Claude Code: `claude plugin marketplace update corekit`, then `claude plugin update <name>@corekit`.
- Codex: `codex plugin marketplace upgrade corekit`, then trust the hooks again in `/hooks`.

## Reporting a vulnerability

Please do not open a public issue for a security problem. Report it privately through GitHub:
open https://github.com/rstrlnkv/CoreKit/security and choose **Report a vulnerability**.

Include:

- the plugin and its version;
- your system and host version (`claude --version` or `codex --version`);
- what you did, what you expected and what happened, with the smallest steps that reproduce it;
- what an attacker could gain (for example, a secret read, a file written outside the project, a
  commit that leaks private files);
- any fix you suggest.

Do not include real secrets in the report.

## What to expect

- A first answer within about a week.
- A fix in a new release of the affected plugin, with a note in its changelog; you are credited
  there if you wish.
- A short report back to you if the issue turns out not to be a vulnerability, with the reason.

## Threat model

The plugins defend against **honest mistakes**, not against an attacker:

- an internal file (agent instructions, the private wiki, `.claude/`) written into or committed to
  a code repo that may be public;
- a secret file (`.env`, `~/.ssh`) read into the model's context or sent to another model.

They do not defend against a hostile prompt, or an agent that tries to get around them.

```
  the boundary        your host: Claude Code permission rules and sandbox,
                      the Codex sandbox and permission profile, GitHub (private Core repo)
        │
  the second line     corecrew hooks (code guard, secrets guard) and git hooks
                      (pre-commit, pre-push): they catch common accidents cheaply
        │
  the backstop        the git hooks check what reaches history and a push
```

The host is the boundary. The hooks are a best-effort second line. A bypass that needs a deliberate
trick is a known limit, not a vulnerability. A guard that blocks everyday legitimate work is a bug.

### Recommended host settings

**Claude Code.** Add deny rules to your settings (`~/.claude/settings.json`, or a project's
`.claude/settings.json`):

```json
{
  "permissions": {
    "deny": [
      "Read(**/.env)",
      "Read(**/.env.*)",
      "Read(~/.ssh/**)"
    ]
  }
}
```

These rules cover Claude's own file tools. Turn on Claude Code's sandbox (`/sandbox`) to apply them
to Bash commands as well. A deny rule wins over an allow rule, so `Read(**/.env.*)` also hides
`.env.example`; list the exact names instead if you need that file.

**Codex.** corecrew prints a permission profile that keeps `.env*`, keys, credentials and `~/.ssh`
unreadable: run `bash <plugin folder>/scripts/lib.sh codex-profile` and paste the output into
`~/.codex/config.toml`. corecrew never writes that file. The profile is a default, not a hard
boundary. These switch it off: `--sandbox`, `--dangerously-bypass-approvals-and-sandbox` or
`-c sandbox_mode=...` on the command line, `sandbox_mode` in any config layer (a profile, the
system config), and the `.codex/config.toml` of a trusted project (a cloned repository can bring
one). It does not cover git history (`git show HEAD:.env`).

### Known limits of the hooks

- The secrets guard is active only inside a Core project. It reads the command line, not the
  programs it starts. It does not see: recursive search (`grep -r SECRET .`, `rg --hidden`), a
  renamed or linked copy (`ln -s .env x; cat x`), interpreters (`python -c`, `node -e`),
  `find -exec`, `git show REV:.env`, `dd` and `curl -F @.env`.
- In Codex, file reads go through the shell: Codex fires no hook for read, search or list tools.
- Codex runs a plugin's hooks only after you trust them in `/hooks`, and again after each update.
- The code guard catches the usual ways to write `CLAUDE.md`, `AGENTS.md`, `docs/` or `.claude/`
  into a code folder: the file tools, and the common write commands in Bash. It does not follow: a
  command line given to `bash -c`, `sh -c` or `eval`, or a script file; a target with a variable, a
  glob, braces or `$(...)`; `xargs` and `find -exec`; a relative target after `cd`, `pushd` or
  `popd`; interpreters (`python -c`, `node -e`); `git -C <dir> mv`; other writers (`rsync`,
  `dd of=`, `tar -C`, `curl -o`). The git pre-commit and pre-push hooks check what is committed
  and pushed.
- Codex subagents cannot be made read-only: the read-only steps of `/corecrew:task` are checked
  (the working tree before and after), not enforced.

## Data that leaves your machine

- **corecrew** talks to GitHub through `gh` and `git`. Read-only checks run without a prompt (in Codex,
  whose sandbox has no network, every network call asks first):
  `new-project` checks that `gh` is logged in and that the project name is free on GitHub,
  `/corecrew:ship` fetches tags from `origin` to check for a clash, and the Core pre-push hook asks
  `api.github.com` whether the Core repo is private. Writes happen only after your yes: each repo
  creation, each push, and the tag and GitHub release of `/corecrew:ship`.
- **coremodel**, in Claude Code, sends each prompt you type to a short classifier call through your
  own Claude Code account, to pick the model and effort. In Codex, while its hint is on, it sends each
  prompt a second time to OpenAI through `codex exec`. [plugins/coremodel/README.md](plugins/coremodel/README.md)
  says how to turn the hint on or off.
- **coreopinion** (Claude Code only) sends the files you confirm, and your question, to OpenAI
  through the Codex CLI. Secret-looking files are filtered out of the list, and a read-only
  permission profile keeps GPT away from them.

## Scope

In scope: the plugins in this repository, their hooks and scripts (the secrets guard, the code
guard, the git hooks, `save`, `undo-step`, `adopt.sh`), the Codex profile they print, and what they
send to a third party (coremodel's Codex hint and coreopinion to OpenAI). Out of scope: the limits
listed above, and the hosts themselves (Claude Code, Codex, GitHub).
