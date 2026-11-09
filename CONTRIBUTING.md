# Contributing

Thank you for helping. This page has the rules every change follows, how to run the tests, and how
a release is made. [ARCHITECTURE.md](ARCHITECTURE.md) explains how the repo is laid out.

## Requirements

- macOS or Linux with `bash`, `git` and the usual command-line tools. CI runs the suite on both
  (macOS with the system bash 3.2, and Ubuntu).
- Optional: the `claude` CLI and the `codex` CLI. Without them, the tests that need them print a
  `SKIP` line and the run names them after `ALL TESTS PASSED`. CI installs `claude` (the version is
  pinned in `.github/workflows/tests.yml`), so there those parts run, and a `SKIP` for lack of it
  fails the suite:
  - without `claude`: the coremodel module tests (`tests/test_coremodel.sh`) and the
    `claude plugin validate` checks (`tests/test_plugin_validate.sh`, and coreopinion's own);
  - without `codex`: the checks against the real Codex CLI (patch parsing, the sandbox profiles,
    plugin install, parts of the boundary and plugin-root tests).
- `python3`, `node` and `sips` (macOS) are used by a few checks when present (JSON syntax, icon
  size); the plugins never need them.

## Running the tests

```bash
bash tests/run.sh                 # every test file; prints ALL TESTS PASSED
bash tests/run.sh -j 4 guard      # 4 files at a time, only the files whose name contains "guard"
bash tests/test_hooks.sh          # one file
claude plugin validate .          # the marketplace
claude plugin validate plugins/corecrew   # one plugin; also plugins/coremodel, plugins/coreopinion
```

The full run takes about ten minutes on a laptop and needs no network; run one file while you work.
`-j N` runs N files at a time; one or more words after the options run only the files whose name
contains one of them. `VERBOSE=1` prints every file's output, not only a failing file's;
`KEEP_SANDBOX=1` keeps the run's temp folder and prints its path. Every test runs in a sandbox
made by `new_sandbox` in `tests/lib.sh`: its own `HOME`, XDG folders, git config, `CODEX_HOME` and
Core. A test never touches your real `~/.claude`, `~/.codex`, Core or global git config. Stub
`gh` on `PATH` instead of calling GitHub. The suite removes its sandboxes when it ends; folders
named `np-test.*` or `np-run.*` under the system temp folder are left over from older runs and can
be deleted by hand: `rm -rf "${TMPDIR:-/tmp}"/np-test.* "${TMPDIR:-/tmp}"/np-run.*`.

CI also runs [ShellCheck](https://www.shellcheck.net/) at `--severity=warning` on the shell files
of the plugins, the tests and `scripts/`. Run it on the files you changed before you push:
`shellcheck --severity=warning <files>` (settings: `.shellcheckrc`, `tests/.shellcheckrc`).

Trigger evals (does a skill start when it should) make real model calls and are not part of the
run: `claude plugin eval plugins/corecrew --ablation none --no-publish`.

## Rules for a change

- **Test first.** Write a failing test in `tests/`, watch it fail, then write the code. A bug fix
  starts with a test that reproduces the bug. For skill and agent texts, test their structure and
  contracts (front matter, sizes, paths that exist, names that match), not single phrases.
- **Portable bash.** Scripts must run on macOS bash 3.2 with BSD tools. Write to a temp file and
  `mv` it instead of editing in place. No `jq`: read JSON with `grep`, `sed` or `awk`. Quote paths;
  they may contain spaces. `tests/test_portability.sh` lists the forbidden constructs and enforces
  them; add a pattern there when you find a new one.
- **Never overwrite or delete the user's files.** Scripts that create files are idempotent and say
  `created` or `skipped`. A script that moves or deletes user files needs a test that a failed step
  leaves the files as they were.
- **Guards.** A guard or blocker needs a test that a legitimate action passes. Hooks are a
  best-effort second line; the host's permissions and sandbox are the boundary
  ([SECURITY.md](SECURITY.md#threat-model)). A rule meant for one host runs only on that host.
- **Nothing personal.** No absolute home paths, emails or names in tracked files;
  `tests/test_no_personal.sh` checks it.
- **English** in every file, comment and commit message. A README may have translations
  (`README.<code>.md`).

## Commits and pull requests

- Work on a branch, never on `main`.
- One commit per working step, in [Conventional Commits](https://www.conventionalcommits.org/)
  form with the plugin as scope: `fix(corecrew): ...`, `feat(coremodel): ...`, `docs: ...`. The
  subject is at most 72 characters; details go in the body. CI checks the subjects of the new commits
  with `scripts/commit-subjects.sh` (types: feat, fix, docs, style, refactor, perf, test, build, ci,
  chore, revert, merge; a lowercase scope or none). To get the same check at every commit, install
  it once as a `commit-msg` hook; this command leaves an existing hook alone:

  ```bash
  h="$(git rev-parse --git-path hooks)/commit-msg"; [ -e "$h" ] || { printf '#!/bin/sh\nexec bash "$(git rev-parse --show-toplevel)/scripts/commit-subjects.sh" --file "$1"\n' > "$h" && chmod +x "$h"; }
  ```

  Nothing installs it for you.
- Add a line for your change under `## [Unreleased]` in the plugin's CHANGELOG (`CHANGELOG.md` for
  corecrew, `plugins/<name>/CHANGELOG.md` for the others), in the group that fits: Added, Changed,
  Deprecated, Removed, Fixed or Security.
- Run `bash tests/run.sh` and `claude plugin validate` for the marketplace and the plugin you
  changed before you open a pull request.

## Releases

Each plugin has its own version, in all its manifests (`.claude-plugin/plugin.json` and, where it
exists, `.codex-plugin/plugin.json`), and its own CHANGELOG in
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) form.

1. Turn `## [Unreleased]` into `## [X.Y.Z] - YYYY-MM-DD` and add a new, empty `## [Unreleased]` above it.
2. Set the same version in every manifest of that plugin, in the same commit.
   `tests/test_manifest.sh` fails when they differ.
3. Check the plugin live in a git repo and in a fresh temp folder that is not one.
4. Merge and push, then tag the merged commit `<plugin>-vX.Y.Z` (for example `corecrew-v0.9.0`)
   and publish a GitHub release for that tag. `/corecrew:ship` does all of it: the merge and the
   push after your yes, the tag and the release after a second yes. Make them by hand only when you
   do not use it.
