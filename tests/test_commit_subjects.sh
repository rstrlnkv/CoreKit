#!/usr/bin/env bash
# scripts/commit-subjects.sh: the check of CoreKit's own commit subjects (CI job and optional commit-msg hook).
source "$(dirname "$0")/lib.sh"
new_sandbox
S="$ROOT/scripts/commit-subjects.sh"
assert_file "$S"
R="$SANDBOX/repo"; git init -q "$R"
c() { git -C "$R" commit -q --allow-empty -m "$1"; }
c "chore: root"; root="$(git -C "$R" rev-parse HEAD)"
c "feat(corecrew): add x"
c "docs: y"
c "feat!: a breaking change"
c "merge: corecrew 0.9.1 and the CI fixes"
s72="fix(coremodel): $(printf '%072d' 0 | cut -c17-)"; [ ${#s72} -eq 72 ] || fail "test bug: s72 is ${#s72} long"
s73="${s72}x"
c "$s72"
c "$s73"
c "Add things"
c "release(corecrew): 0.9.0"
c "fixup! feat(corecrew): add x"
c 'Revert "feat(corecrew): add x"'
c "Undo step 20260101-120000-01-1a2b: Add things"
# a --no-ff merge: its subject is never checked
git -C "$R" checkout -q -b side; c "fix(corecrew): on the side"; git -C "$R" checkout -q -; git -C "$R" merge -q --no-ff -m "Merge branch 'side' into main" side

# --range: exit 1, and stderr names exactly the bad subjects, each with its reason
inrepo() { (cd "$R" && "$@"); }
inrepo bash "$S" --range "$root..HEAD" > "$SANDBOX/out" 2> "$SANDBOX/err"; rc=$?
assert_eq "$rc" "1" "--range with bad subjects"
assert_eq "$(wc -l < "$SANDBOX/err" | tr -d ' ')" "4" "one stderr line per bad subject: $(cat "$SANDBOX/err")"
assert_contains "$SANDBOX/err" "$s73"
assert_contains "$SANDBOX/err" "Add things"
assert_contains "$SANDBOX/err" "release(corecrew): 0.9.0"
assert_contains "$SANDBOX/err" "fixup! feat(corecrew): add x"
grep -F "$s73" "$SANDBOX/err" | grep -q '72' && pass || fail "the too-long line names the limit: $(grep -F "$s73" "$SANDBOX/err")"
assert_not_contains "$SANDBOX/err" "Merge branch"
assert_not_contains "$SANDBOX/err" 'Revert "'
assert_not_contains "$SANDBOX/err" 'Undo step'
grep -F "$s72" "$SANDBOX/err" | grep -vF "$s73" | grep -q . && fail "the 72-byte subject was refused" || pass
# a range of good commits only (the first four after the root) exits 0; an empty range exits 0
good_end="$(git -C "$R" rev-parse HEAD~9 2>/dev/null)"
assert_eq "$(git -C "$R" log --format=%s "$root..$good_end" | tail -1)" "feat(corecrew): add x" "test bug: the good range"
assert_exit 0 inrepo bash "$S" --range "$root..$good_end"
assert_exit 0 inrepo bash "$S" --range "$root..$root"
# the range is read from the current folder: a bad one is a usage error (2), not a pass
(cd "$R" && bash "$S" --range "$root..$good_end") >/dev/null 2>&1; assert_eq "$?" "0" "--range from inside the repo"
(cd "$R" && bash "$S" --range "nosuch..HEAD") >/dev/null 2>&1; assert_eq "$?" "2" "--range with an unknown revision"
# a bad range and a folder outside a repo: exit 2 with one own line, not git's fatal: line and the Usage line
(cd "$R" && bash "$S" --range "nosuch..HEAD") >"$SANDBOX/out" 2>"$SANDBOX/err"
assert_eq "$(cat "$SANDBOX/err")" "commit-subjects: bad range nosuch..HEAD" "--range with an unknown revision: one own line"
assert_eq "$(cat "$SANDBOX/out")" "" "--range with an unknown revision: nothing on stdout"
mkdir -p "$SANDBOX/norepo"
(cd "$SANDBOX/norepo" && bash "$S" --range "$root..HEAD") >"$SANDBOX/out" 2>"$SANDBOX/err"; rc=$?
assert_eq "$rc" "2" "--range outside a git repo"
assert_eq "$(cat "$SANDBOX/err")" "commit-subjects: not a git repository" "--range outside a git repo: one own line"
assert_eq "$(cat "$SANDBOX/out")" "" "--range outside a git repo: nothing on stdout"

# --file: the subject is the first line that is neither blank nor a # comment
f="$SANDBOX/msg"
printf '# Please enter the commit message\n\nfeat(corecrew): good subject\n\nBody.\n' > "$f"
assert_exit 0 bash "$S" --file "$f"
printf 'fixup! feat(corecrew): add x\n' > "$f"; assert_exit 0 bash "$S" --file "$f"
printf 'squash! feat(corecrew): add x\n' > "$f"; assert_exit 0 bash "$S" --file "$f"
printf 'amend! feat(corecrew): add x\n' > "$f"; assert_exit 0 bash "$S" --file "$f"
printf 'Revert "feat(corecrew): add x"\n\nThis reverts commit abc.\n' > "$f"; assert_exit 0 bash "$S" --file "$f"
printf 'Add things\n' > "$f"; assert_exit 1 bash "$S" --file "$f"
printf '%s\n' "$s73" > "$f"; assert_exit 1 bash "$S" --file "$f"
printf 'fix(CoreCrew): capitals in the scope\n' > "$f"; assert_exit 1 bash "$S" --file "$f"
printf 'fix(corecrew):no space\n' > "$f"; assert_exit 1 bash "$S" --file "$f"
printf 'fix(corecrew):  two spaces\n' > "$f"; assert_exit 1 bash "$S" --file "$f"
printf 'fix(core_crew): underscore\n' > "$f"; assert_exit 1 bash "$S" --file "$f"
printf 'fix(corecrew)!: a breaking fix\n' > "$f"; assert_exit 0 bash "$S" --file "$f"
printf '# only a comment\n\n' > "$f"; assert_exit 1 bash "$S" --file "$f"
# the length is counted in bytes (LC_ALL=C): a non-ASCII subject of 72 bytes passes, 73 fails
printf 'fix: %s\n' "$(printf 'é%.0s' $(seq 1 34))" > "$f"   # 5 + 68 bytes = 73
assert_exit 1 bash "$S" --file "$f"
printf 'fix: %sa\n' "$(printf 'é%.0s' $(seq 1 33))" > "$f"  # 5 + 66 + 1 = 72
assert_exit 0 bash "$S" --file "$f"

# The types live in two places: the script's RE line and the "types: ..." sentence of CONTRIBUTING.md (which wraps
# over two lines). Both lists are read here and compared in both directions; each type is run through the script.
types="$(sed -n "s/^RE='^(\([a-z|]*\)).*/\1/p" "$S" | tr '|' ' ')"
doc_types="$(tr -s '\n ' '  ' < "$ROOT/CONTRIBUTING.md" | sed -n 's/.*(types: \([a-z, ]*\);.*/\1/p' | tr -d ',')"
[ -n "$types" ] && pass || fail "no type list read from the RE line of scripts/commit-subjects.sh"
[ -n "$doc_types" ] && pass || fail "no type list read from the '(types: ...;' sentence of CONTRIBUTING.md"
for t in $types; do
  printf '%s: x\n' "$t" > "$f"
  bash "$S" --file "$f" 2>/dev/null && pass || fail "the script refuses its own type $t ('$t: x')"
  case " $doc_types " in *" $t "*) pass ;; *) fail "the script accepts the type $t, CONTRIBUTING.md does not name it" ;; esac
done
for t in $doc_types; do
  printf '%s: x\n' "$t" > "$f"
  bash "$S" --file "$f" 2>/dev/null && pass || fail "CONTRIBUTING.md names the type $t, the script refuses it ('$t: x')"
done
# a type neither list holds is refused
printf 'wip: x\n' > "$f"; assert_exit 1 bash "$S" --file "$f"

# arguments: none, one, an unknown mode, a missing file → 2
assert_exit 2 bash "$S"
assert_exit 2 bash "$S" --range
assert_exit 2 bash "$S" --what "$root..HEAD"
assert_exit 2 bash "$S" --file "$SANDBOX/no-such-file"
finish
