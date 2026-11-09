#!/usr/bin/env bash
# Characterisation of hooks/session-start.sh (Claude host): its output must stay byte-identical when work
# moves out of it into scripts/prepare.sh. Golden file: tests/fixtures/session-start-golden.txt
# (regenerate on purpose with GOLDEN_WRITE=1; sandbox paths are shown as @SB@, the plugin folder as @PL@).
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/lib-hook.sh"
new_sandbox
H="$HOOKS/session-start.sh"
export CLAUDE_PLUGIN_ROOT="$PLUGIN" COREKIT_HOST=claude
unset CLAUDE_PLUGIN_OPTION_CORE_DIR
G="$ROOT/tests/fixtures/session-start-golden.txt"; ACT="$SANDBOX/actual.txt"
case_run() {   # case_run <label> <cwd> — stdout and stderr, exit code
  { echo "== $1"; hook_event claude SessionStart "$2" source=startup | bash "$H" 2>&1; echo "rc=$?"; } >> "$SANDBOX/raw.txt"
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
mkdir -p "$C/.git/hooks"; printf '#!/bin/sh\n# new-project hook\n' > "$C/.git/hooks/pre-commit"
printf 'schema: 1\n' > "$CORE_DIR/.coredev"
case_run "layout note + stale hook" "$C"
case_run "from the Core project folder" "$P"
sed -e "s|$SANDBOX|@SB@|g" -e "s|$PLUGIN|@PL@|g" "$SANDBOX/raw.txt" > "$ACT"
if [ "${GOLDEN_WRITE:-}" = 1 ]; then cp "$ACT" "$G"; echo "golden written"; fi
if cmp -s "$ACT" "$G"; then pass; else fail "session-start output changed: $(diff "$G" "$ACT" | head -20)"; fi
finish
