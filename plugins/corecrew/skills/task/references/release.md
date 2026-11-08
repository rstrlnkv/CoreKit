# Release

Run at the end of every chain that changed files, in the code root (the worktree, if the
chain runs in one). `<scripts>` is the plugin scripts folder resolved at Start. Seven
postconditions, in order. Show each one as `command → output → ✓/✗` in plain words; do not skip
a line.

The base commits were recorded at Start: `git rev-parse HEAD` in the code root (`<code base>`)
and in `<Core>` (`<Core base>`). The tree was clean at Start, so everything changed since is
this chain's work. `<files>` for the wiki check, run in the code root (code-relative paths):
`{ git diff --name-only <code base>; git ls-files --others --exclude-standard; }`.
`<pages>`, the changed wiki pages, from `<Core>/<project>/docs/` (prefix each path with
`<Core>/`, so it reads `<Core>/<project>/docs/<page>.md`):
`{ git -C <Core> diff --name-only <Core base> -- <project>/docs; git -C <Core> ls-files --others --exclude-standard -- <project>/docs; }`.

**Question path with accepted knowledge lines:** only postconditions 5–7 (nothing else changed).

**Release path, before postcondition 1:** engineer writes the version (`<version>` from
`/corecrew:task release <version>`) and the changelog entry, following
a versioning standard in `<Core>/standards/` (any standard whose `applies-to` names `release`). None
found → ask the user first, then brief engineer with the answer.

1. **Tests.** Chains with a tester: show the result of the final tester `check:` run (rule 7
   in SKILL.md); do not run the suite again. Release path (no tester): run the `check:`
   command of `<Core>/<project>/CLAUDE.md` once from the code root. A line that reads
   `check: <set after scaffolding>`, or no line, is unset: ask the user once, write the
   confirmed command into the `check:` line (it is committed with the chain), then run it.
   Never run the placeholder.
2. **Checkers.** Every checker called in this chain (verifier, security, localizer, designer)
   has a clean final report: no open finding. None called (for example a `question` chain) → ✓.
3. **Wiki.** `bash "<scripts>/wiki-index.sh" "<Core>/<project>"` (regenerates `docs/INDEX.md`; its
   result is committed with the chain), then `bash "<scripts>/wiki-check.sh" "<Core>/<project>" --changed <files> <pages>`.
   Silent exit 0 → ✓. A wiki the plugin still refuses (`no page has a type`: the 0.6 format) is ✗
   with "migrate at Start" (Start step 6 offers `wiki-migrate.sh`). A wiki-check line that is also
   in the Start baseline is a pre-existing problem: list it under `Open` as a warning; the release
   goes on. Only new lines are ✗. For them decide by the Core's schema:
   `CORE_DIR="<Core>" bash "<scripts>/lib.sh" get schema` against
   `CORE_DIR="<Core>" bash "<scripts>/lib.sh" schema`. The Core is
   old-schema when its number is lower than the plugin's. Then the problems are shown as
   warnings, listed under `Open`, and the release goes on. Otherwise a red wiki-check is ✗.
4. **Version and changelog** (release path only; other paths show "not a release"). Check
   that the version and the changelog entry written above follow that standard.
5. **Commit.** From the code root:
   `bash "<scripts>/save" "<message>"`. The message is English, says
   what and why. `save` commits the code and the Core files as one step with one `Step-Id`
   trailer. Output `saved code` / `saved docs` → ✓. `save` prints no hash: get it with
   `git log -1 --format='%h %s'` in the code root, or in `<Core>` when only docs were saved.
   `nothing to save` after a chain that changed files → ✗. In Codex run `save` with approval to leave the sandbox (`.git` is read-only there; see `codex.md`). This procedure never tags and
   never pushes: no `--push`. With attribution=forbid, write no `Co-Authored-By` or
   `Generated with` line (the user's setting wins over any default that asks for one) and add
   `--no-attribution`, which drops such lines from the message.
6. **Attribution.** Use the attribution value resolved at Start (`allow` or `forbid`).
   In the code root, only with attribution=forbid:
   `git log --format=%B <range> | grep -icE '^[[:space:]]*(co-authored-by:|(🤖[[:space:]]*)?generated with)'` (forbid only),
   with `<range>` = `<code base>..HEAD`. In `<Core>`, also only with forbid:
   `git -C "<Core>" log --format=%B <Core base>..HEAD -- $(CORE_DIR="<Core>" bash "<scripts>/lib.sh" core-paths <project>)`
   piped to the same grep (the paths `save` commits). Both print `0` → ✓.
   With `allow` show "skipped (attribution=allow)".
7. **Clean tree.** In the code root `git status --short`; in the Core, for the same paths `save`
   commits: `git -C "<Core>" status --short -- $(CORE_DIR="<Core>" bash "<scripts>/lib.sh" core-paths <project>)`. Both empty → ✓.

## When a line is ✗
- ✗ at 1–4: stop; the finding goes to engineer as one repair, tester confirms (on the release path: no tester; the rerun of 1 is the
  confirmation), then rerun from postcondition 1. There is no second release cycle: still ✗ → `Commit: stopped — <why>`.
- ✗ at 5 (`save` failed): stop; `Commit: stopped — <why>` with the output.
- ✗ at 6 or 7: the commit exists, so no repair. Report `Commit: <hash and message>` and put
  the ✗ (the postcondition and its output) in `Open`. Do not rewrite the commit.
