# Hook and worktree test helpers. A hook test sources this file after lib.sh:
#   source "$(dirname "$0")/lib.sh"; source "$(dirname "$0")/lib-hook.sh"
# It is no test_*.sh, so run.sh does not run it; tests/test_isolation.sh reads its source line as it reads lib.sh's.

# SM — the start of the refusal of a patch handed to the shell (both guards, in Codex only)
SM="corecrew: run patches with the apply_patch tool, not through the Bash command line; that form cannot be checked"

# json_esc <text> — the text as the inside of a JSON string: backslash, double quote and newline are escaped. A TAB or a
# CR stays as it is: the escaped \t, \r and \/ forms are hand-written inputs of the tests that need them.
# A text with none of the three is printed as it is (bash 3.2 is slow to search a long string).
json_esc() {
  local s="$1"
  case "$s" in *[\\\"$'\n']*) s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}" ;; esac
  printf '%s' "$s"
}

# hook_event <claude|codex> <event> <cwd> [key=value...] — a hook input on stdout, one line, no newline. Synthetic, like
# tests/fixtures/codex: the Codex field names are those of the rust-v0.166.0 structs. The fields, in this order:
#   session_id   always "s"
#   turn_id      Codex only ("turn-1"; turn_id=<id> sets another); Claude Code sends none
#   cwd          <cwd>
#   hook_event_name  <event>; an empty <event> leaves the field out
#   model        model=<name>
#   tool_name, tool_input.command   tool=<name>, command=<text> (JSON-escaped here) or rawcmd=<text already escaped>
#   prompt       prompt=<text> (JSON-escaped here) or rawprompt=<text already escaped>
#   source       source=<startup|resume|compact> (SessionStart)
# rawcmd and rawprompt are for inputs too big to escape in bash (bash 3.2 is slow on long strings): awk writes them.
hook_event() {
  local kind="$1" ev="$2" cwd="$3" a v turn="" model="" tool="" cmd="" hascmd="" prompt="" hasprompt="" src=""
  shift 3
  [ "$kind" = codex ] && turn="turn-1"
  for a in "$@"; do
    v="${a#*=}"
    case "$a" in
      turn_id=*) turn="$v" ;;
      model=*) model="$v" ;;
      tool=*) tool="$v" ;;
      command=*) cmd="$(json_esc "$v")"; hascmd=1 ;;
      rawcmd=*) cmd="$v"; hascmd=1 ;;
      prompt=*) prompt="$(json_esc "$v")"; hasprompt=1 ;;
      rawprompt=*) prompt="$v"; hasprompt=1 ;;
      source=*) src="$v" ;;
      *) echo "hook_event: unknown field: $a" >&2; return 2 ;;
    esac
  done
  printf '{"session_id":"s"'
  [ -z "$turn" ] || printf ',"turn_id":"%s"' "$turn"
  printf ',"cwd":"%s"' "$(json_esc "$cwd")"
  [ -z "$ev" ] || printf ',"hook_event_name":"%s"' "$ev"
  [ -z "$model" ] || printf ',"model":"%s"' "$model"
  [ -z "$tool" ] || printf ',"tool_name":"%s"' "$tool"
  [ -z "$hascmd" ] || printf ',"tool_input":{"command":"%s"}' "$cmd"
  [ -z "$hasprompt" ] || printf ',"prompt":"%s"' "$prompt"
  [ -z "$src" ] || printf ',"source":"%s"' "$src"
  printf '}'
}

# run_hook <hook> <json> — runs the hook on the input: stdout in OUT, stderr in ERR, exit code in RC (also in the files
# out and err under $OD). The hook runs with SIGPIPE ignored, as GitHub's runners often start it: a writer in a
# pipeline whose reader stops early then gets EPIPE and may print "write error: Broken pipe" instead of dying quietly,
# and that noise would reach the user.
run_hook() {
  local d="${OD:-$TEST_TMP}"
  ( trap '' PIPE; printf '%s' "$2" | bash "$1" ) >"$d/out" 2>"$d/err"; RC=$?; OUT="$(<"$d/out")"; ERR="$(<"$d/err")"
}
# hook_ok <label> — exit 0, silent
hook_ok() { assert_eq "$RC" "0" "$1"; assert_eq "$OUT" "" "$1: stdout"; assert_eq "$ERR" "" "$1: stderr"; }
# hook_blocked_any <label> — exit 2, nothing on stdout, a non-empty message (Codex ignores exit 2 with an empty one)
hook_blocked_any() { assert_eq "$RC" "2" "$1"; assert_eq "$OUT" "" "$1: stdout"; [ -n "$ERR" ] && pass || fail "$1: empty stderr"; }
# hook_refused_patch <label> — exit 2, nothing on stdout, the message starts with the shell-patch refusal ($SM)
hook_refused_patch() {
  assert_eq "$RC" "2" "$1"; assert_eq "$OUT" "" "$1: stdout"
  case "$ERR" in "$SM"*) pass ;; *) fail "$1: message: $ERR" ;; esac
}

# proj <path> — the project lib.sh's project-of prints for the path; its exit code is kept
proj() { bash "$SCRIPTS/lib.sh" project-of "$1" 2>/dev/null; }
# wt_of <path> — "<rc> <worktree root> <main checkout>" as lib.sh's worktree_of sets them
wt_of() { ( . "$SCRIPTS/lib.sh"; WT_ROOT=""; WT_MAIN=""; worktree_of "$1"; rc=$?; echo "$rc $WT_ROOT $WT_MAIN" ); }

# poll <tenths> <cmd...> — runs cmd every 0.1 s until it succeeds, at most <tenths> more times; 1 when it never did
poll() { local n="$1"; shift; while ! "$@"; do [ "$n" -gt 0 ] || return 1; n=$((n - 1)); sleep 0.1; done; }

# codex_hooks_list <cwd> <out> — asks the real `codex app-server` (CODEX_HOME from new_sandbox) which hooks it loads for
# <cwd> (request hooks/list). <out> gets the answer split before each hook: line 1 the head, then one line per hook
# starting {"key":"<plugin>@<marketplace>:..., the last one followed by "warnings":[...],"errors":[...]; stderr goes to
# <out>.err. Stdin stays open until the answer is written (polled, up to 10 s); 1 when none came.
codex_hooks_list() {
  local raw="$2.raw"
  printf '%s\n' '{"id":1,"method":"initialize","params":{"clientInfo":{"name":"t","version":"1"}}}' '{"method":"initialized"}' \
    "{\"id\":2,\"method\":\"hooks/list\",\"params\":{\"cwds\":[\"$(json_esc "$1")\"]}}" > "$2.req"
  : > "$raw"
  (cat "$2.req"; poll 100 grep -q '"id":2' "$raw") | codex --disable remote_plugin app-server --listen stdio:// > "$raw" 2> "$2.err"
  grep '"id":2' "$raw" | sed 's/{"key":/\
&/g' > "$2"
  [ -s "$2" ]
}
