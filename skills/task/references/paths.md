# Paths

Choose one path per call and name it in your first line to the user. When the task does not
fit one path, say so and pick the closest; never mix two chains in one call. Briefs follow
`brief.md`; the final report follows `report.md`. Everywhere below, `check:` is the line in
`<Core>/<project>/CLAUDE.md`; a line that still reads `check: <set after scaffolding>` means
unset (or missing): ask the user once, before the first tester call that needs it (on `release`, before
postcondition 1; every path except `question`), and write the confirmed command into the `check:` line of that `CLAUDE.md`
so the next chain does not ask.

## fix
A defect in a known place.
1. `feature-dev:code-architect` only if more than one module is affected (needs feature-dev;
   see SKILL.md Start step 3). Otherwise skip.
2. tester: write a test that reproduces the defect and show it red (the failing output). Where
   no test can catch it (a screen, a recording), a screenshot or recording of the defect.
   A test that does not fail on the defect goes back.
3. engineer: the smallest change that fixes it.
4. tester: the same test, shown green after the fix; then 2–3 mutations of the fix (break it
   on purpose in a different way each time), each shown red, then reverted. A mutation that stays green means
   the test is hollow: it goes back to tester once.
5. Checkers' wave (below).
6. Release (`release.md`).

## full
A new capability or a behaviour change.
1. Ask the user 3–5 clarifying questions, one at a time, in plain words. Then show a short plan
   in plain words (what will change for the user, in how many tasks and which modules). Wait
   for "ok". Without feature-dev stop here and name the install command.
2. If the plan has more than 5 tasks or touches more than 3 modules: run only its first task
   as the whole chain (steps 3–6: architect to release, committed), then stop with the diff,
   the risk and an estimate, and wait for the user's go.
3. `feature-dev:code-architect`: the design for the plan.
4. engineer, then tester (touched modules only).
5. Checkers' wave (see the checkers' wave section). If it has findings, engineer repairs them
   in one pass and tester confirms, as that section says; none, go on.
6. Release (`release.md`).

## question
A question about the code or the project; no files change.
- `feature-dev:code-explorer` for how something works across files (needs feature-dev), or one
  corecrew role when the question is in its field (tester: how it is tested; security: what
  an input can reach; and so on).
- Proof is a `file:line` for every claim. An answer with no `file:line` goes back once.
- No files change, so no release. Only if the user accepts knowledge lines from the reply: write
  them and commit through `save`; the tree was clean at Start, so `save` commits only the chain's
  files (release.md postconditions 5–7); then `Commit:` is the
  hash. With no accepted lines there is no commit: `Commit: none — no files changed`.

## batch
Several changes of one shape (the same edit in many places, a rename, a version bump).
1. Check the list for file overlap: entries that touch the same file are handed back to the user
   as separate tasks; run only the rest. To find overlap, list the files each entry will touch
   (read the code or grep for the symbol) and hand back entries that share a file.
2. One chain: engineer → tester → verifier → release. One engineer, one tester; not one chain
   per entry. The verifier step is the checkers' wave with verifier only; its findings go to
   engineer as one repair, as that section says.
3. One full `check:` run at the end, as its own tester call; per entry, only its tests.
4. Report lists each entry in `Done` or `Open`.

## checkers' wave
After tester's pass on `fix` and `full`; the `batch` path calls verifier only. One message,
several foreground Agent calls:
- verifier: always.
- security: when deletion, permissions, running foreign code, updating or the network is touched.
- localizer: when user-visible text changes.
- designer: when what is drawn changes. If both localizer and designer apply, localizer goes
  first and designer after it (both build the artifact; never at the same time).

Each checker gets tester's report; designer also gets engineer's `Screens`. Collect all
findings and send them to engineer as one repair (the wave counts as one engineer pass). After
the repair, tester confirms, and each checker whose finding was repaired re-checks only that
place. A finding that engineer cannot repair goes to `Open`.

## release
`/corecrew:task release <version>`: the release procedure with a version and a changelog entry.
Read `references/release.md` (listed in SKILL.md) and follow it in full: every postcondition,
and postcondition 4 (version and changelog) applies on this path. Before postcondition 1 there
is one engineer call: it writes `<version>` and the changelog entry per the versioning standard
(ask the user first when there is none); more engineer calls only if a check fails. Nothing is
tagged or pushed.

## adopt
`/corecrew:task adopt <folder>`: bring an existing project into the Core layout.
Read `references/adopt.md` (listed in SKILL.md) and follow it. This path works outside
a project.
