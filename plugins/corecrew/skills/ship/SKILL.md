---
name: ship
description: Release the current branch (version, changelog, tests on that tree, commit), merge it into the default branch and push, then tag it and publish a GitHub release, each after your go-ahead. Use /corecrew:ship [patch|minor|major|<version>].
disable-model-invocation: true
argument-hint: "[patch | minor | major | <version>]"
---

# Ship

## Overview
Ship takes a finished branch of a project's code repo to the repo's default branch on its remote:
a version with a changelog entry, the tests on that tree and one commit, a stop for the user's go-ahead, a
fast-forward merge and a push, then, after a second yes, a tag and a GitHub release. The release
commit itself is the `release` path of the task skill; this skill adds the version choice, the
merge, the push, the tag and the GitHub release. It never forces anything: no forced push, no
rewritten history, no merge commit made behind the user's back, no tag moved or deleted.

Files of the task skill this skill follows (open them with Read):
- `<plugin>/skills/task/SKILL.md` — sections Settings and Start
- `<plugin>/skills/task/references/paths.md` — section `release`
- `<plugin>/skills/task/references/release.md` — the release postconditions

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
3. **Branch.** `git rev-parse --abbrev-ref HEAD` is the branch. On `<main>` (or on a detached HEAD)
   say there is no branch to ship and stop. Then `git log --oneline <main>..HEAD`: empty → say the
   branch has nothing that `<main>` lacks, and stop.
4. **Default branch moved.** `git merge-base --is-ancestor <main> HEAD`, exit 0 → go on. Otherwise
   `<main>` has commits the branch lacks: say so, and on the user's yes run `git merge <main>` in the
   code root (a conflict: stop and name the files). The tests below then run on the merged tree.
5. **Remote.** `git remote` lists `origin` → it is the push target. No `origin`: say the push and
   the GitHub release will be skipped, and go on.

## Steps
1. **Version and tag names.** The argument picks the version: empty or `patch` raises the last
   number, `minor` the middle one (last becomes 0), `major` the first (the others become 0); an
   explicit `<version>` is used as given. Read the current version where the versioning standard in
   `<Core>/standards/` says it lives (a standard whose `applies-to` names `release`). No such
   standard: ask the user where the version lives and how it is written, before anything changes;
   this is the one place that asks, and the answer goes into the brief of step 2.
   A repo with several versioned parts (several packages or plugins): raise each part the branch
   changed (`git diff --name-only <main>...HEAD`), each by the same rule, and list them.
   The tag of each new version follows that standard; when it says nothing, a repo with one
   versioned part uses `v<version>`, and a repo with several uses `<part>-v<version>` (the part's
   name as its manifest gives it). A tag that already exists
   (`git rev-parse --verify --quiet "refs/tags/<tag>"` prints a hash, here or after
   `git fetch origin --tags`): stop and name it before anything changes.
2. **Release.** Run the `release` path of the task skill with that version:
   engineer writes the version and the changelog entry (the version answer of step 1 in its
   brief), then release.md postconditions 1–7 in order. The release commit subject is
   `chore(<part>): release <version>` in a repo with several versioned parts (several raised at
   once: the first in the subject, all of them in the body) and `chore: release <version>` in a
   repo with one; a commit standard in `<Core>/standards/` wins. Postcondition 1 runs `check:`
   on the tree that has the new version, so the release commit itself is what was tested. A ✗ at
   postcondition 1 stops ship: show the output, name the uncommitted version and changelog files
   (`git status --short`), no repair, no merge; the user decides. Any other ✗ follows release.md;
   one that stops the chain stops ship too: report and do not merge.
3. **Go-ahead.** Show the user: the branch, the commits that will land on `<main>`
   (`git log --oneline <main>..HEAD`), the new version(s), the push target (or that there is no
   remote), that the tests passed on the release commit, and the tag(s) and GitHub release that step 6 will ask about after the push.
   Wait for the user's explicit yes in their own message. Anything else: stop here; the release commit stays
   on the branch.
4. **Merge.** Fast-forward only, so `<main>` gets exactly the branch's commits:
   - `<main>` is checked out in a worktree (`git worktree list --porcelain` shows
     `branch refs/heads/<main>`): there run `git -C "<that worktree>" status --short`; not empty →
     stop and name the files. Then `git -C "<that worktree>" merge --ff-only <branch>`.
   - otherwise: `git fetch . <branch>:<main>` (it refuses anything but a fast-forward).
   A refusal: stop, show it, change nothing more.
5. **Push.** With `origin`: `git push origin <main>`. A rejected push (the remote moved, or a
   pre-push hook blocked it): stop and show the output; the local `<main>` keeps the merge, and the
   user decides. Never retry with force. The Core repo is not pushed by this skill.
6. **Tag and release.** Only after the push went through (no `origin`: offer the local tag alone).
   Ask, naming each tag: "Tag `<tag>` on `<main>` and publish a GitHub release with this version's
   changelog entry as its notes?" Only on the user's explicit yes in their own message:
   - for each tag: `git tag -a "<tag>" -m "<tag>" <main>`, then `git push origin "refs/tags/<tag>"`;
   - the GitHub release, when `git remote get-url origin` is a GitHub URL and `gh auth status`
     exits 0: write the new version's changelog section (its heading line up to the next `## `
     heading) to a temp file from `mktemp`, then
     `gh release create "<tag>" --verify-tag --title "<tag>" --notes-file "<that file>"`, and remove
     the file. Without `gh`, or not on GitHub: say the release was not made and why; the tag stays.
   A no: nothing is tagged; give the user the two commands above to run later. A failed tag push or
   release: stop and show the output. Never move, delete or force a tag.
7. **Report.**
   - `Merged: <short hash of <main>> (<branch> → <main>)` and `Pushed: origin/<main>` or `Pushed: no — <why>`
   - `Version: <old> → <new>` (one line per versioned part)
   - `Tag: <tag> (pushed | local only)` or `Tag: none — <why>`; `Release: <url gh printed>` or `Release: none — <why>`
   - `Open:` what is left: a skipped push, tag or release, Core commits not on its remote
     (`git -C "<Core>" status -sb`), release.md lines put under `Open`, or `none`.
   Then say how the user can check it (for example the release page, or the version on the remote's
   default branch).
