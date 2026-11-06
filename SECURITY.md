# Security policy

## Supported versions

Only the latest released version of each plugin gets security fixes. The version is in the
plugin's manifest, `plugins/<name>/.claude-plugin/plugin.json`.

| Plugin | Supported version |
|---|---|
| `corecrew` | 0.7.1 (latest) |
| `coremodel` | 0.5.2 (latest) |
| `coreopinion` | 0.2.5 (latest) |

Update with `claude plugin marketplace update corekit`, then `claude plugin update <name>@corekit`.

## Reporting a vulnerability

Please do not open a public issue for a security problem. Report it privately through GitHub:
open https://github.com/rstrlnkv/CoreKit/security and choose **Report a vulnerability**.

Include:

- the plugin and its version (`claude plugin list`);
- your system and Claude Code version (`claude --version`);
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

## Scope

In scope: the plugins in this repository, their hooks and scripts (the secrets guard, the code
guard, the git hooks, `save`, `undo-step`, `adopt.sh`), and the files they send to a third party
(`coreopinion` to OpenAI). The secrets guard is a best-effort check, not a sandbox: bypasses of the
cases it documents in `README.md` are known limits, not vulnerabilities.
