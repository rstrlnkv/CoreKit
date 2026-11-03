# Release

Run at the end of every chain that changed files, in the code root (the worktree, if the
chain runs in one). Seven postconditions, in order. Show each one as
`command → output → ✓/✗` in plain words; do not skip a line.

The base commits were recorded at Start: `git rev-parse HEAD` in the code root (`<code base>`)
and in `<Core>` (`<Core base>`). The tree was clean at Start, so everything changed since is
this chain's work. `<files>` for the wiki check, run in the code root (code-relative paths):
`{ git diff --name-only <code base>; git ls-files --others --exclude-standard; }`.
`<pages>`, the changed wiki pages, from `<Core>/<project>/docs/` (rewrite the
`<project>/docs/` prefix to `../docs/`):
`{ git -C <Core> diff --name-only <Core base> -- <project>/docs; git -C <Core> ls-files --others --exclude-standard -- <project>/docs; }`.

**Question path with accepted knowledge lines:** only postconditions 5–7 (nothing else changed).

**Release path, before postcondition 1:** engineer writes the version (`<version>` from
`/coredev:task release <version>`) and the changelog entry, following
`<Core>/standards/versioning.md` or any standard whose `applies-to` names `release`. None
found → ask the user first, then brief engineer with the answer.

1. **Tests.** Chains with a tester: show the result of the final tester `check:` run (rule 7
   in SKILL.md); do not run the suite again. Release path (no tester): run the `check:`
   command of `<Core>/<project>/CLAUDE.md` once from the code root. A line that reads
   `check: <set after scaffolding>`, or no line, is unset: ask the user once, write the
   confirmed command into the `check:` line (it is committed with the chain), then run it.
   Never run the placeholder.
2. **Checkers.** Every checker called in this chain (verifier, security, localizer, designer)
   has a clean final report: no open finding. None called (for example a `question` chain) → ✓.
3. **Wiki.** `bash "${CLAUDE_SKILL_DIR}/../../scripts/wiki-check.sh" <Core>/<project> --changed <files> <pages>`.
   Silent exit 0 → ✓. Otherwise decide by the Core's schema:
   `CORE_DIR="<Core>" bash "${CLAUDE_SKILL_DIR}/../../scripts/lib.sh" get schema` against
   `CORE_DIR="<Core>" bash "${CLAUDE_SKILL_DIR}/../../scripts/lib.sh" schema`. The Core is
   old-schema when its number is lower than the plugin's. Then the problems are shown as
   warnings, listed under `Open`, and the release goes on. Otherwise a red wiki-check is ✗.
4. **Version and changelog** (release path only; other paths show "not a release"). Check
   that the version and the changelog entry written above follow that standard.
5. **Commit.** From the code root:
   `bash "${CLAUDE_SKILL_DIR}/../../scripts/save" "<message>"`. The message is English, says
   what and why. `save` commits the code and the Core files as one step with one `Step-Id`
   trailer. Output `saved code` / `saved docs` → ✓. `save` prints no hash: get it with
   `git log -1 --format='%h %s'` in the code root, or in `<Core>` when only docs were saved.
   `nothing to save` after a chain that changed files → ✗. This procedure never tags and
   never pushes: no `--push`.
6. **Attribution.** Read `${user_config.attribution}`; a value that still reads
   `${user_config.` means `allow`. In the code root, only with attribution=forbid:
   `git log --format=%B <range> | grep -icE 'co-authored-by|generated with'` (forbid only),
   with `<range>` = `<code base>..HEAD`. In `<Core>`, also only with forbid:
   `git -C <Core> log --format=%B <Core base>..HEAD -- <project>` (add `knowledge` when
   knowledge lines were written) piped to the same grep. Both print `0` → ✓.
   With `allow` show "skipped (attribution=allow)".
7. **Clean tree.** In the code root `git status --short`; in the Core
   `git -C <Core> status --short -- <project>` (add `knowledge` when knowledge lines were
   written). Both empty → ✓.

## When a line is ✗
- ✗ at 1–4: stop; the finding goes to engineer as one repair, tester confirms (on the release path: no tester; the rerun of 1 is the
  confirmation), then rerun from postcondition 1. There is no second release cycle: still ✗ → `Commit: stopped — <why>`.
- ✗ at 5 (`save` failed): stop; `Commit: stopped — <why>` with the output.
- ✗ at 6 or 7: the commit exists, so no repair. Report `Commit: <hash and message>` and put
  the ✗ (the postcondition and its output) in `Open`. Do not rewrite the commit.
