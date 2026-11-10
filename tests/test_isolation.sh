#!/usr/bin/env bash
# The sandbox must not see the developer's HOME, XDG config or global/system git config.
source "$(dirname "$0")/lib.sh"
REAL_HOME="$HOME"
# a planted outer value (never the real one): new_sandbox must replace it, not keep it
export CORE_DIR="$TEST_TMP/outer-core" CLAUDE_PLUGIN_DATA="$TEST_TMP/outer-data"
new_sandbox
case "$HOME" in "$SANDBOX"/*) pass ;; *) fail "HOME not in the sandbox: $HOME" ;; esac
case "${XDG_CONFIG_HOME:-}" in "$SANDBOX"/*) pass ;; *) fail "XDG_CONFIG_HOME not in the sandbox: ${XDG_CONFIG_HOME:-}" ;; esac
case "${CODEX_HOME:-}" in "$SANDBOX"/*) pass ;; *) fail "CODEX_HOME not in the sandbox: ${CODEX_HOME:-}" ;; esac
case "${CORE_DIR:-}" in "$SANDBOX"/*) pass ;; *) fail "CORE_DIR not in the sandbox: ${CORE_DIR:-}" ;; esac
case "${CLAUDE_PLUGIN_DATA:-}" in "$SANDBOX"/*) pass ;; *) fail "CLAUDE_PLUGIN_DATA not in the sandbox: ${CLAUDE_PLUGIN_DATA:-}" ;; esac
assert_eq "$GIT_CONFIG_GLOBAL" "$SANDBOX/gitconfig" "GIT_CONFIG_GLOBAL"
assert_eq "$GIT_CONFIG_NOSYSTEM" "1" "GIT_CONFIG_NOSYSTEM"
[ "$HOME" != "$REAL_HOME" ] && pass || fail "HOME is the real one"
assert_eq "$(git config --global --get core.excludesFile)" "" "global excludesFile"
assert_eq "$(git config --global --list | grep -c '^user\.')" "0" "global git identity leaked in"
# the default excludes file (from XDG/HOME) is not the developer's: settings.local.json is not ignored
mkdir -p "$SANDBOX/r/.claude"; git init -q "$SANDBOX/r"; : > "$SANDBOX/r/.claude/settings.local.json"
git -C "$SANDBOX/r" check-ignore -q .claude/settings.local.json && fail "settings.local.json ignored by a global excludes file" || pass
# a global setting lands in the sandbox file, not in the real one (never write unless isolated)
[ "$GIT_CONFIG_GLOBAL" = "$SANDBOX/gitconfig" ] && [ "$HOME" != "$REAL_HOME" ] \
  || { fail "sandbox not isolated; skipping the global write"; finish; exit 1; }
git config --global test.isolation yes
assert_contains "$SANDBOX/gitconfig" "isolation = yes"

# Every test file that runs code (a script by a variable path, claude, codex, git config --global or --system)
# calls new_sandbox. A file run on its own has no throwaway HOME from run.sh, so without new_sandbox it would
# write the developer's files.
# runs_code <file> — the file runs code (comment lines and the source lines of lib.sh and lib-hook.sh do not count)
runs_code() {
  grep -v '^[[:space:]]*#' "$1" | grep -vF -e 'source "$(dirname "$0")/lib.sh"' -e 'source "$(dirname "$0")/lib-hook.sh"' \
    | grep -qE '(^|[^[:alnum:]_-])(bash|sh|source|\.) +"?\$|(^|[;&|(`]|then |do |assert_exit [0-9]+ )[[:space:]]*(command +)?(claude|codex|git config --(global|system)) '
}
has_sandbox() { grep -qE '(^|[;&(]|then |do )[[:space:]]*new_sandbox' "$1"; }
# self-check on fixtures: a hook run, claude, codex and a global git config count; a comment, a read or the words
# 'git config --global' in an assert's text do not; new_sandbox clears it
F="$SANDBOX/fx"; mkdir -p "$F"
printf 'source "$(dirname "$0")/lib.sh"\nbash "$HOOKS/guard-code.sh" < x\n' > "$F/hook"
printf 'source "$(dirname "$0")/lib.sh"\nassert_exit 0 claude plugin validate "$P"\n' > "$F/claude"
printf 'source "$(dirname "$0")/lib.sh"\nif true; then codex exec x; fi\n' > "$F/codex"
printf 'source "$(dirname "$0")/lib.sh"\ngit config --global x.y z\n' > "$F/gitcfg"
printf 'source "$(dirname "$0")/lib.sh"\nsource "$(dirname "$0")/lib-hook.sh"\n# bash "$HOOKS/x.sh"\nassert_contains "$SCRIPTS/save" bash\nassert_not_contains "$SK" "git config --global"\n' > "$F/reads"
printf 'source "$(dirname "$0")/lib.sh"\nnew_sandbox\nbash "$HOOKS/guard-code.sh" < x\n' > "$F/sandboxed"
for x in hook claude codex gitcfg; do runs_code "$F/$x" && pass || fail "runs_code misses the $x fixture"; done
runs_code "$F/reads" && fail "runs_code counts a comment, a read or the helper source lines" || pass
has_sandbox "$F/sandboxed" && pass || fail "has_sandbox misses new_sandbox"
has_sandbox "$F/hook" && fail "has_sandbox sees a sandbox in a file without one" || pass
for t in "$ROOT"/tests/test_*.sh; do
  runs_code "$t" || continue
  has_sandbox "$t" && pass || fail "$(basename "$t") runs code without new_sandbox"
done

[ -z "${CORECREW_CONFIG:-}" ] && pass || fail "CORECREW_CONFIG leaks into the sandbox"
finish
