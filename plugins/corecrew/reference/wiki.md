# Wiki rules

A project's internal wiki is `<Core>/<project>/docs/`. Its map is `docs/INDEX.md`. An agent
reads `CLAUDE.md`, then the map, then the one page its task needs. A user standard
`<Core>/standards/wiki.md`, if present, wins over this file.

## The map

- `docs/INDEX.md` has one line per page: `- [Title](path.md) — what it is for.`
- It links exactly the wiki pages on disk: a new page gets a line, a deleted page loses it.

## Pages

- One subject per page. Folders are flat (`features/`, `decisions/`), one level deep.
- A page over about 8 KB needs `##` headings so a reader can jump to the part they need.
- Every page starts with front matter, all six fields:
  `title`, `description`, `status`, `files`, `related`, `updated`.
  - `files:` lists the code paths (relative to the code root) the page describes; a path ending in
    `/` stands for a folder. Write `files: []` when the page describes no code.
  - `related:` lists other pages. `updated:` is the date of the last content change.
- Headings are unique within a page.

## References

- Refer to another page as `docs/<page>.md § <exact heading>`. The heading is the `## ` line
  text, written exactly. It runs to the end of the line or to the closing backtick, so put the
  reference in backticks when prose follows it. One trailing `.` `,` `;` `:` or `)` is
  forgiven when the exact text is not a heading.
- Links are Markdown links relative to the file that holds them. A link with `#anchor` is
  checked for the file only.
- "See above", "this document" and "as mentioned" are defects. Name the page and heading.

## Content

- No history: git has it. No dated measurements.
- No number without the command that prints it.
- One home per fact: do not copy another page or `CLAUDE.md`; link to it.
- A new architectural decision is a new file `decisions/NNN-<slug>.md`.

## Who keeps it true

- engineer is the only author of wiki edits. When a change touches a code file, engineer updates
  every page whose `files:` lists it (content and `updated`), adds a map line for a new page
  and a decision file for a new decision.
- verifier runs `wiki-check.sh`; release refuses to commit while it is red.

## Not covered by the checks

`docs/knowledge/`, `docs/standards/` and `docs/superpowers/` are outside the wiki rules.

## Checking

`bash scripts/wiki-check.sh <project_dir> [--changed <path>...]` prints
`wiki-check: <file>: <problem>` for each failure and exits 1; silent and exit 0 when green.

| Problem | Meaning |
|---|---|
| `missing front matter field <f>` | a required field is absent or empty |
| `not in INDEX.md` / `INDEX.md links missing page` | map and disk disagree |
| `broken link` / `broken reference § <heading>` | the target file or heading does not exist |
| `unclosed front matter` | the opening `---` has no closing `---` |
| `duplicate heading` | the same `##` heading twice in one page |
| `page over 8 KB without ## headings` | add headings or split the page |
| `drift: <code path> changed, page not updated` | `--changed` lists a code file that a page's `files:` names, and the page is not among the changed files |

`--changed` takes paths relative to the code root (as `git diff --name-only` prints there). A
changed page is passed as the absolute `<Core>/<project>/docs/<page>.md` (`docs/<page>.md` and
`../docs/<page>.md` also work). Pages live in the Core repo, so list the changed ones there
(read-only) and prefix each with `<Core>/`:
`{ git -C <Core> diff --name-only HEAD -- <project>/docs; git -C <Core> ls-files --others --exclude-standard -- <project>/docs; }`.
