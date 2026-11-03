# Shared helpers for bash tests. Source this file; call `finish` at the end.
FAILS=0; PASSES=0
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$ROOT/skills/new-project"
SCRIPTS="$ROOT/scripts"
HOOKS="$ROOT/hooks"

pass() { PASSES=$((PASSES + 1)); }
fail() { FAILS=$((FAILS + 1)); echo "  FAIL: $*"; }

assert_file()    { [ -f "$1" ] && pass || fail "missing file $1"; }
assert_dir()     { [ -d "$1" ] && pass || fail "missing dir $1"; }
assert_no_file() { [ ! -e "$1" ] && pass || fail "should not exist: $1"; }
assert_contains() { grep -qF -- "$2" "$1" 2>/dev/null && pass || fail "$1 lacks: $2"; }
assert_not_contains() { grep -qF -- "$2" "$1" 2>/dev/null && fail "$1 contains: $2" || pass; }
assert_eq() { [ "$1" = "$2" ] && pass || fail "${3:-values differ}: '$1' != '$2'"; }
# assert_exit <code> <cmd...> — runs cmd, output saved in $OUT
assert_exit() {
  local want="$1"; shift
  OUT="$("$@" 2>&1)"; local got=$?
  [ "$got" = "$want" ] && pass || fail "exit $got (want $want): $* :: $OUT"
}

# Fresh sandbox: exports CORE_DIR inside a new temp dir; git identity for commits.
new_sandbox() {
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/np-test.XXXXXX")"
  SANDBOX="$(cd -P "$SANDBOX" && pwd)"   # physical path: scripts print canonical paths
  export CORE_DIR="$SANDBOX/Projects/Core"
  export CLAUDE_PLUGIN_DATA="$SANDBOX/plugin-data"   # never the real ~/.claude
  export COREDEV_TOOLS="$CLAUDE_PLUGIN_DATA/tools"
  export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
  export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
}

# setup_core — creates the Core skeleton in $CORE_DIR (what scaffold.sh requires).
setup_core() { bash "$SCRIPTS/setup-core.sh" "$CORE_DIR" >/dev/null; }

# sync_tools — copies the plugin's scripts into $COREDEV_TOOLS (what session-start does),
# so git hook shims installed in the sandbox have something to run.
sync_tools() { bash "$SCRIPTS/sync-tools.sh" "$ROOT" "$COREDEV_TOOLS" >/dev/null; }

# Checksum of all files under a dir, excluding .git internals.
# (NUL-separated, so names with spaces or non-ASCII characters are summed too.)
tree_sum() { (cd "$1" && find . -type f -not -path '*/.git/*' -print0 | xargs -0 cksum | LC_ALL=C sort -k3); }

finish() {
  echo "$(basename "$0"): $PASSES passed, $FAILS failed"
  [ "$FAILS" -eq 0 ]
}
