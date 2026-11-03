# Knowledge format

Knowledge is what a project (or all of them) learned the hard way, kept as short lines an agent
reads before it works. It is not a wiki page and not a standard: it is the raw lesson.
A lesson that keeps recurring becomes a standard through `/coredev:new-standard`.

## Two levels

| Level | File | Holds |
|---|---|---|
| This project | `<Core>/<project>/docs/knowledge/<role>.md` | lessons about this project |
| All projects | `<Core>/knowledge/<role>.md` | lessons that hold in any project |

`<role>` is an agent name: engineer, tester, security, verifier, localizer or designer.
Both folders are outside the wiki checks (`reference/wiki.md`). An agent reads the project
file first, then the all-projects file, and skips lines tagged with another stack.

## A role file (at most 80 lines)

Four sections, in this order:
1. `## How proof is made here` — the commands and checks that show the work is right.
2. `## Where things are` — paths and entry points an agent would otherwise search for.
3. `## What has broken here` — one line per case (the line form below), or a link to a family.
4. `## What you must not do here` — hard prohibitions, one line each.

## The case line

`symptom → cause → guard address | no guard`

- symptom: what was seen, in the words of the failure.
- cause: why it happened, one clause.
- guard address: where the lesson is now enforced (a test path, a hook, a standard), or the
  words `no guard` when nothing checks it yet.
- An optional stack tag opens the line: `[swift] symptom → cause → guard`. A line with no tag
  holds for every stack.

Example: `[swift] build passes, app crashes on launch → entitlement missing in release config → tests/test_entitlements.sh`

## Families

When a role file would pass 80 lines, cases of one kind move to `<role>/<Family>.md`
(a `.md` file named for the family, e.g. `engineer/Concurrency.md`), one case line per
line. The role file keeps a link line:

`- [Family](<role>/Family.md): symptom → cause`

## Who writes it

Only `/coredev:task`, and only after the user's ok. An agent never edits these files; it ends
its reply with `Knowledge line: <symptom → cause → guard | none>`; `task` shows it in plain
words and asks whether to keep it and at which level (this project or all projects). The line
goes into the file of the role that proposed it, in the right section; when that file would
pass 80 lines, `task` moves a family out.
