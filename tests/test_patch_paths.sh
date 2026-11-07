#!/usr/bin/env bash
# scripts/patch-paths.awk and lib.sh patch_paths: the file paths of a Codex apply_patch text.
# Output "<kind>\t<path>": W written (Add, Update without Move, Move destination), S Move source,
# D Delete, X unreadable (no Begin Patch, or an unknown *** line in a hunk position).
source "$(dirname "$0")/lib.sh"
new_sandbox
. "$SCRIPTS/lib.sh"
SELF="$PLUGIN"
T="$(printf '\t')"
trap 'rm -rf "$SANDBOX"' EXIT

# pp <text> — the adapter output with the TAB shown as '>'
pp() { patch_paths "$1" | tr '\t' '>'; }
nl="
"
b="*** Begin Patch$nl"; e="*** End Patch"

assert_eq "$(pp "$b*** Add File: docs/a.md${nl}+hi$nl$e")" "W>docs/a.md" "add"
assert_eq "$(pp "$b*** Update File: src/a.swift$nl@@$nl-a$nl+b$nl$e")" "W>src/a.swift" "update"
assert_eq "$(pp "$b*** Delete File: docs/a.md$nl$e")" "D>docs/a.md" "delete"
assert_eq "$(pp "$b*** Update File: .env$nl*** Move to: src/x$nl@@$nl-a$nl+b$nl$e")" "S>.env${nl}W>src/x" "update with move"
assert_eq "$(pp "$b*** Add File: a$nl+x$nl*** Update File: b$nl@@$nl+y$nl*** Delete File: c$nl$e")" "W>a${nl}W>b${nl}D>c" "several files"
assert_eq "$(pp "$b*** Add File: /abs/x.md$nl+x$nl*** Add File: ../up/y.md$nl+y$nl$e")" "W>/abs/x.md${nl}W>../up/y.md" "absolute and relative"
assert_eq "$(pp "$(printf '*** Begin Patch\r\n*** Add File: docs/a.md\r\n+x\r\n*** End Patch\r\n')")" "W>docs/a.md" "CRLF"
assert_eq "$(pp "$b*** Update File: a$nl@@$nl-x$nl+y$nl*** End of File$nl*** Add File: b$nl+z$nl$e")" "W>a${nl}W>b" "End of File marker"
assert_eq "$(pp "*** Begin Patch$nl*** Environment ID: e1$nl*** Add File: a$nl+x$nl$e")" "W>a" "Environment ID"
assert_eq "$(pp "apply_patch <<'EOF'$nl$b*** Add File: docs/a.md$nl+x$nl$e${nl}EOF")" "W>docs/a.md" "heredoc wrapper lines"
assert_eq "$(pp "$b*** Add File: a$nl+*** Add File: docs/x$nl$e")" "W>a" "content line that looks like a header is not a path"
assert_eq "$(pp "$b*** Update File: a$nl@@$nl   *** Add File: docs/x$nl+z$nl$e")" "W>a" "indented header in an update hunk is context"
assert_eq "$(pp "$b*** Delete File: a$nl  *** Add File: docs/y$nl+z$nl$e")" "D>a${nl}W>docs/y" "indented header after a delete is a path"
assert_eq "$(pp "$b*** Add File: my docs/a b.md$nl+x$nl$e")" "W>my docs/a b.md" "spaces in a path"
assert_eq "$(pp "$b*** Add File: docs/a.md   $nl+x$nl$e")" "W>docs/a.md" "trailing spaces"
assert_eq "$(pp "$b*** Add File: d*/\$x/\`y\`.md$nl+x$nl$e")" "W>d*/\$x/\`y\`.md" "glob and variable characters are kept"
assert_eq "$(pp "just text")" "X>unreadable" "no Begin Patch"
assert_eq "$(pp "")" "X>unreadable" "empty input"
assert_eq "$(pp "$b*** Add File: docs/a.md$nl+x")" "W>docs/a.md" "unterminated patch"
assert_eq "$(pp "$b*** Add File: a$nl+x$nl*** Bogus line$nl$e")" "W>a${nl}X>unreadable" "unknown *** line"
assert_eq "$(pp "$b*** Update File: a$nl@@$nl*** Bogus$nl$e")" "X>unreadable${nl}W>a" "unknown *** line in a hunk (the update is listed at its end)"
many="$b"; i=0; while [ "$i" -lt 150 ]; do many="$many*** Add File: f$i$nl+x$nl"; i=$((i + 1)); done
assert_eq "$(pp "$many$e" | wc -l | tr -d ' ')" "101" "capped at 100 paths plus one C line"
assert_eq "$(pp "$many$e" | tail -n 1)" "C>too many files" "the cap shows as a C line"
# Begin must stand alone on its line (a patch in a shell command is not read here: the guards refuse it)
assert_eq "$(pp "apply_patch '*** Begin Patch$nl*** Add File: docs/a.md$nl+x$nl$e'")" "X>unreadable" "Begin after text"
# tester: inputs nobody fed
assert_eq "$(pp "$b*** Add File: a$nl+x$nl$e$nl$b*** Add File: docs/b$nl+x$nl$e")" "W>a${nl}W>docs/b" "two Begin..End blocks"
assert_eq "$(pp "$b*** Add File:	docs/a.md$nl+x$nl$e")" "W>docs/a.md" "a tab after the colon is trimmed"
assert_eq "$(pp "$b*** Add File:docs/a.md$nl+x$nl$e")" "W>docs/a.md" "no space after the colon"
assert_eq "$(pp "$b*** ADD FILE: docs/a.md$nl+x$nl$e")" "X>unreadable" "uppercase header is unreadable"
assert_eq "$(pp "*** BEGIN PATCH${nl}*** Add File: docs/a.md")" "X>unreadable" "uppercase Begin is unreadable"
assert_eq "$(pp "$b*** Update File: .env$nl*** Move to: x$nl@@$nl-a$nl+b$nl*** Delete File: .env$nl$e")" "S>.env${nl}W>x${nl}D>.env" "move source kept as S, delete after it"
assert_eq "$(pp "$b*** Update File: a$nl*** Move to: b$nl*** Move to: .env$nl@@$nl$e")" "S>a${nl}W>b${nl}X>unreadable" "a second Move to is unreadable"
assert_eq "$(pp "$b*** Add File: a$nl+x$nl*** Move to: .env$nl$e")" "W>a${nl}X>unreadable" "Move to after an Add is unreadable"
assert_eq "$(pp "$b*** Add File: $nl+x$nl*** Add File: docs/a$nl$e")" "X>unreadable${nl}W>docs/a" "an empty path is unreadable, the next header still read"
assert_eq "$(pp "$b*** Add File: док/ё.md$nl+x$nl$e")" "W>док/ё.md" "non-ASCII path"
# the 101st path: the adapter prints a C line instead of dropping it silently
many="$b"; i=0; while [ "$i" -lt 100 ]; do many="$many*** Add File: f$i$nl+x$nl"; i=$((i + 1)); done
assert_eq "$(pp "$many*** Add File: .env$nl+x$nl$e" | tail -n 1)" "C>too many files" "the 101st path (.env) is flagged by a C line"
assert_eq "$(pp "$many$e" | grep -c '^C>')" "0" "exactly 100 paths: no C line"
# whitespace as Rust trim() sees it (Codex trims header lines and paths): ASCII, NEL, NBSP, U+1680, U+2000-200A, U+2028/9, U+202F, U+205F, U+3000
ws=" $(printf '\t\v\f') $(printf '\302\205 \302\240 \341\232\200 \342\200\200 \342\200\212 \342\200\250 \342\200\251 \342\200\257 \342\201\237 \343\200\200')"
for w in $ws; do
  assert_eq "$(pp "$b${w}*** Add File: docs/a.md$nl+x$nl$e")" "W>docs/a.md" "leading whitespace $(printf '%s' "$w" | od -An -tx1 | tr -d ' \n')"
  assert_eq "$(pp "$b*** Add File: docs/a.md${w}$nl+x$nl$e")" "W>docs/a.md" "trailing whitespace $(printf '%s' "$w" | od -An -tx1 | tr -d ' \n')"
  assert_eq "$(pp "${w}*** Begin Patch$nl*** Add File: ${w}docs/a.md$nl+x$nl$e")" "W>docs/a.md" "Begin and path with whitespace $(printf '%s' "$w" | od -An -tx1 | tr -d ' \n')"
done
assert_eq "$(pp "$b*** Add File: a$nl+x$nl$(printf '\302\240')*** Add File: docs/b$nl$e")" "W>a${nl}W>docs/b" "NBSP header after an Add body"
# junk before a header: unreadable
assert_eq "$(pp "$b*** Add File: a$nl+x${nl}junk *** Add File: .env$nl$e")" "W>a${nl}X>unreadable" "junk before a header is X"
assert_eq "$(pp "x *** Add File: .env" )" "X>unreadable" "strict: text with a header outside Begin is X"
# a missing awk file prints nothing and does not fail
SELF="$SANDBOX/nowhere"
assert_eq "$(patch_paths "$b*** Add File: a$nl$e")" "" "missing adapter prints nothing"
finish
