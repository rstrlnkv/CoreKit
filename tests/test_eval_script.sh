#!/usr/bin/env bash
# scripts/eval.sh: the repo tool that runs a plugin's trigger evals on an assembled copy (plugin + evals/<plugin>/).
# A stub `claude` stands in for the real one: no model call is made here.
source "$(dirname "$0")/lib.sh"
new_sandbox
B="$ROOT/scripts/eval.sh"
assert_file "$B"

# the stub: logs its arguments one per line, what the target folder holds, and writes one result file
BIN="$SANDBOX/bin"; LOG="$SANDBOX/claude.log"; mkdir -p "$BIN"
cat > "$BIN/claude" <<'EOF'
#!/usr/bin/env bash
{ printf 'arg %s\n' "$@"
  [ -f "$3/.claude-plugin/plugin.json" ] && echo "has manifest"
  for c in "$3"/evals/*/; do [ -d "$c" ] && echo "case $(basename "$c")"; done
  [ -f "$3/evals/.gitignore" ] && echo "has gitignore"
} > "$STUB_LOG"
if [ -n "${STUB_RESULT:-}" ]; then mkdir -p "$3/evals/results" && echo scored > "$3/evals/results/run.json"; fi
echo "stub ran"
exit "${STUB_RC:-0}"
EOF
chmod +x "$BIN/claude"
# run_eval <script> <args...> — runs the script with the stub first on PATH; output in $OUT (assert_exit)
run_eval() { local want="$1"; shift; assert_exit "$want" env PATH="$BIN:$PATH" STUB_LOG="$LOG" bash "$@"; }
# stub_dir — the folder the stub was given (its third argument)
stub_dir() { sed -n '3s/^arg //p' "$LOG"; }

# --- the real tree: each plugin that has evals is handed over whole, with its cases inside
for pl in corecrew coreopinion; do
  : > "$LOG"
  run_eval 0 "$B" "$pl"
  assert_contains "$LOG" "has manifest"
  d="$(stub_dir)"
  assert_eq "$(basename "$d")" "$pl" "$pl: the staged folder has the plugin's name"
  assert_eq "$(grep '^arg ' "$LOG" | tr '\n' ' ')" "arg plugin arg eval arg $d arg --ablation arg none arg --no-publish " "$pl: the command"
  want="$(for c in "$ROOT/evals/$pl"/*/; do echo "case $(basename "$c")"; done)"
  assert_eq "$(grep '^case ' "$LOG")" "$want" "$pl: the staged cases"
  [ -n "$want" ] && pass || fail "$pl: no case folder under evals/$pl"
  # the copy is a throwaway one, outside the repo, and it is gone after the run
  case "$d" in "$ROOT"/*) fail "$pl: staged inside the repo: $d" ;; *) pass ;; esac
  assert_no_file "$(dirname "$d")"
done

# --- a small repo of its own: results come back, extra arguments pass through, the exit code is claude's
R="$SANDBOX/repo"; mkdir -p "$R/scripts" "$R/plugins/demo/.claude-plugin" "$R/plugins/demo/skills" "$R/evals/demo/one/graders" "$R/evals/demo/two"
cp "$B" "$R/scripts/eval.sh"
echo '{"name": "demo"}' > "$R/plugins/demo/.claude-plugin/plugin.json"
echo 'p' > "$R/evals/demo/one/prompt.md"; echo 'results/' > "$R/evals/demo/.gitignore"
: > "$LOG"
STUB_RESULT=1 run_eval 0 "$R/scripts/eval.sh" demo --case 'one*'
printf '%s\n' "$OUT" | grep -qx 'stub ran' && pass || fail "claude's output is not shown: $OUT"
assert_eq "$(grep '^case ' "$LOG" | tr '\n' ' ')" "case one case two " "demo: the staged cases"
assert_contains "$LOG" "has gitignore"
assert_eq "$(sed -n '4,$p' "$LOG" | grep '^arg ' | tr '\n' ' ')" "arg --ablation arg none arg --no-publish arg --case arg one* " "extra arguments follow the fixed ones"
assert_eq "$(cat "$R/evals/demo/results/run.json" 2>/dev/null)" "scored" "the results come back to evals/demo/results/"
assert_no_file "$R/plugins/demo/evals"
assert_no_file "$(dirname "$(stub_dir)")"
STUB_RC=3 run_eval 3 "$R/scripts/eval.sh" demo
# the results of an earlier run stay in the repo folder: the copy starts without them
assert_file "$R/evals/demo/results/run.json"
assert_eq "$(grep '^case ' "$LOG" | tr '\n' ' ')" "case one case two " "demo: earlier results are not staged"
assert_no_file "$(dirname "$(stub_dir)")"
# a plugin of the copy is the plugin as it is: nothing of the repo's plugin folder changes
assert_eq "$(cd "$R" && find plugins -type f | LC_ALL=C sort | tr '\n' ' ')" "plugins/demo/.claude-plugin/plugin.json " "the plugin folder is untouched"

# --- refusals: exit 2, usage or reason on stderr, claude not called
mkdir -p "$R/plugins/bare/.claude-plugin"; echo '{"name": "bare"}' > "$R/plugins/bare/.claude-plugin/plugin.json"
for args in "" "nosuch" "bare" "../demo" "demo/x" "demo/../demo" ".claude"; do
  : > "$LOG"
  # shellcheck disable=SC2086  # an empty $args is no argument on purpose
  run_eval 2 "$R/scripts/eval.sh" $args
  case "$OUT" in eval.sh:*) pass ;; *) fail "refusal '$args' does not start with eval.sh: $OUT" ;; esac
  [ ! -s "$LOG" ] && pass || fail "claude was called for '$args'"
done
run_eval 2 "$R/scripts/eval.sh"
case "$OUT" in *"usage: bash scripts/eval.sh <plugin>"*) pass ;; *) fail "no usage line: $OUT" ;; esac
run_eval 2 "$R/scripts/eval.sh" bare
case "$OUT" in *"evals/bare"*) pass ;; *) fail "the missing evals folder is not named: $OUT" ;; esac

# --- no claude on PATH: exit 1 and a line that says so
NOCL="$SANDBOX/nocl"; mkdir -p "$NOCL"
for t in bash dirname basename mktemp cp rm mkdir env; do
  p="$(command -v "$t")" && ln -s "$p" "$NOCL/$t"
done
assert_exit 1 env PATH="$NOCL" bash "$R/scripts/eval.sh" demo
case "$OUT" in *"claude is not on PATH"*) pass ;; *) fail "no line about the missing claude: $OUT" ;; esac
finish
