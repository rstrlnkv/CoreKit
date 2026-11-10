#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
new_sandbox; setup_core; sync_tools
bash "$SKILL/scripts/scaffold.sh" --name stop-app >/dev/null
P="$CORE_DIR/stop-app"; C="$(dirname "$CORE_DIR")/stop-app"; H="$HOOKS/stop-remind.sh"
assert_file "$H"
J="$C/.claude/settings.local.json"
# well-formed JSON (test-only use of python3; plugin code never uses it)
if command -v python3 >/dev/null 2>&1; then
  python3 -m json.tool "$J" >/dev/null 2>&1 && pass || fail "settings.local.json is not valid JSON"
else
  skip settings-json "python3 not on PATH; JSON well-formedness of settings.local.json not checked"
fi
# the Stop hook ships with the plugin; the project settings carry no hooks and no Core/bin path
assert_not_contains "$J" "\"Stop\""; assert_not_contains "$J" "\"hooks\""
assert_not_contains "$J" "stop-remind"; assert_contains "$J" "\"$P\""
assert_not_contains "$PLUGIN/templates/code/settings.local.json.tmpl" "\"hooks\""
HJ="$PLUGIN/hooks/hooks.json"
assert_contains "$HJ" "\"Stop\""
assert_contains "$HJ" 'bash \"${CLAUDE_PLUGIN_ROOT}/hooks/stop-remind.sh\"'
assert_contains "$HJ" "\"timeout\": 10"
(cd "$C" && bash "$SCRIPTS/save" "init") >/dev/null 2>&1

input() { printf '{"session_id":"x","cwd":"%s","hook_event_name":"Stop","stop_hook_active":%s}' "$1" "$2"; }
# clean -> 0
input "$C" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "0" "clean repo should pass"
# dirty code -> 2 with message naming save
echo x > "$C/new.txt"
OUT=$(input "$C" false | bash "$H" 2>&1); rc=$?
assert_eq "$rc" "2" "dirty code should block"; echo "$OUT" | grep -q 'save' && pass || fail "message lacks save"
echo "$OUT" | grep -qF "bash \"$SCRIPTS/save\"" && pass || fail "message does not name the plugin's save ($SCRIPTS/save): $OUT"
echo "$OUT" | grep -qF "/bin/save" && fail "message names a Core/bin copy: $OUT" || pass
echo "$OUT" | grep -q 'waiting for the user' && pass || fail "message lacks the waiting-for-approval case"
# already reminded -> 0
input "$C" true | bash "$H" >/dev/null 2>&1; assert_eq "$?" "0" "stop_hook_active must not loop"
# same changes at the next stop (e.g. waiting for approval) -> no repeat
input "$C" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "0" "repeated reminder for unchanged state"
# new edits, also to an already untracked file -> remind again
echo more >> "$C/new.txt"
input "$C" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "2" "no reminder after new edits"
assert_eq "$(git -C "$C" status --porcelain)" "?? new.txt" "hook left files in the worktree"
# dirty docs only -> 2
(cd "$C" && bash "$SCRIPTS/save" "s") >/dev/null 2>&1; echo y >> "$P/docs/brief.md"
input "$C" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "2" "dirty docs should block"
# a session in <Core>/<name>/ of a new-layout project: the reminder covers the code folder beside the Core
(cd "$C" && bash "$SCRIPTS/save" "s-core") >/dev/null 2>&1; echo z > "$C/from-core.txt"
OUT=$(input "$P" false | bash "$H" 2>&1); rc=$?
assert_eq "$rc" "2" "dirty code, session in <Core>/<name>/: $OUT"
echo "$OUT" | grep -q 'save' && pass || fail "reminder from <Core>/<name>/ lacks save: $OUT"
(cd "$C" && bash "$SCRIPTS/save" "s-core2") >/dev/null 2>&1
# outside a project -> 0 (never block unrelated sessions)
OUT=$(input "$SANDBOX" false | bash "$H" 2>&1); assert_eq "$?" "0" "outside project should pass"
assert_eq "$OUT" "" "hook must stay silent outside a Core project"

# untracked file with a non-ASCII name: edits are noticed, no cksum errors reach Claude
(cd "$C" && bash "$SCRIPTS/save" "s2") >/dev/null 2>&1
echo a > "$C/заметки.txt"
OUT=$(input "$C" false | bash "$H" 2>&1); assert_eq "$?" "2" "non-ASCII file: first reminder"
assert_eq "$(echo "$OUT" | grep -c 'No such file')" "0" "cksum error in reminder: $OUT"
echo b >> "$C/заметки.txt"
input "$C" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "2" "edit of non-ASCII untracked file missed"

# repo with no commits yet (right after scaffold): edits to a staged file are noticed
bash "$SKILL/scripts/scaffold.sh" --name fresh-app >/dev/null; F="$(dirname "$CORE_DIR")/fresh-app"
echo 1 > "$F/a.txt"; git -C "$F" add a.txt; echo 2 >> "$F/a.txt"
input "$F" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "2" "no-commit repo: first reminder"
echo 3 >> "$F/a.txt"
input "$F" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "2" "no-commit repo: edit of staged file missed"
# cwd with JSON escapes: a Core whose path has a space, quotes and Cyrillic (written as \u, \/ and \")
OLD_CORE="$CORE_DIR"; EC="$SANDBOX/Мой проекты \"q\"/Ядро"; export CORE_DIR="$EC"; setup_core
bash "$SKILL/scripts/scaffold.sh" --name esc-app >/dev/null; X="$(dirname "$EC")/esc-app"
echo x > "$X/new.txt"
esc_json() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's|/|\\/|g' -e 's/Мой/\\u041c\\u043e\\u0439/'; }
printf '{"session_id":"x",\n "cwd" :\n "%s", "hook_event_name":"Stop","stop_hook_active":false}' "$(esc_json "$X")" | bash "$H" >/dev/null 2>&1
assert_eq "$?" "2" "escaped cwd (quote, space, \\u) must still find the project"
export CORE_DIR="$OLD_CORE"
# a cwd that is not valid JSON-wise parseable lets the stop through
printf '{"cwd":"/no/such/\\' | bash "$H" >/dev/null 2>&1; assert_eq "$?" "0" "broken JSON passes"
# a nested repo with the Core shape but outside the Core (other/proj/code): the hook stays inert
O="$SANDBOX/other"; mkdir -p "$O/proj/code"
git init -q "$O"; echo r > "$O/readme.txt"; git -C "$O" add -A; git -C "$O" commit -q -m o
git init -q "$O/proj/code"; echo a > "$O/proj/code/a.txt"; git -C "$O/proj/code" add -A; git -C "$O/proj/code" commit -q -m a
echo dirty > "$O/proj/code/new.txt"; echo dirty >> "$O/proj/notes.md"
OUT=$(input "$O/proj/code" false | bash "$H" 2>&1); rc=$?
assert_eq "$rc" "0" "non-Core other/proj/code must pass"
assert_eq "$OUT" "" "hook must stay silent in a non-Core other/proj/code"
assert_no_file "$O/proj/code/.git/new-project-stop-remind"
# attribution=forbid: the reminder's save command carries --no-attribution
echo more >> "$C/new.txt"
OUT=$(input "$C" false | CLAUDE_PLUGIN_OPTION_ATTRIBUTION=forbid bash "$H" 2>&1)
echo "$OUT" | grep -qF "bash \"$SCRIPTS/save\" \"<short English subject>\" --no-attribution" && pass || fail "forbid: reminder lacks --no-attribution: $OUT"
echo more >> "$C/new.txt"
OUT=$(input "$C" false | bash "$H" 2>&1)
echo "$OUT" | grep -qF -- "--no-attribution" && fail "allow: reminder has --no-attribution: $OUT" || pass

# untracked files are fingerprinted by name, size and mtime, not by reading their content: a change of
# the mtime alone counts as a new change, the same name, size and mtime does not
(cd "$C" && bash "$SCRIPTS/save" "s-fp") >/dev/null 2>&1
echo same > "$C/fp.txt"
input "$C" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "2" "fingerprint: first reminder"
input "$C" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "0" "fingerprint: unchanged file reminded again"
touch -t 200001010000 "$C/fp.txt"
input "$C" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "2" "fingerprint: an mtime change was missed"
# an untracked file the hook cannot read is still fingerprinted, with no error in the reminder
if [ "$(id -u)" != 0 ]; then
  echo secret > "$C/noread.txt"; chmod 000 "$C/noread.txt"
  OUT=$(input "$C" false | bash "$H" 2>&1); rc=$?
  assert_eq "$rc" "2" "fingerprint: unreadable file"
  echo "$OUT" | grep -qi 'permission denied' && fail "read error in the reminder: $OUT" || pass
  touch -t 200001020000 "$C/noread.txt"
  input "$C" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "2" "fingerprint: mtime change of an unreadable file missed"
  chmod 600 "$C/noread.txt"; rm -f "$C/noread.txt"
fi
# an edit of the same size within the same minute is noticed (the file is newer than the last reminder)
input "$C" false | bash "$H" >/dev/null 2>&1
echo same > "$C/fp.txt"; input "$C" false | bash "$H" >/dev/null 2>&1
printf 'SAME\n' > "$C/fp.txt"
input "$C" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "2" "fingerprint: a same-size edit was missed"
# a file dated in the future (a clock ahead) is reminded once, not at every stop
echo f > "$C/future.txt"; touch -t 209901010000 "$C/future.txt"
input "$C" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "2" "future file: first reminder"
input "$C" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "0" "future file: reminded at every stop"
rm -f "$C/fp.txt" "$C/future.txt"

# the state file is a function of the tree: written again from scratch, it has the same bytes (a dirty code repo,
# dirty docs, an untracked file dated in the future, so both parts of the file are there)
(cd "$C" && bash "$SCRIPTS/save" "s-state") >/dev/null 2>&1
echo s > "$C/state-a.txt"; echo f > "$C/state-future.txt"; touch -t 209901010000 "$C/state-future.txt"; echo d >> "$P/docs/brief.md"
ST="$C/.git/new-project-stop-remind"; rm -f "$ST"
input "$C" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "2" "state file: first reminder"
cp "$ST" "$SANDBOX/state.1"; rm -f "$ST"
input "$C" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "2" "state file: reminder after the state file was removed"
cmp -s "$ST" "$SANDBOX/state.1" && pass || fail "state file: written again, its content differs: $(diff "$SANDBOX/state.1" "$ST")"
assert_eq "$(sed -n 2p "$ST")" "$C/state-future.txt" "state file: the future-dated file is its second line"

# cost: a dirty, already reminded project runs each git command once (a shim on PATH counts them)
GIT="$(command -v git)"; mkdir -p "$SANDBOX/gitshim"
printf '#!/bin/sh\necho "$*" >> "%s"\nexec "%s" "$@"\n' "$SANDBOX/git.log" "$GIT" > "$SANDBOX/gitshim/git"; chmod +x "$SANDBOX/gitshim/git"
: > "$SANDBOX/git.log"
input "$C" false | PATH="$SANDBOX/gitshim:$PATH" bash "$H" >/dev/null 2>&1; assert_eq "$?" "0" "git count: already reminded"
n="$(wc -l < "$SANDBOX/git.log" | tr -d ' ')"
[ "$n" -le 13 ] && pass || fail "git calls in a dirty, already reminded project: $n (at most 13): $(sed 's/^-C [^ ]* //' "$SANDBOX/git.log" | tr '\n' '|')"
rm -f "$C/state-a.txt" "$C/state-future.txt"; (cd "$C" && bash "$SCRIPTS/save" "s-state2") >/dev/null 2>&1

# a TMPDIR inside the code repo, not ignored: the hook leaves no file there that its own untracked list would see,
# so an unchanged tree is reminded once, not at every stop
mkdir -p "$C/.tmp"; echo t > "$C/tmp-new.txt"
for _ in 1 2 3; do input "$C" false | TMPDIR="$C/.tmp" bash "$H" >/dev/null 2>&1; printf '%s ' "$?"; done > "$SANDBOX/rcs"
assert_eq "$(cat "$SANDBOX/rcs")" "2 0 0 " "TMPDIR in the repo: three stops on an unchanged tree"
assert_eq "$(ls -A "$C/.tmp")" "" "TMPDIR in the repo: the hook left a file there"
# no temp file can be made (mktemp fails): the same outcome
mkdir -p "$SANDBOX/nomktemp"; printf '#!/bin/sh\nexit 1\n' > "$SANDBOX/nomktemp/mktemp"; chmod +x "$SANDBOX/nomktemp/mktemp"
echo u >> "$C/tmp-new.txt"
for _ in 1 2 3; do input "$C" false | PATH="$SANDBOX/nomktemp:$PATH" bash "$H" >/dev/null 2>&1; printf '%s ' "$?"; done > "$SANDBOX/rcs"
assert_eq "$(cat "$SANDBOX/rcs")" "2 0 0 " "no temp file: three stops on an unchanged tree"
rm -rf "$C/.tmp" "$C/tmp-new.txt"; (cd "$C" && bash "$SCRIPTS/save" "s-tmp") >/dev/null 2>&1
# the untracked list's temp file sits in the code repo's git folder and goes with the hook: after every stop above
# (reminded, not reminded, exit 0 and exit 2) none is left there
GDC="$(git -C "$C" rev-parse --absolute-git-dir)"
assert_eq "$(find "$GDC" -maxdepth 1 -name 'corecrew-stop.*' | wc -l | tr -d ' ')" "0" "a corecrew-stop temp file was left in $GDC"

# a Core path that is a tracked folder gone from disk (its whole folder deleted) still belongs to the step:
# core_paths keeps the first part of each tracked path, so the deletion is a docs change and is reminded
CORE_ROOT="$(git -C "$P" rev-parse --show-toplevel)"
mkdir -p "$CORE_ROOT/knowledge/deep"; echo k > "$CORE_ROOT/knowledge/deep/note.md"
git -C "$CORE_ROOT" add -f knowledge/deep/note.md && git -C "$CORE_ROOT" -c user.name=t -c user.email=t@t commit -qm k --no-verify
input "$C" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "0" "tracked Core folder: clean tree passes"
rm -rf "$CORE_ROOT/knowledge"
cps="$(cd "$C" && . "$SCRIPTS/_locate.sh" && locate && printf ' %s ' "$CORE_PATHS")"
echo "$cps" | grep -q ' knowledge ' && pass || fail "a tracked folder missing on disk is not a Core path: $cps"
input "$C" false | bash "$H" >/dev/null 2>&1; assert_eq "$?" "2" "a deleted tracked Core folder is a docs change"
git -C "$CORE_ROOT" checkout -q -- knowledge

# Codex Stop payloads (fixtures built from the rust-v0.166.0 structs): same rules, and an exit 2 carries a
# non-empty stderr (Codex treats exit 2 with an empty one as a failed hook, not a block)
FX="$ROOT/tests/fixtures/codex"
(cd "$C" && bash "$SCRIPTS/save" "s-codex0") >/dev/null 2>&1
cstop() { sed "s|@CWD@|$C|g" "$FX/$1.json" | bash "$H" 2>"$SANDBOX/cerr" >"$SANDBOX/cout"; CRC=$?; }
cstop stop; assert_eq "$CRC" "0" "codex Stop: clean repo passes"
echo c > "$C/codex-new.txt"
cstop stop; assert_eq "$CRC" "2" "codex Stop: dirty code blocks"
[ -s "$SANDBOX/cerr" ] && pass || fail "codex Stop: exit 2 with an empty stderr"
assert_eq "$(cat "$SANDBOX/cout")" "" "codex Stop: nothing on stdout"
grep -q 'save' "$SANDBOX/cerr" && pass || fail "codex Stop: the reminder lacks save"
cstop stop-active; assert_eq "$CRC" "0" "codex Stop: stop_hook_active exits 0"
cstop stop; assert_eq "$CRC" "0" "codex Stop: the same change set is not reminded twice"
echo more >> "$C/codex-new.txt"
cstop stop; assert_eq "$CRC" "2" "codex Stop: new edits remind again"
[ -s "$SANDBOX/cerr" ] && pass || fail "codex Stop: second exit 2 with an empty stderr"
(cd "$C" && bash "$SCRIPTS/save" "s-codex") >/dev/null 2>&1

finish
