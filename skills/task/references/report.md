# Report

The last thing `task` says. In the user's language, labels in English, plain words. Nine lines,
in this order:

```
Path: <fix | full | question | batch | release | adopt> · project <P>
Chain: <role → role → …>
Done: <one line>
Proof: <command> → <key output lines>   (question: file:line)
Standards: <applied, or "none in Core">
Open: <what is left, or "nothing">
Knowledge: <saved lines and where | none>
Cost: <N agent calls, K engineer passes>
Commit: <hash and message | stopped — why>
```

## Rules
- `Proof` is a command you ran or an agent ran and showed, with the key output lines; for a
  `question`, a `file:line`. **No `Proof` → no report**: go back and get it.
- `Path` is also named in the first line said to the user when the chain starts.
- `Chain` lists roles in the order called, repeats included (`tester → engineer → tester`).
- `Standards` merges the agents' `Standards:` lines: the rule applied, quoted, or
  `none in Core`.
- `Open` holds extra tasks from the brief, unrepaired findings, "Not checked" items and, with a
  note, a reply that came back twice without `Standards:`.
- `Knowledge` names each saved line and its level (this project / all projects), and any line
  offered as a standard.
- `Cost` counts every Agent call and every engineer pass.
- `Commit` is the hash and message from `save`; for a stopped chain `stopped — <why>` and the
  step that failed.
