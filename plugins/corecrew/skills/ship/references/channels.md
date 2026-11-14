# Release channels

Ship reads section Scheme on every run (the **Channels** step of its Start). With one channel the rest of this
file does not apply. With several, each channel has its own branch, and this file says which
branch plays `<branch>` and `<main>` in the steps of SKILL.md.

## Scheme
1. The scheme is the user's, never ship's: the versioning standard Start read (`applies-to` names
   `release`) gives it when it names, for each channel, its name, its branch, its tag form and its
   build number, in order from the first channel (where work branches land) to the last (the
   release, marked Latest). Apply the standard's exceptions: a part it keeps to one channel ships
   with one channel.
2. The standard names no channels: run `git fetch origin` and `git branch -r`. A remote branch
   whose last path segment is one of these hints at a scheme nobody recorded:
   dev, develop, beta, staging, next, nightly, canary, stable, production, release.
   Name the branches found and ask the user once: are they release channels, and if so their
   order, each one's name and branch, its tag form and how its build number is made. No such
   branch, or the user says no: one channel.
3. An answer holds for this run only. Ship never writes a standard; the report suggests
   `/corecrew:new-standard` so the next run does not ask.
4. Every branch of the scheme must exist: `git rev-parse --verify --quiet "refs/remotes/origin/<b>"`
   (no `origin`: `refs/heads/<b>`). One missing: say the repo has not moved to this scheme yet,
   name the branch and stop; setting it up is not ship's work.

## Channel
1. The channel is the argument word that names one of the scheme's channels, in any case. A word
   that is no part, channel, level or version: stop and list the channels. No channel word: the
   first channel.
2. `<target>` is the channel's branch. What lands on it, `<source>`: on the first channel the
   current branch (a work branch); on a later channel a work branch cut from `<target>` (a fix:
   `git merge-base --is-ancestor <target> HEAD`), or else the previous channel's branch (moving
   the channel forward). Unclear which: ask.
3. A channel the standard keeps to fixes: compare the changelog of `<target>` and `<source>`
   (`git diff <target> <source> -- <changelog>`); added lines in a group the standard counts as a
   feature → stop and name them.

## Build
Every channel but the last. No release commit: the version and the changelog stay as they are.
1. In a clean checkout or worktree of `<source>` (the tree `<target>` becomes, since the merge only
   fast-forwards), run the `check:` command. Red: show it, push and tag nothing.
2. Land `<source>` on `<target>` as SKILL.md steps 3–6 do, with `<source>` as `<branch>` and
   `<target>` as `<main>`: the go-ahead, the branch push and CI, the merge with `--ff-only`, the push.
3. The version is the one the standard derives (for example from `## [Unreleased]`, or frozen on
   this channel). The build number comes from the standard's command on `<target>`'s tip. Read
   every build number in `git tag --list` (the scheme's tag forms): the new one must be greater
   than all of them, else stop and show both.
4. The tag and the release as SKILL.md step 7, on `<target>`, with the channel's tag form and
   `gh release create ... --prerelease`; the notes are `## [Unreleased]`, shaped as the release
   standard says.

## Last channel
The release itself. `<branch>` is the previous channel's branch and `<main>` the last channel's.
The current branch is not `<branch>`: on the user's yes run `git switch <branch>` (the tree is clean
from Start), then follow SKILL.md Steps 1–7: the release commit lands on `<branch>`, is pushed and
checked, and `<main>` moves to it with `--ff-only`. The tag has the last channel's form and the
release is marked Latest.

## Merge back
After a channel branch moved (a fix on a later channel, or the release commit), every earlier
channel branch must contain it. For each earlier branch `<e>`, nearest first, with `<l>` the branch
after it:
1. `git merge-base --is-ancestor <l> <e>` exits 0 → nothing to do.
2. Otherwise, on the user's yes, in a clean checkout or worktree of `<e>`: `git merge --no-edit <l>`.
   A conflict: name the files, run `git merge --abort`, give the user the merge command and stop.
   A changelog conflict is solved by keeping under `## [Unreleased]` only the lines the release did
   not take.
3. Run `check:` on the merged tree; red: stop, the merge stays local, say so. Green:
   `git push origin <e>`; rejected: stop and show the output.

## Report
After the lines of SKILL.md's report:
- `Channel: <name> (<target>)`
- `Build: <number>`
- `Merged back: <e> ← <l> (pushed | local only | conflict in <files>)`, one line each, or `Merged back: none`
- a scheme the user answered: suggest `/corecrew:new-standard` to record it.
