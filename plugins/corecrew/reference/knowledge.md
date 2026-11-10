# Knowledge format

Knowledge is what a project (or all of them) learned the hard way, kept as short lines an agent
reads before it works. It is not a wiki page and not a standard: it is the raw lesson.

## Two levels

| Level | File | Holds |
|---|---|---|
| This project | `<Core>/<project>/docs/knowledge/<role>.md` | every new lesson, by default |
| All projects | `<Core>/knowledge/<role>.md` | a lesson that recurred in another project, or one the user calls general |

`<role>` is an agent name: engineer, tester, security, verifier, localizer or designer.
Both folders are outside the wiki checks (`reference/wiki.md`). An agent reads the project
file first, then the all-projects file, and skips lines tagged with another stack.

## A role file

A title line `# <role> — <project>` (or `# <role> — all projects`), then one list: one `- ` line
per lesson, newest last. No sections, no size limit, no sub-files. A file in the older form, with
four sections and family links, is read as it is and never restructured.

## The line

`symptom → cause → guard address | no guard`

- symptom: what was seen, in the words of the failure.
- cause: why it happened, one clause.
- guard address: where the lesson is now enforced (a test path, a hook, a standard), or the
  words `no guard` when nothing checks it yet.
- An optional stack tag opens the line: `[swift] symptom → cause → guard`. A line with no tag
  holds for every stack.
- The arrow is `→`. A line a person wrote by hand with `->` reads the same; `task` writes `→`.

Example: `- [swift] build passes, app crashes on launch → entitlement missing in release config → tests/test_entitlements.sh`

## Who writes it

Only `/corecrew:task`, and only after the user's ok. An agent never edits these files; it ends
its reply with `Knowledge line: <symptom → cause → guard | none>`. `task` shows the line in plain
words, with its level and why, and asks ok / no. The line goes to the end of the file of the role
that proposed it:
- This project, by default.
- All projects when the lesson recurs: its cause already appears in another project's
  `docs/knowledge/<role>.md`. The earlier line stays where it is (a step commits only its own
  project folder and the shared Core files); the user may delete it by hand. The user may also
  choose all projects for a new lesson that is plainly general.
- Its cause is already in `<Core>/knowledge/`: the lesson keeps recurring. `task` writes it
  nowhere and offers to turn it into a standard with `/corecrew:new-standard` (pass the line).
