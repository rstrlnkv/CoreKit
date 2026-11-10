#!/usr/bin/env bash
# Pins the whole output of hooks/session-start.sh (stdout, stderr and exit code) byte for byte in seven cases: no Core;
# a ready Core, outside a project; a new-layout project whose links are created, then current; a real CLAUDE.local.md;
# a layout note with a stale git hook; and the Core's own project folder. A change to any of these texts fails here
# until the golden file is regenerated on purpose. Golden file: tests/fixtures/session-start-golden.txt, the Claude
# Code output (GOLDEN_WRITE=1 rewrites it; sandbox paths are shown as @SB@, the plugin folder as @PL@). The same cases
# run through the hook as Codex calls it (its SessionStart input, COREKIT_HOST=codex): that output must equal the golden
# with each /corecrew: written $corecrew:, so there is no second golden file.
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/lib-hook.sh"
H="$HOOKS/session-start.sh"
G="$ROOT/tests/fixtures/session-start-golden.txt"
unset CLAUDE_PLUGIN_OPTION_CORE_DIR
export CLAUDE_PLUGIN_ROOT="$PLUGIN"

# run_cases <claude|codex> — every case in a fresh sandbox, as that host calls the hook; ACT holds the output with
# the sandbox and plugin paths replaced
run_cases() {
  local host="$1" ev=""
  new_sandbox
  export COREKIT_HOST="$host"
  ACT="$SANDBOX/actual.txt"
  [ "$host" = codex ] && ev="model=gpt-5.5"
  case_run() {   # case_run <label> <cwd> — stdout and stderr, exit code
    # shellcheck disable=SC2086  # ev is empty or one word
    { echo "== $1"; hook_event "$host" SessionStart "$2" source=startup $ev | bash "$H" 2>&1; echo "rc=$?"; } >> "$SANDBOX/raw.txt"
  }
  mkdir -p "$SANDBOX/elsewhere"
  case_run "no core" "$SANDBOX/elsewhere"
  setup_core
  case_run "core ready, elsewhere" "$SANDBOX/elsewhere"
  bash "$SKILL/scripts/scaffold.sh" --name gold >/dev/null
  P="$CORE_DIR/gold"; C="$(dirname "$CORE_DIR")/gold"
  printf -- '---\nname: alpha\n---\n' > "$CORE_DIR/standards/alpha.md"
  printf 'Rule one.\n' > "$CORE_DIR/session-rules.md"
  rm -f "$C/CLAUDE.local.md" "$C/AGENTS.md"
  case_run "new layout, links created" "$C"
  case_run "new layout, links current" "$C"
  rm -f "$C/CLAUDE.local.md"; printf 'mine\n' > "$C/CLAUDE.local.md"
  case_run "real CLAUDE.local.md" "$C"
  rm -f "$C/CLAUDE.local.md"
  printf 'schema: 1\n' > "$CORE_DIR/.coredev"
  case_run "layout note" "$C"
  case_run "from the Core project folder" "$P"
  sed -e "s|$SANDBOX|@SB@|g" -e "s|$PLUGIN|@PL@|g" "$SANDBOX/raw.txt" > "$ACT"
}

run_cases claude
if [ "${GOLDEN_WRITE:-}" = 1 ]; then cp "$ACT" "$G"; echo "golden written"; fi
if cmp -s "$ACT" "$G"; then pass; else fail "session-start output changed: $(diff "$G" "$ACT" | head -20)"; fi

# Codex names the skills $corecrew:<skill> (hooks/messages.sh); only the "no core" case carries a /corecrew: name
run_cases codex
sed 's|/corecrew:|$corecrew:|g' "$G" > "$SANDBOX/want.txt"
if cmp -s "$ACT" "$SANDBOX/want.txt"; then pass; else fail "session-start output in Codex changed: $(diff "$SANDBOX/want.txt" "$ACT" | head -20)"; fi
finish
