---
name: ship
description: Release the current branch (tests, version, changelog, commit), then merge it into main and push, after your go-ahead. Use /corecrew:ship [patch|minor|major|<version>].
disable-model-invocation: true
argument-hint: "[patch | minor | major | <version>]"
---

# Ship

## Overview
Ship takes a finished branch of a project's code repo to `main` on its remote, in four steps:
tests, a version with a changelog entry and one commit, a stop for the user's go-ahead, then a
fast-forward merge into `main` and a push. The release itself is the `release` path of the task
skill; this skill adds the global git config check, the version choice, the merge and the push.
It never forces anything: no forced push, no rewritten history, no merge commit made behind the
user's back.

Files of the task skill this skill follows (open them with Read):
- `${CLAUDE_SKILL_DIR}/../task/SKILL.md` — sections Settings and Start
- `${CLAUDE_SKILL_DIR}/../task/references/paths.md` — section `release`
- `${CLAUDE_SKILL_DIR}/../task/references/release.md` — the release postconditions

## Language
Talk to the user in their language, in plain words. Everything on disk (version, changelog,
commit messages) is English. Report labels (`Merged:`, `Version:`, `Open:`) stay English.

## Settings
Settings arrive as `${user_config.core_dir}` and `${user_config.attribution}`.
A value that still reads literally `${user_config.` means the plugin is unconfigured: treat it as unset and use the
defaults: `core_dir` `~/Projects/Core`, `attribution` `allow`.

## Start
1. **Core.** Resolve `<Core>` to an absolute path and show it:
   `CORE_DIR='${user_config.core_dir}' bash "${CLAUDE_SKILL_DIR}/../../scripts/lib.sh" core-dir`.
   Then do steps 1, 2 and 4–6 of Start in the task skill (set-up, project and code root, the
   `check:` line and the standards, clean tree, base commits), with the same stops.
2. **Branch.** In the code root: `git rev-parse --abbrev-ref HEAD` is the branch. On `main`
   (or on a detached HEAD) say there is no branch to ship and stop. Then
   `git log --oneline main..HEAD`: empty → say the branch has nothing that `main` lacks, and stop.
3. **main moved.** `git merge-base --is-ancestor main HEAD`, exit 0 → go on. Otherwise `main` has
   commits the branch lacks: say so, and on the user's yes run `git merge main` in the code root
   (a conflict: stop and name the files). The tests below then run on the merged tree.
4. **Remote.** `git remote` lists `origin` → it is the push target. No `origin`: say the push
   will be skipped, and go on.

## Steps
1. **Tests and git config.** Save the global git config first:
   `git config --global --list > "<tmp>/gitconfig.before" 2>/dev/null` (`<tmp>` from `mktemp -d`;
   a missing global config gives an empty file). Run the `check:` command once from the code root
   (release.md postcondition 1, release path). A failing run: stop and show its output. Then
   `git config --global --list > "<tmp>/gitconfig.after" 2>/dev/null` and
   `diff "<tmp>/gitconfig.before" "<tmp>/gitconfig.after"`: any difference means the tests wrote
   into the user's own git config. Stop, show the diff, change nothing in that file (the user
   decides), and remove `<tmp>`.
2. **Version.** The argument picks the version: empty or `patch` raises the last number, `minor`
   the middle one (last becomes 0), `major` the first (the others become 0); an explicit
   `<version>` is used as given. Read the current version where the versioning standard in
   `<Core>/standards/` says it lives (a standard whose `applies-to` names `release`). No such
   standard: ask the user where the version lives and how it is written, before anything changes.
   A repo with several versioned parts (several packages or plugins): raise each part the branch
   changed (`git diff --name-only main...HEAD`), each by the same rule, and list them.
3. **Release.** Run the `release` path of the task skill with that version: engineer writes the
   version and the changelog entry, then release.md postconditions 2–7 (postcondition 1 is the
   run of step 1; do not run the suite again). A ✗ that release.md says stops the chain stops
   ship too: report and do not merge.
4. **Go-ahead.** Show the user: the branch, the commits that will land on `main`
   (`git log --oneline main..HEAD`), the new version(s), and the push target (or that there is no
   remote). Wait for the user's explicit yes in their own message. Anything else: stop here; the
   release commit stays on the branch.
5. **Merge.** Fast-forward only, so `main` gets exactly the branch's commits:
   - `main` is checked out in a worktree (`git worktree list --porcelain` shows
     `branch refs/heads/main`): there run `git -C "<that worktree>" status --short`; not empty →
     stop and name the files. Then `git -C "<that worktree>" merge --ff-only <branch>`.
   - otherwise: `git fetch . <branch>:main` (it refuses anything but a fast-forward).
   A refusal: stop, show it, change nothing more.
6. **Push.** With `origin`: `git push origin main`. A rejected push (the remote moved, or a
   pre-push hook blocked it): stop and show the output; the local `main` keeps the merge, and the
   user decides. Never retry with force. The Core repo is not pushed by this skill.
7. **Report.**
   - `Merged: <short hash of main> (<branch> → main)` and `Pushed: origin/main` or `Pushed: no — <why>`
   - `Version: <old> → <new>` (one line per versioned part)
   - `Open:` what is left: a skipped push, Core commits not on its remote
     (`git -C "<Core>" status -sb`), release.md lines put under `Open`, or `none`.
   Then say how the user can check it (for example the version on the remote's main branch).
