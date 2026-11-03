# Release

Run at the end of every chain that changed files, in the code root (the worktree, if the
chain runs in one). Seven postconditions, in order. Show each one as
`command → output → ✓/✗` in plain words; do not skip a line.

The base commits were recorded at Start: `git rev-parse HEAD` in the code root (`<code base>`)
and in `<Core>` (`<Core base>`). `<files>` is `git diff --name-only <code base>`, run in the
code root (code-relative paths).

**Question path with accepted knowledge lines:** only postconditions 5–7 (nothing else changed).

1. **Tests.** Run the `check:` command of `<Core>/<project>/CLAUDE.md` from the code root.
   Green → ✓. A line that reads `check: <set after scaffolding>`, or no line, is unset: ask the
   user once, write the confirmed command into the `check:` line (it is committed with the
   chain), then run it. Never run the placeholder.
2. **Checkers.** Every checker called in this chain (verifier, security, localizer, designer)
   has a clean final report: no open finding. None called (for example a `question` chain) → ✓.
3. **Wiki.** `bash "${CLAUDE_SKILL_DIR}/../../scripts/wiki-check.sh" <Core>/<project> --changed <files>
   <pages>`, where `<pages>` are the wiki pages changed in `<Core>/<project>/docs/`, as
   `../docs/<page>.md`. Silent exit 0 → ✓. Otherwise decide by the Core's schema:
   `CORE_DIR="<Core>" bash "${CLAUDE_SKILL_DIR}/../../scripts/lib.sh" get schema` against
   `CORE_DIR="<Core>" bash "${CLAUDE_SKILL_DIR}/../../scripts/lib.sh" schema`. The Core is
   old-schema when its number is lower than the plugin's. Then the problems are shown as
   warnings, listed under `Open`, and the release goes on. Otherwise a red wiki-check is ✗.
4. **Version and changelog** (release path only; other paths show "not a release"). Look for
   `<Core>/standards/versioning.md`, or any standard whose `applies-to` names `release`, and
   follow its rules for the version and the changelog entry. None found → ask the user. The
   engineer writes the change; you check it against the rule.
5. **Commit.** From the code root:
   `bash "${CLAUDE_SKILL_DIR}/../../scripts/save" "<message>"`. The message is English, says
   what and why. `save` commits the code and the project's Core docs as one step with one
   `Step-Id` trailer. Output `saved code` / `saved docs` → ✓; the hash goes to `Commit:`.
   `nothing to save` after a chain that changed files → ✗. This procedure never tags and
   never pushes: no `--push`.
6. **Attribution.** Read `${user_config.attribution}`; a value that still reads
   `${user_config.` means `allow`.
   Only with attribution=forbid: `git log --format=%B <range> | grep -icE 'co-authored-by|generated with'`
   with `<range>` = `<code base>..HEAD` in the code root, and the same in `<Core>`
   (`git -C <Core> log …`) with `<Core base>..HEAD`. Both print `0` → ✓.
   With `allow` show "skipped (attribution=allow)".
7. **Clean tree.** `git status --short` in the code root and in `<Core>/<project>/` (and in
   `<Core>` when knowledge lines were written to `<Core>/knowledge/`). Empty output → ✓.

## When a line is ✗
Stop at the first ✗. The finding goes to engineer as one repair, then tester confirms, then
rerun the failed postcondition and the ones after it. There is no second release cycle: if it
is still ✗, report `Commit: stopped — <why>` (the postcondition and its output). If the commit
is already made (6 or 7 failed), say so; do not rewrite it.
