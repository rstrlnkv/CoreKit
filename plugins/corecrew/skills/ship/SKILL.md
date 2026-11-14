---
name: ship
description: Release the current branch (version, changelog, tests on that tree, commit), push it and wait for its CI checks, merge it into the default branch and push, then tag it and publish a GitHub release, each after your go-ahead; follows the project's own release channels when it has them. Use /corecrew:ship [<part>] [<channel>] [patch|minor|major|<version>].
disable-model-invocation: true
argument-hint: "[<part>] [<channel>] [patch | minor | major | <version>]"
---

# Ship

## Overview
Ship takes a finished branch of a project's code repo to the repo's default branch on its remote: a version
with a changelog entry, the tests on that tree and one commit, a stop for the user's go-ahead, a push of the
branch and a wait for its CI checks (so a protected default branch accepts the release commit), a fast-forward
merge and a push, then, after a second yes, a tag and a GitHub release. The release commit itself is the
`release` path of the task skill. It never forces anything: no forced push, no rewritten history, no merge
commit made behind the user's back, no tag moved or deleted, no branch deleted.

Files this skill follows (open them with Read):
- `<plugin>/skills/task/SKILL.md` — sections Settings and Start
- `<plugin>/skills/task/references/paths.md` — section `release`
- `<plugin>/skills/task/references/release.md` — the release postconditions
- `<skill>/references/channels.md` — release channels (the **Channels** step of Start)

## Paths
This skill's folder is `${CLAUDE_SKILL_DIR}`; call it `<skill>`. Claude Code fills in that absolute
path before you read it. Codex leaves the text as written: then read `reference/codex-host.md` in the
plugin folder (two folders above the folder of the SKILL.md path Codex gave for this skill), find and
check `<skill>` as its section Skill folder says, and follow that file for the rest of this skill.
Then run `bash "<skill>/../../scripts/lib.sh" plugin-root`. It prints `<plugin>`, the absolute plugin
folder; `<scripts>` is `<plugin>/scripts`. Write every later command and every Read path with these
filled in as absolute paths. If the command fails, or you cannot give `<skill>` as an absolute path,
stop, tell the user the corecrew folder was not found, and do not guess a path.

## Language
Talk to the user in their language, in plain words. Everything on disk (version, changelog,
commit messages, tag messages, release notes) is English. Report labels (`Merged:`, `Version:`,
`Open:` ...) stay English.

## Settings
In Claude Code the settings arrive as the plugin options `${user_config.core_dir}` and
`${user_config.attribution}`; in Codex they live in the settings file (see Settings in the task
skill). A value that still reads literally `${user_config.` means the plugin is unconfigured: treat
it as unset. Resolve attribution with the `lib.sh settings` call in Start of the task skill; the
defaults are `core_dir` `~/Projects/Core`, `attribution` `allow`.

## Start
1. **Core.** Resolve `<Core>` to an absolute path and show it:
   `CORE_DIR='${user_config.core_dir}' bash "<scripts>/lib.sh" core-dir`.
   If that command prints a line on stderr, tell the user in plain words that their core_dir setting was ignored and why.
   Then follow these steps of Start in the task skill, with the same stops: Start, **Core** (set-up
   and its Prepare step), Start, **Project** (the code root), Start, **Read** (the `check:` line and
   the standards), Start, **Clean tree**, Start, **Wiki** (the baseline) and Start, **Base commits**.
2. **Default branch.** In the code root find the branch to ship into once, call it `<main>`, and use
   it everywhere below:
   - `git symbolic-ref --short refs/remotes/origin/HEAD` prints `origin/<name>`: `<main>` is `<name>`;
   - else (no remote, or its default is not known here) `git config init.defaultBranch`;
   - either way it must be a local branch: `git rev-parse --verify --quiet "refs/heads/<main>"`.
   Neither gives one: ask the user which branch to ship into, and check that one the same way.
3. **Branch.** `git rev-parse --abbrev-ref HEAD` is the branch. On a detached HEAD say there is no
   branch to ship and stop. The part to ship is the one step 1 picks. Its changelog has lines under
   `## [Unreleased]` (or the repo keeps no changelog and `git log --oneline <main>..HEAD` is not
   empty) → there is something to release; otherwise say so and stop. On `<main>`: say a release
   needs its own branch and, on the user's yes, run `git switch -c release/<part>` in the code root
   (one versioned part: `<part>` is the project's name), then go on there. A branch with nothing
   that `<main>` lacks goes on too: the release commit is what lands.
4. **Default branch moved.** `git merge-base --is-ancestor <main> HEAD`, exit 0 → go on. Otherwise
   `<main>` has commits the branch lacks: say so, and on the user's yes run `git merge <main>` in the
   code root (a conflict: stop and name the files). The tests below then run on the merged tree.
5. **Remote.** `git remote` lists `origin` → it is the push target. No `origin`: say the push and
   the GitHub release will be skipped, and go on.
6. **Channels.** Read section Scheme of `<skill>/references/channels.md` and follow it. One release
   channel: go on below. Several: follow that file, which says which branches play `<branch>` and
   `<main>` in the steps below.

## Steps
1. **Version and tag names.** The argument is `[<part>] [<level or version>]`; a first word that is not a level or a version
   is the `<part>`. The level picks the version: empty takes the level the versioning standard derives
   from the changelog (none: patch); `patch` raises the last number, `minor` the middle one (last becomes 0), `major` the first (the others become 0); an
   explicit `<version>` is used as given. Read the current version where the versioning standard in
   `<Core>/standards/` says it lives (a standard whose `applies-to` names `release`). No such
   standard: ask the user where the version lives and how it is written, before anything changes;
   this is the one place that asks, and the answer goes into the brief of step 2.
   A repo with several versioned parts (several packages or plugins) ships one part per run: the
   `<part>` the argument names. None named: list the parts whose changelog has lines under
   `## [Unreleased]` and ask which one; the others wait for their own run. The tag follows that
   standard; when it says nothing, a repo with one versioned part uses `v<version>`, and a repo
   with several uses `<part>-v<version>` (the part's name as its manifest gives it). A tag that already exists
   (`git rev-parse --verify --quiet "refs/tags/<tag>"` prints a hash, here or after
   `git fetch origin --tags`): stop and name it before anything changes.
2. **Release.** Run the `release` path of the task skill with that version:
   engineer writes the version and the changelog entry (the version answer of step 1 in its
   brief), then release.md postconditions 1–7 in order. The release commit subject is
   `chore(<part>): release <version>` in a repo with several versioned parts and
   `chore: release <version>` in a repo with one; a commit standard in `<Core>/standards/` wins. Postcondition 1 runs `check:`
   on the tree that has the new version, so the release commit itself is what was tested. A ✗ at
   postcondition 1 stops ship: show the output, name the uncommitted version and changelog files
   (`git status --short`), no repair, no merge; the user decides. Any other ✗ follows release.md;
   one that stops the chain stops ship too: report and do not merge.
3. **Go-ahead.** Show the user: the branch, the commits that will land on `<main>`
   (`git log --oneline <main>..HEAD`), the new version(s), the push target (or that there is no
   remote), that the tests passed on the tree that lands (the release commit; a channel build has
   none), that the branch will be pushed and its CI checks waited for first (step 4), and the
   tag(s) and GitHub release that step 7 will ask about after the push. Wait for the user's explicit yes in their own message. Anything else: stop here;
   the release commit stays on the branch.
4. **Branch push and CI.** With `origin`: `git push origin <branch>` (a new remote branch, or a
   fast-forward of one). A rejected push: stop, show the output, merge nothing; never retry with
   force. Then, when `gh` is on PATH and `git remote get-url origin` is a GitHub URL, wait for the
   CI checks on the pushed commit (`<sha>` from `git rev-parse HEAD`), so a default branch that
   requires them accepts the push of step 6:
   - find the run(s): `gh run list --commit <sha> --json databaseId,status,conclusion,name`; none
     yet → `sleep 10` and look again, up to 90 s in all (never a tight loop); still none → tell the
     user CI did not start and ask whether to merge without the check;
   - wait for each run: `gh run watch <id> --exit-status`;
   - every run ends in `success` → go on to step 5; any run ends in `failure`, `cancelled` or any
     other conclusion → stop, show the failed jobs (`gh run view <id> --json jobs`), merge nothing;
     the branch stays pushed, say so, and the user decides.
   Without `gh`, or not on GitHub: say the checks cannot be waited for here and ask the user to
   confirm the merge; only on their yes go on. No `origin`: skip this step.
5. **Merge.** Fast-forward only, so `<main>` gets exactly the branch's commits:
   - `<main>` is checked out in a worktree (`git worktree list --porcelain` shows
     `branch refs/heads/<main>`): there run `git -C "<that worktree>" status --short`; not empty →
     stop and name the files. Then `git -C "<that worktree>" merge --ff-only <branch>`.
   - otherwise: `git fetch . <branch>:<main>` (it refuses anything but a fast-forward).
   A refusal: stop, show it, change nothing more.
6. **Push.** With `origin`: `git push origin <main>`. A rejected push (the remote moved, a
   pre-push hook blocked it, or the default branch requires checks the branch push of step 4 did
   not run): stop and show the output; the local `<main>` keeps the merge, and the user decides.
   Never retry with force. The Core repo is not pushed by this skill.
7. **Tag and release.** Only after the push went through (no `origin`: offer the local tag alone).
   Ask, naming each tag: "Tag `<tag>` on `<main>` and publish a GitHub release with this version's
   changelog entry as its notes?" Only on the user's explicit yes in their own message:
   - for each tag: `git tag -a "<tag>" -m "<tag>" <main>`, then `git push origin "refs/tags/<tag>"`;
   - the GitHub release, when `git remote get-url origin` is a GitHub URL and `gh auth status`
     exits 0: `<title>` and the notes follow a standard in `<Core>/standards/` on GitHub releases
     (`applies-to` names `release`); none: the tag, and the version's changelog section (its heading
     line up to the next `## ` heading). Write the notes to a temp file from `mktemp`, then
     `gh release create "<tag>" --verify-tag --title "<title>" --notes-file "<that file>"`, and remove
     the file. Without `gh`, or not on GitHub: say the release was not made and why; the tag stays.
   A no: nothing is tagged; give the user the two commands above to run later. A failed tag push or
   release: stop and show the output. Never move, delete or force a tag.
8. **Report.**
   - `Pushed: origin/<branch> (CI: passed | not waited for — <why>)` or `Pushed: no — <why>`
   - `Merged: <short hash of <main>> (<branch> → <main>)` and `Pushed: origin/<main>` or `Pushed: no — <why>`
   - `Version: <old> → <new>` (with the part's name in a repo with several)
   - `Tag: <tag> (pushed | local only)` or `Tag: none — <why>`; `Release: <url gh printed>` or `Release: none — <why>`
   - `Open:` what is left: a skipped push, tag or release, Core commits not on its remote
     (`git -C "<Core>" status -sb`), release.md lines put under `Open`, or `none`. The branch
     stays: give the commands to delete it later, `git push origin --delete <branch>` and `git branch -d <branch>`.
   Then say how the user can check it (for example the release page, or the version on the remote's
   default branch).
