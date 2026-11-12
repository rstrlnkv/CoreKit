# Adopt: the documents

The stage after adopt's Verify step (`adopt.md`, step 9). The script moved the files; here the
private side gets filled in from what the repo already says, and the public documents are checked
against the Core standards and rewritten on the user's ok. `<folder>` is the code root, `<name>` the
project, `<P>` is `<Core>/<name>`.

The session was not started in `<folder>`, so the private `CLAUDE.md` is not loaded here: read
`<P>/CLAUDE.md` yourself, and give every agent absolute paths. Talk to the user in plain words;
everything written to disk is English.

## 1. Private pages

One `corecrew:engineer` call, then one `corecrew:verifier` call, as the `fix` path runs them
(briefs per `brief.md`, model per SKILL.md Settings).

- **Sources**, the only ones: the repo's `README*`, `INTERNALS*`, `ARCHITECTURE*`, `CONTRIBUTING*`,
  build and test scripts, manifests (`package.json`, `*.csproj`, `Cargo.toml`, ...), the CI files,
  and the pages adopt copied to `<P>/docs/`. Never `.env` files or `~/.ssh`.
- **Engineer fills:** in `<P>/CLAUDE.md` the Stack and Commands sections and the `check:` line
  (the command the user confirmed in adopt step 5; none confirmed: leave the line as it is);
  `docs/brief.md` (purpose and audience, what it stores, scope);
  `docs/architecture.md` (modules, data flow, boundaries); `docs/decisions/001-*.md` (the stack
  and the main design choices as the repo shows them); the `TODO` descriptions `wiki-migrate.sh`
  gave copied pages. Every statement comes from a source:
  what no source says stays `TODO` and is listed in the reply. A command the sources mark as
  dangerous or needing consent (it touches hardware, deletes data) goes in Commands with that
  warning and never into `check:`. Then `wiki-index.sh "<P>"` and front matter per
  `<plugin>/reference/wiki.md` (`status: active` for a filled page, `draft` while it has `TODO`).
- **Verifier:** every sentence written has its source (`file:line`), nothing is invented;
  `wiki-check.sh "<P>"` is green. A finding goes back to engineer once.
- **Commit** the Core only: `"<scripts>/save" "Fill <name> pages from the repo"` (release.md
  postconditions 5–7 for this one commit). Show the user what was filled and the `TODO` list.

## 2. Audit of the public side

Read-only; no agent. Ask the user once whether the repo is public (or will be). Not public:
skip the public-repository checks, keep the leftovers and the language.

1. **Standards.** For each file in `<Core>/standards/` and `<P>/docs/standards/` that governs the
   repository's files (for example `public-repository.md`: README shape, CHANGELOG in Keep a
   Changelog with one file per project language, `SECURITY.md`, a short `ARCHITECTURE.md`,
   `NOTICE.md` complete per third-party item), run its "How to check" commands in `<folder>` and
   note each rule that fails. A check with no command (read `NOTICE.md` against the tree): read
   and judge. A check that needs the network (`gh`) only on the user's ok. No standards there: say
   so and skip to 2.
2. **Leftovers of older private setups:** `.gitignore` blocks for files the Core now holds
   (other than the corecrew block adopt added), scripts or docs that create or explain links to
   private files, mentions of folders that no longer exist (`docs/` pages that moved, old tool
   names). `git -C "<folder>" grep -n` for them.
3. **Language.** Ask the user the project's language for code, comments and documents (the
   private `CLAUDE.md` Rules may already say it). List the tracked files whose comments or
   documents are in another language (UI text files the project localizes stay out).

Show the result as one numbered list, one line per item: the file, what is wrong, the rule
(`public-repository.md` rule 4, ...), and the chain that would fix it. Group items that touch the
same file into one item. Nothing failed: say so, go to the report.

## 3. Rewrite

The user picks the items (all, some, none). Run each picked item as its own chain, in list order,
as if the user had called `/corecrew:task "<item>"` with `<folder>` as the code root and `<name>`
as the project: SKILL.md Start steps 4–8, then the path (`fix` for one file, `batch` for one
shape in many files, `full` for a new document), release and report, one commit each.

- The brief names the rule, quotes nothing from the standard (give its path), and lists the
  sources the item may use; facts not in the repo (support policy, contact) are asked from the
  user before the chain, never invented.
- A translated file (`README.<code>.md`, `CHANGELOG.<code>.md`) or a language item: the
  checkers' wave includes `corecrew:localizer`.
- Moving, renaming or deleting a file of the user's: say which in the item and wait for its ok.
- A chain that stops: report it, ask whether to go on with the next item.

## Report lines

Add to adopt's report:
- `Private pages:` filled, and the `TODO` left (or `none`)
- `Documents:` per item, its commit or `declined` / `stopped — <why>`
