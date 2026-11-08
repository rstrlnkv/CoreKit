# Wiki rules

A project's wiki is `<Core>/<project>/docs/`, one Obsidian vault per project. An agent reads
`CLAUDE.md`, then the map `docs/INDEX.md`, then the one page its task needs. A user standard `<Core>/standards/wiki.md` wins over this file.

## Pages

- A page is every `docs/**/*.md` except `INDEX.md` and `knowledge/`, `standards/`, `superpowers/`,
  `.obsidian/`. Its name is the file name without `.md`; names are unique within a project.
- One subject per page. Folders are flat (`features/`, `decisions/`, `specs/`, `plans/`).
- A page over about 8 KB needs `##` headings; `##` headings are unique within a page.
- No history (git has it), no number without the command that prints it. One home per fact:
  link, do not copy. A new decision is a new file `decisions/NNN-<slug>.md`.

## Front matter

Every page starts with all six fields, in this order; these six are all, any other field is an error (put state in the body; the brief keeps `## Progress`): `type`, `status`, `description`, `files`, `related`, `updated`.

- `type`: `brief`, `architecture`, `decision`, `feature`, `spec`, `plan` or `glossary`.
- `status`: `draft`, `active`, `done` or `superseded`.
- `description`: one line, at most 80 characters (surrounding quotes do not count).
- `files`: code paths relative to the code root; a path ending in `/` is a folder; `[]` for none.
- `related`: other pages as `[[name]]` links; `[]` for none.
- `updated`: `YYYY-MM-DD`, the last content change.

## Links

- Link to a page with a wikilink: `[[name]]`, `[[folder/name]]`, `[[name#Heading]]` (exact heading
  text, `#` to `######`), `[[name|alias]]`, `[[name#Heading|alias]]`; `![[name]]` embeds.
- A target with an extension other than `.md` names a file under `docs/`.
- Wikilinks in code fences and `inline code` are not links. A Markdown link `[text](path)` is for
  URLs and files outside the wiki and must resolve; to a wiki page it is a defect.

## The map and Obsidian

`docs/INDEX.md` is generated: run `bash scripts/wiki-index.sh <project_dir>` after adding,
renaming, deleting or re-describing a page; never edit it. It groups pages by `type`, one line
each: `[[name]] description`. Pages with status `done` or `superseded` are counted in a
`history:` line. With `--check` it writes nothing and prints `wiki-index: stale` when out of date.
`docs/wiki.base` (a table of pages by field) and `docs/.obsidian/` come from `new-project` or
`wiki-migrate.sh`; the scripts print `created` or `skipped` and never overwrite them.

## Who keeps it true

- engineer is the only author of wiki edits. When a change touches a code file, engineer updates
  every page whose `files:` lists it (content and `updated`), writes a decision file for a new
  decision, then runs `wiki-index.sh`.
- verifier runs `wiki-check.sh`; release runs `wiki-index.sh`, then `wiki-check.sh`, and refuses
  to commit while it is red. `docs/knowledge/` and `docs/standards/` are outside these rules.

## Old wikis

`wiki-index.sh` refuses a wiki from an older corecrew with `no page has a type`; `wiki-migrate.sh`
converts it, and `/corecrew:task` offers that at Start. The steps are in `older-formats.md` beside this
file, section Wiki without types.

## Checking

`bash scripts/wiki-check.sh <project_dir> [--changed <path>...]` prints
`wiki-check: <file>: <problem>` (`<file>` relative to `docs/`) per failure and exits 1; silent and 0 when green.

| Problem | Meaning |
|---|---|
| `missing front matter field <f>` | a field is absent, or `type`, `status`, `description`, `updated` is empty |
| `unknown front matter field <f>` | a key beyond the six; move it into the body or delete it |
| `bad type: <v>`, `bad status: <v>`, `bad updated: <v>` | the value is not in the lists above, or not `YYYY-MM-DD` |
| `description over 80 chars`, `description not one line` | longer without surrounding quotes; a `>` or `\|` block |
| `duplicate page name <name>` | a later page has a taken name |
| `broken wikilink [[<target>]]`, `related is not a wikilink: <item>` | no such page, file or heading; a `related` item is not `[[...]]` |
| `use a wikilink: <target>`, `broken link <target>` | a Markdown link points to a wiki page, or to a missing file |
| `unclosed front matter`, `duplicate heading <h>` | no closing `---`; the same `##` heading twice in a page |
| `page over 8 KB without ## headings` | add headings or split the page |
| `INDEX.md stale` | `wiki-index.sh --check` fails: run `wiki-index.sh` |
| `drift: <code path> changed, page not updated` | `--changed` names a code file a page's `files:` lists, page not changed |

Also `wiki-check: INDEX.md: missing` (other checks still run) and `wiki-check: docs: missing docs/ directory` (nothing else is checked).
`--changed` takes code-root-relative paths (as `git diff --name-only` prints there). A changed page
is the absolute `<Core>/<project>/docs/<page>.md`. List the changed pages in the Core (read-only):
`{ git -C <Core> diff --name-only HEAD -- <project>/docs; git -C <Core> ls-files --others --exclude-standard -- <project>/docs; }`.
