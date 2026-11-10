#!/usr/bin/env bash
# Codex task chain (port task 4): lib.sh role-model, core-writable, tree-state, and the Codex docs of the task skill.
source "$(dirname "$0")/lib.sh"
new_sandbox
LIB="$SCRIPTS/lib.sh"
TASK="$PLUGIN/skills/task"

# --- role-model: every host x profile x role
rm_check() { # host profile role want
  local out err rc
  out="$(bash "$LIB" role-model "$1" "$2" "$3" 2>"$SANDBOX/err")"; rc=$?
  assert_eq "$rc" "0" "role-model $1 $2 $3 exits 0"
  assert_eq "$out" "$4" "role-model $1 $2 $3"
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = "1" ] && pass || fail "role-model $1 $2 $3 prints one line"
}
# columns: economy balanced strong
for role in engineer tester; do
  rm_check claude economy "$role" haiku; rm_check claude balanced "$role" sonnet; rm_check claude strong "$role" sonnet
  rm_check codex economy "$role" "gpt-6-luna medium"; rm_check codex balanced "$role" "gpt-6.1-sol medium"; rm_check codex strong "$role" "gpt-6.1-sol high"
done
for role in security verifier localizer designer; do
  rm_check claude economy "$role" sonnet; rm_check claude balanced "$role" sonnet; rm_check claude strong "$role" opus
  rm_check codex economy "$role" "gpt-6.1-sol low"; rm_check codex balanced "$role" "gpt-6.1-sol medium"; rm_check codex strong "$role" "gpt-6-astra high"
done
for role in architect explorer; do
  for p in economy balanced strong; do rm_check claude "$p" "$role" ""; done
  rm_check codex economy "$role" "gpt-6.1-sol low"; rm_check codex balanced "$role" "gpt-6.1-sol medium"; rm_check codex strong "$role" "gpt-6-astra high"
done
rm_bad() { # args...
  local out rc
  out="$(bash "$LIB" role-model "$@" 2>"$SANDBOX/err")"; rc=$?
  assert_eq "$rc" "2" "role-model $* exits 2"
  assert_eq "$out" "" "role-model $* prints nothing on stdout"
  [ -s "$SANDBOX/err" ] && grep -qi usage "$SANDBOX/err" && pass || fail "role-model $* prints a usage line on stderr"
}
rm_bad gemini balanced engineer
rm_bad claude turbo engineer
rm_bad codex balanced janitor
rm_bad claude balanced
rm_bad
rm_bad claude balanced engineer extra
rm_bad "" balanced engineer
rm_bad claude "" engineer
rm_bad claude balanced ""
rm_bad Claude balanced engineer

# --- role-model: the user's own Codex models from the settings file (Claude Code keeps its table)
SF="$(bash "$LIB" setting-path)"; mkdir -p "$(dirname "$SF")"
rmo() { bash "$LIB" role-model "$@" 2>"$SANDBOX/err"; }
printf 'codex_model: my-model-1 high\n' > "$SF"
for role in engineer tester security verifier localizer designer architect explorer; do
  for p in economy balanced strong; do assert_eq "$(rmo codex "$p" "$role")" "my-model-1 high" "codex_model applies to codex $p $role"; done
done
assert_eq "$(rmo claude balanced engineer)" "sonnet" "codex_model leaves claude alone"
printf 'codex_model: my-model-1 high\ncodex_model_tester: other.model-2\ncodex_model_verifier: inherit\n' > "$SF"
assert_eq "$(rmo codex balanced tester)" "other.model-2" "a role key beats codex_model; a model alone has no effort"
assert_eq "$(rmo codex balanced verifier)" "" "inherit: an empty line (spawn without model and effort)"
assert_eq "$(rmo codex balanced verifier | wc -l | tr -d ' ')" "1" "inherit still prints one line"
assert_eq "$(rmo codex balanced engineer)" "my-model-1 high" "other roles keep codex_model"
printf 'codex_model_engineer:   spaced-model    low  \n' > "$SF"
assert_eq "$(rmo codex balanced engineer)" "spaced-model low" "blanks are trimmed and collapsed"
for bad in 'two words more' 'bad;model' '$(touch x)' 'model HIGH' '-flag low'; do
  printf 'codex_model_engineer: %s\n' "$bad" > "$SF"
  out="$(rmo codex balanced engineer)"; rc=$?
  assert_eq "$rc:$out" "0:gpt-6.1-sol medium" "an invalid value ($bad) falls back to the table"
  grep -q 'codex_model_engineer' "$SANDBOX/err" && pass || fail "an invalid value ($bad) is named on stderr"
done
printf 'codex_model: bad;x\ncodex_model_engineer: also bad;x\n' > "$SF"
assert_eq "$(rmo codex strong security)" "gpt-6-astra high" "an invalid codex_model falls back to the table"
rm -f "$SF"
# the built-in Codex table names models (and efforts) the bundled catalog of the installed codex knows
if command -v codex >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  mkdir -p "$CODEX_HOME"
  if codex debug models --bundled > "$SANDBOX/models.json" 2>/dev/null; then
    for p in economy balanced strong; do for role in engineer security; do
      bash "$LIB" role-model codex "$p" "$role"
    done; done | sort -u > "$SANDBOX/table.txt"
    miss="$(python3 -c '
import json, sys
cat = json.load(open(sys.argv[1]))
models = cat.get("models", cat) if isinstance(cat, dict) else cat
known = {}
for m in models:
    levels = m.get("supported_reasoning_levels") or []
    known[m.get("slug")] = {l.get("effort") for l in levels if isinstance(l, dict)}
for line in open(sys.argv[2]):
    w = line.split()
    if not w: continue
    if w[0] not in known: print(w[0])
    elif len(w) > 1 and known[w[0]] and w[1] not in known[w[0]]: print(" ".join(w))
' "$SANDBOX/models.json" "$SANDBOX/table.txt" 2>&1)"
    assert_eq "$miss" "" "every model and effort of the role-model codex table is in the bundled catalog"
  else
    skip codex-catalog "codex debug models --bundled failed; the role-model table is not compared with the catalog"
  fi
else
  skip codex-catalog "codex or python3 not on PATH; the role-model table is not compared with the catalog"
fi

# --- core-writable
D="$SANDBOX/cw dir"; mkdir -p "$D"; : > "$D/keep.txt"
before="$(ls -A "$D")"
out="$(bash "$LIB" core-writable "$D" 2>&1)"; rc=$?
assert_eq "$rc" "0" "core-writable on a writable dir exits 0"
assert_eq "$out" "" "core-writable is silent when writable"
assert_eq "$(ls -A "$D")" "$before" "core-writable leaves no probe behind"
assert_file "$D/keep.txt"
if [ "$(id -u)" != "0" ]; then
  RO="$SANDBOX/ro dir"; mkdir -p "$RO"; : > "$RO/f"; chmod a-w "$RO"
  err="$(bash "$LIB" core-writable "$RO" 2>&1 >/dev/null)"; rc=$?
  assert_eq "$rc" "1" "core-writable on a read-only dir exits 1"
  case "$err" in *--add-dir*"$RO"*|*"$RO"*--add-dir*) pass ;; *) fail "stderr names --add-dir and the dir: $err" ;; esac
  assert_eq "$(ls -A "$RO")" "f" "read-only dir untouched"
  chmod u+w "$RO"
else
  skip core-writable-read-only "running as root"
fi
MISSING="$SANDBOX/no such dir"
err="$(bash "$LIB" core-writable "$MISSING" 2>&1 >/dev/null)"; rc=$?
assert_eq "$rc" "1" "core-writable on a missing dir exits 1"
case "$err" in *--add-dir*) pass ;; *) fail "missing dir stderr names --add-dir: $err" ;; esac
case "$err" in *"$MISSING"*) pass ;; *) fail "missing dir stderr names the dir: $err" ;; esac
assert_no_file "$MISSING"
bash "$LIB" core-writable "relative/dir" >/dev/null 2>&1; assert_eq "$?" "2" "core-writable relative path exits 2"
bash "$LIB" core-writable >/dev/null 2>&1; assert_eq "$?" "2" "core-writable no args exits 2"
bash "$LIB" core-writable "$D" extra >/dev/null 2>&1; assert_eq "$?" "2" "core-writable two args exits 2"
bash "$LIB" core-writable "" >/dev/null 2>&1; [ "$?" -ne 0 ] && pass || fail "core-writable empty path fails"

# --- tree-state
R="$SANDBOX/repo with space"; mkdir -p "$R/sub dir"; git -C "$R" init -q
printf '*.log\n' > "$R/.gitignore"; printf 'aaaa\n' > "$R/tracked file.txt"; printf 'one\n' > "$R/sub dir/other.txt"
git -C "$R" add -A && git -C "$R" commit -q -m init
ts() { bash "$LIB" tree-state "$R" 2>/dev/null; }
base="$(ts)"; rc=0
[ -n "$base" ] && pass || fail "tree-state prints a line"
assert_eq "$(printf '%s\n' "$base" | wc -l | tr -d ' ')" "1" "tree-state prints one line"
assert_eq "$(ts)" "$base" "tree-state is stable across two runs"
changed() { # label: state must differ from $base, then reset base
  local now; now="$(ts)"
  [ -n "$now" ] && [ "$now" != "$base" ] && pass || fail "tree-state changes after: $1"
  base="$now"
}
printf 'aaab\n' > "$R/tracked file.txt"; changed "editing a tracked file by one byte (same size)"
printf 'aaaa\n' > "$R/tracked file.txt"; changed "restoring the tracked file"
printf 'bbbb\n' > "$R/tracked file.txt"; git -C "$R" add "tracked file.txt"; changed "staging a change"
git -C "$R" reset -q; changed "unstaging"
git -C "$R" checkout -q -- "tracked file.txt"; base="$(ts)"
printf 'new\n' > "$R/untracked one.txt"; changed "a new untracked file"
printf 'neW\n' > "$R/untracked one.txt"; changed "changing an untracked file (same size)"
printf 'x\n' > "$R/sub dir/deep.txt"; changed "a new untracked file in a subfolder with a space"
rm "$R/sub dir/other.txt"; changed "deleting a tracked file"
git -C "$R" add -A; git -C "$R" commit -q -m two; changed "a new commit"
# each part of the fingerprint alone: only one of its inputs differs between the two states
printf 'cccc\n' > "$R/tracked file.txt"; base="$(ts)"
printf 'cccd\n' > "$R/tracked file.txt"; changed "a second edit of an already modified tracked file"   # diff HEAD only
git -C "$R" add "tracked file.txt"; printf 'eeee\n' > "$R/tracked file.txt"; base="$(ts)"   # staged and edited again
blob="$(printf 'ffff\n' | git -C "$R" hash-object -w --stdin)"
git -C "$R" update-index --cacheinfo "100644,$blob,tracked file.txt"
changed "staging other content while the work tree file keeps its bytes"   # the index only
git -C "$R" reset -q --hard; base="$(ts)"
git -C "$R" commit -q --allow-empty -m empty; changed "an empty commit"   # HEAD only
printf 'same\n' > "$R/t1.log"; printf 'same\n' > "$R/t2.log"   # ignored, equal content: only the link's target differs
ln -s t1.log "$R/a link"; base="$(ts)"
rm "$R/a link"; ln -s t2.log "$R/a link"; changed "an untracked symlink re-pointed at another file with the same content"
rm "$R/a link" "$R/t1.log" "$R/t2.log"
# documented limit: ignored files are not part of the state
base="$(ts)"
printf 'log\n' > "$R/x.log"; assert_eq "$(ts)" "$base" "creating an ignored x.log does not change the state"
printf 'log2\n' > "$R/x.log"; assert_eq "$(ts)" "$base" "editing an ignored x.log does not change the state"
# untracked nested git repo: a change inside it changes the line
base="$(ts)"
mkdir -p "$R/nested repo"; git -C "$R/nested repo" init -q; printf 'n1\n' > "$R/nested repo/n.txt"
changed "a new untracked nested repo"
git -C "$R/nested repo" add -A; git -C "$R/nested repo" -c user.name=t -c user.email=t@t commit -q -m i; changed "a commit inside the nested repo"
printf 'n2\n' > "$R/nested repo/n.txt"; changed "editing a tracked file inside the nested repo"
printf 'u\n' > "$R/nested repo/u.txt"; changed "a new untracked file inside the nested repo"
# an untracked file that cannot be read: one line still, exit 0, and no shell error reaches the caller
if [ "$(id -u)" != "0" ]; then
  printf 'secret\n' > "$R/noread.txt"; chmod 000 "$R/noread.txt"
  out="$(bash "$LIB" tree-state "$R" 2>"$SANDBOX/ts.err")"; rc=$?
  chmod 600 "$R/noread.txt"
  assert_eq "$rc" "0" "tree-state with an unreadable untracked file exits 0"
  assert_eq "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "1" "tree-state with an unreadable untracked file prints one line"
  assert_eq "$(cat "$SANDBOX/ts.err")" "" "tree-state with an unreadable untracked file: stderr"
  rm -f "$R/noread.txt"; base="$(ts)"
else
  skip tree-state-unreadable "running as root"
fi
# not a work tree
N="$SANDBOX/plain"; mkdir -p "$N"
out="$(bash "$LIB" tree-state "$N" 2>/dev/null)"; rc=$?
assert_eq "$rc" "1" "tree-state outside a git work tree exits 1"
assert_eq "$out" "" "tree-state prints nothing outside a work tree"
bash "$LIB" tree-state "$SANDBOX/nope" >/dev/null 2>&1; assert_eq "$?" "1" "tree-state on a missing dir exits 1"
bash "$LIB" tree-state "$R/.git" >/dev/null 2>&1; assert_eq "$?" "1" "tree-state inside .git (not a work tree) exits 1"

# --- docs
CX="$TASK/references/codex.md"
assert_file "$CX"
for w in spawn_agent role-model tree-state '<plugin>/agents/<role>.md' '<plugin>/reference/codex-host.md'; do
  assert_contains "$CX" "$w"
done
# the shared Codex reference: both multi-agent tool sets, a clear stop
# without spawn_agent, the --add-dir restart and the approval to leave the sandbox
CH="$PLUGIN/reference/codex-host.md"
sec() { awk -v n="$2" '$0 == "## " n {f=1; next} /^## /{f=0} f' "$1"; }
sa="$(sec "$CH" Subagents)"
for w in spawn_agent wait_agent 'fork_context: false' send_input close_agent task_name 'fork_turns: "none"' followup_task; do
  case "$sa" in *"$w"*) pass ;; *) fail "codex-host.md Subagents lacks: $w" ;; esac
done
case "$sa" in *'No `spawn_agent`'*stop*) pass ;; *) fail "codex-host.md Subagents: no stop when spawn_agent is missing" ;; esac
case "$(sec "$CH" 'Writable folders')" in *core-writable*'--add-dir'*) pass ;; *) fail "codex-host.md Writable folders: core-writable and --add-dir" ;; esac
case "$(sec "$CH" 'Approval outside the sandbox')" in *save*gh*'git push'*) pass ;; *) fail "codex-host.md Approval: save, gh, git push" ;; esac
case "$(sec "$CH" Questions)" in *AskUserQuestion*) pass ;; *) fail "codex-host.md Questions names what it replaces" ;; esac
assert_not_contains "$CH" '--full-auto'
# the crew chain sends both tool forms through the shared reference: no v2-only parameter in codex.md
for w in fork_turns followup_task task_name; do assert_not_contains "$CX" "$w"; done
assert_file "$TASK/references/architect-explorer.md"
assert_contains "$TASK/references/architect-explorer.md" "## Architect"
assert_contains "$TASK/references/architect-explorer.md" "## Explorer"
assert_contains "$TASK/SKILL.md" "references/codex.md"
# the SKILL.md Claude table agrees with role-model
for row in "engineer, tester|engineer" "security, verifier, localizer, designer|security"; do
  names="${row%%|*}"; role="${row##*|}"
  line="$(grep -F "| $names |" "$TASK/SKILL.md" | head -1)"
  e="$(printf '%s' "$line" | awk -F'|' '{gsub(/ /,"",$3); print $3}')"
  b="$(printf '%s' "$line" | awk -F'|' '{gsub(/ /,"",$4); print $4}')"
  s="$(printf '%s' "$line" | awk -F'|' '{gsub(/ /,"",$5); print $5}')"
  [ -n "$e" ] && pass || fail "SKILL.md table row for $names parsed"
  for pair in "economy $e" "balanced $b" "strong $s"; do
    p="${pair%% *}"; want="${pair#* }"
    for r in $(printf '%s' "$names" | tr -d ',' ); do
      assert_eq "$(bash "$LIB" role-model claude "$p" "$r" 2>/dev/null)" "$want" "SKILL.md table vs role-model claude $p $r"
    done
  done
done
# --- host
unset COREKIT_HOST
assert_eq "$(COREKIT_HOST=codex bash "$LIB" host)" "codex" "host: COREKIT_HOST=codex"
assert_eq "$(COREKIT_HOST=claude bash "$LIB" host)" "claude" "host: COREKIT_HOST=claude"
assert_eq "$(CODEX_HOME="$SANDBOX/cxh" bash "$LIB" host)" "claude" "host: default is claude"
mkdir -p "$SANDBOX/cxh/plugins/cache/corekit/corecrew"; cp -R "$PLUGIN" "$SANDBOX/cxh/plugins/cache/corekit/corecrew/9.9.9"
assert_eq "$(CODEX_HOME="$SANDBOX/cxh" bash "$SANDBOX/cxh/plugins/cache/corekit/corecrew/9.9.9/scripts/lib.sh" host)" "codex" "host: plugin under CODEX_HOME is codex"
assert_eq "$(COREKIT_HOST=codex bash "$LIB" host | wc -l | tr -d ' ')" "1" "host prints one line"
# --- hook messages name skills the way the host calls them: /corecrew:x in Claude Code, $corecrew:x in Codex
hm() { ( . "$SCRIPTS/lib.sh"; . "$HOOKS/messages.sh"; msg "$@" ); }
for k in hint_not_found hint_not_set_up; do
  out="$(COREKIT_HOST=codex hm "$k" /c)"
  case "$out" in *'$corecrew:new-project'*'$corecrew:task adopt'*) pass ;; *) fail "codex $k: $out" ;; esac
  case "$out" in */corecrew:*) fail "codex $k still names /corecrew: $out" ;; *) pass ;; esac
  out="$(COREKIT_HOST=claude hm "$k" /c)"
  case "$out" in *'/corecrew:new-project'*) pass ;; *) fail "claude $k: $out" ;; esac
done
out="$(COREKIT_HOST=codex UI_LANGUAGE=ru hm old_layout /a /b /c)"
case "$out" in *'$corecrew:task adopt /b'*) pass ;; *) fail "codex ru old_layout: $out" ;; esac
out="$(COREKIT_HOST=codex hm guard_code_blocked '/x/corecrew:y' /z)"
case "$out" in *'/x/corecrew:y'*) pass ;; *) fail "an argument is printed as given: $out" ;; esac
finish
