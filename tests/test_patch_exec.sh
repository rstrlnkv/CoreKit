#!/usr/bin/env bash
# NOTE: the rule is best effort, not a security boundary; the LIMIT cases (tests/test_shell_patch.sh) list known ways past it.
# Execution check for the shell apply_patch refusal: a fake apply_patch (it appends a line to a log) is first on PATH.
# Every bypass spelling must make guard-code and guard-secrets exit 2; every legitimate twin must pass both hooks and,
# when really run, must not start the fake. The bypass commands are run too (where the tool exists) to show that the
# fake is reachable that way, so the refusal is not guarding an empty danger.
source "$(dirname "$0")/lib.sh"
new_sandbox
unset CLAUDE_PLUGIN_OPTION_CORE_DIR
W="$SANDBOX/work"; BIN="$SANDBOX/fakebin"; LOG="$SANDBOX/fake.log"
mkdir -p "$W" "$BIN" "$CORE_DIR/p/code"
: > "$CORE_DIR/p/CLAUDE.md"
printf '#!/bin/sh\necho "RAN $*" >> "%s"\ncat >/dev/null 2>&1 </dev/null\n' "$LOG" > "$BIN/apply_patch"
chmod +x "$BIN/apply_patch"
( cd "$W" && git init -q . && git config user.email t@t && git config user.name t \
  && printf 'one\n' > f.txt && git add f.txt && git commit -qm "apply_patch note" ) >/dev/null 2>&1

json() { # json <cmd> [claude] — a Codex Bash PreToolUse event (turn_id) with the command escaped; "claude": Claude Code's shape
  local c t='"turn_id":"turn-1",'; c="$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | LC_ALL=C awk 'NR > 1 { printf "\\n" } { printf "%s", $0 }')"
  [ "${2:-}" = claude ] && t=""
  printf '{"session_id":"s",%s"cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"}}' "$t" "$CORE_DIR/p/code" "$c"
}
hook_rc() { json "$2" "${3:-}" | bash "$HOOKS/$1" >/dev/null 2>&1; echo $?; }
ran_fake() { # ran_fake <cmd> — run it for real with the fake first on PATH; 0 when the fake started
  : > "$LOG"
  ( cd "$W" && PATH="$BIN:$PATH" timeout 20 bash -c "$1" </dev/null >/dev/null 2>&1 ) 2>/dev/null
  [ -s "$LOG" ]
}
command -v timeout >/dev/null 2>&1 || timeout() { shift; "$@"; }

pad50="$(LC_ALL=C awk 'BEGIN { for (i = 0; i < 51; i++) printf "ls; "; }')"
q51="$(LC_ALL=C awk 'BEGIN { for (i = 0; i < 51; i++) printf "bash -c '"'"'ls; ls'"'"'; " }')"
nl="
"
bigcmd="$(LC_ALL=C awk 'BEGIN { for (i = 0; i < 245; i++) { printf "echo "; for (j = 0; j < 4000; j++) printf "x"; printf "; " } print "apply_patch" }')"
pad5k="$(LC_ALL=C awk 'BEGIN { for (i = 0; i < 5000; i++) printf "x" }')"

bypass=(
  "LESSOPEN='|apply_patch %s' less f.txt"
  "LESSOPEN='||apply_patch %s' cat f.txt"
  "MANPAGER=apply_patch man -l f.txt"
  "PAGER=apply_patch man -l f.txt"
  "GIT_EXTERNAL_DIFF=apply_patch git diff HEAD~0 --ext-diff"
  "GIT_EXTERNAL_DIFF=apply_patch git log -p --ext-diff"
  "${q51}bash -c 'ls;apply_patch'"
  "bash -c 'ls; $pad5k; apply_patch'"
  "bash -c 'ls; $pad5k; ls' ; bash -c apply_patch"
  "git grep --open-f=apply_patch one"
  "git grep --open-files-in-pager=apply_patch one"
  "git grep -nOapply_patch one"
  "git grep -O apply_patch one"
  "git log --out=o5.txt --grep=apply_patch" "git grep --ope=apply_patch one"
  "$BIN/apply_pat?h x" "$BIN/apply_pat[c]h x" "$BIN/appl*_patch x" "cd $BIN && ./app*y_patch x"
  'git grep $IFS--open-files-in-pager=apply_patch one' 'git grep -n $IFS--open-files-in-pager=apply_patch one'
  "man -aPapply_patch ls"
  "man -lP apply_patch f.txt"
  "rg --hostname-bin=apply_patch --hyperlink-format=x one"
  "echo \"\$(cat <<\"EOF\"${nl}a${nl}EOF${nl})\"; apply_patch"
  "x=\"\$(cat <<\"EOF\"${nl}a${nl}EOF${nl})\"${nl}apply_patch"
  "bash -c 'ap\"\"ply_patch'" "sh -c 'a\\pply_patch'" "sh -c \"ap''ply_patch\"" "bash -c '\$\"apply_patch\"'" "eval 'ap\"\"ply_patch'"
  "env bash -c 'a\\pply_patch'" "nohup sh -c 'ap\"\"ply_patch'" "timeout 5 bash -c 'ap\"\"ply_patch'" "echo x | xargs sh -c 'ap\"\"ply_patch'"
  "find . -exec sh -c 'ap\"\"ply_patch' \\;" "time eval 'ap\"\"ply_patch'"
  "LESSOPEN='|ap\"\"ply_patch %s' less f.txt" "LESSOPEN='|a\\pply_patch %s' less f.txt" "MANPAGER='ap\"\"ply_patch' man ls"
  "env MANPAGER='ap\"\"ply_patch' man ls" "export MANPAGER=\"ap''ply_patch\"; man ls" "X='ap\"\"ply_patch'; eval \"\$X\""
  "git -c alias.x='!ap\"\"ply_patch' x" "git -c alias.x='!apply_patch' x" "git -c \"alias.x=!apply_patch\" x" "LESSOPEN='|-apply_patch %s' less f.txt"
  "git config alias.ap '!apply_patch'"
  "${q51}bash -c \"x; apply_pa''tch\"" "${q51}bash -c \"x; a\\pply_patch\"" "${q51}bash -c \"x; \\\"apply\\\"_patch\""
  "bash -c \"x; $pad5k; apply_pa''tch\""
  "echo \$'a\\'b'; apply_patch; echo \$'c'" "\$'\\x61pply_patch'" "\$'apply\\x5fpatch' x" "echo \$'\\x61pply_patch' | sh"
  'echo `echo apply_patch`' 'echo `printf apply_patch` x' 'echo `basename /x/apply_patch`' 'echo `which apply_patch`' 'echo `command -v apply_patch`'
  'echo `cat <<< apply_patch`' 'PAGER=`echo apply_patch` man ls' 'PAGER=$(echo apply_patch) man ls'
  "cat <<EOF${nl}\$(apply_patch)${nl}EOF" "cat <<EOF${nl}\`apply_patch\`${nl}EOF" "bash <<EOF${nl}apply_patch${nl}EOF"
  'printf -v MANPAGER apply_patch; man ls' 'echo apply_patch > s.sh' "less '+!apply_patch' f.txt"
  "$bigcmd"
  # character classes of the name
  "cd $BIN && ./apply_p[[:alpha:]]tch x" "cd $BIN && ./apply[[:punct:]]patch x" "cd $BIN && ./apply_p[^b-z]tch x"
)
twins=(
  "git log --grep=apply_patch"
  "git log --oneline --grep=apply_patch" "grep -E 'apply_patch|applypatch' f.txt" "git commit -m \"apply_patch; hooks\"" "grep -n 'apply_patch(' f.txt"
  "git grep -n apply_patch"
  "git grep -e apply_patch"
  "grep -rn apply_patch ."
  "grep -rn apply_patch . | sort | uniq"
  "rg -e apply_patch ."
  "cat f.txt"
  "${q51}bash -c 'ls;ls'"
  "bash -c 'ls; $pad5k; ls'"
  "git log -S apply_patch"
  "git commit -m \"Adds apply_patch guard\""
  "cat docs/eval-apply_patch.md"
  "ls apply_patch_notes.md"
  "find . -name apply_patch.rs"
  "wc -l apply_patch.md"
  "grep -c apply_patch f.txt | tr -d ' '"
  "rg apply_patch . | cut -d: -f1 | sort -u"
  "git log --grep=apply_patch --format=%H" "git diff --no-ext-diff f.txt" "git show HEAD:f.txt" "find . -name apply_patch.rs -print"
  "grep 'apply_patch\$' f.txt" "grep -e 'apply_patch\$' f.txt" "grep x'y'--pre=apply_patch f.txt" "grep \"a'b\" apply_patch f.txt"
  "grep 'a\"b' apply_patch f.txt" "grep -e'x' apply_patch f.txt" "git log -S'apply_patch'" "find . -name 'apply_patch*'"
  "head -n 5 f.txt | wc -l" "grep	-rn	apply_patch	." "grep    -rn    apply_patch    ."
)

# Documented over-blocking (LIMIT): a hit outside the simple form is refused by both hooks.
limits=( "git commit --allow-empty -m 'Adds apply_patch guard; eval x'" "FOO=apply_patch_x ls" "echo apply_patch" "cd . && grep apply_patch f.txt"
  "grep 'apply_patch f.txt" "grep \"apply_patch f.txt" "rg apply_patch\"\$x\"" "rg 'a'\$'b' apply_patch" "'grep' apply_patch f.txt" "\"rg\" -e apply_patch"
  "grep \\'apply_patch f.txt" "grep apply_patch\\' f.txt" "ls appl[\\\"y]_patch" "grep \"apply_patch\$\" f.txt" "grep 'apply_patch'\$ f.txt" )
for c in "${limits[@]}"; do
  for h in guard-code.sh guard-secrets.sh; do
    rc="$(hook_rc "$h" "$c")"
    [ "$rc" = 2 ] && pass || fail "LIMIT $h rc=$rc (want 2) for: ${c:0:120}"
  done
done
# LIMIT: a quoted part glued to a glob is not recognised (best effort); both hooks let it pass. Only the hook rc is asserted.
quoted_glob_limits=( "cd $BIN && ./app'l'?_patch x" "cd $BIN && ./app\"l\"?_patch x" "cd $BIN && ./app['l']y_patch x" "cd $BIN && ./ap[\"p\"]ly_patch x"
  "cd $BIN && ./app[!'x']y_patch x" "cd $BIN && ./app[a-\"m\"]y_patch x" "cd $BIN && ./app['l'x]y_patch x" )
for c in "${quoted_glob_limits[@]}"; do
  for h in guard-code.sh guard-secrets.sh; do
    rc="$(hook_rc "$h" "$c")"
    [ "$rc" = 0 ] && pass || fail "LIMIT quoted part glued to a glob: $h rc=$rc (want 0) for: ${c:0:120}"
  done
done
for c in "${bypass[@]}"; do
  for h in guard-code.sh guard-secrets.sh; do
    rc="$(hook_rc "$h" "$c")"
    [ "$rc" = 2 ] && pass || fail "$h rc=$rc (want 2) for: ${c:0:120}"
  done
  # Sanity of the danger: where the command can start the fake at all, record it (not asserted: a tool may be absent).
  if ran_fake "$c"; then note "really starts the fake: ${c:0:70}"; fi
done
for c in "${twins[@]}"; do
  for h in guard-code.sh guard-secrets.sh; do
    rc="$(hook_rc "$h" "$c")"
    [ "$rc" = 0 ] && pass || fail "$h rc=$rc (want 0) for: ${c:0:120}"
  done
  if ran_fake "$c"; then fail "twin started the fake: ${c:0:120}"; else pass; fi
done
# The word-splitting bypass is real: the fake is started by it (not only refused by the hook).
ran_fake 'git grep $IFS--open-files-in-pager=apply_patch one' && pass || fail "the \$IFS git grep pager case no longer starts the fake: the bypass test is blind"
# Control: the fake itself works, and a plain apply_patch line is refused (the test is not blind).
ran_fake "apply_patch x" && pass || fail "the fake apply_patch does not run: the check would be blind"
[ "$(hook_rc guard-code.sh "apply_patch x")" = 2 ] && pass || fail "plain apply_patch not refused"
# Claude Code has no apply_patch tool: the refusal does not run there (a program of that name is the person's own), so the
# same inputs pass both hooks when the event has Claude Code's shape and the plugin is not installed under CODEX_HOME
for c in "apply_patch x" "${bypass[0]}" "cd $BIN && ./app*y_patch x" 'rm -rf dist/* && ls'; do
  for h in guard-code.sh guard-secrets.sh; do
    rc="$(hook_rc "$h" "$c" claude)"
    [ "$rc" = 0 ] && pass || fail "claude $h rc=$rc (want 0) for: ${c:0:120}"
  done
done
finish
