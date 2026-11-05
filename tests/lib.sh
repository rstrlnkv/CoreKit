# Shared helpers for bash tests. Source this file; call `finish` at the end.
FAILS=0; PASSES=0
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN="$ROOT/plugins/corecrew"   # the corecrew plugin; the repo root holds the marketplace
SKILL="$PLUGIN/skills/new-project"
SCRIPTS="$PLUGIN/scripts"
HOOKS="$PLUGIN/hooks"

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

# Fresh sandbox: exports CORE_DIR inside a new temp dir; git identity for commits; HOME, XDG and
# git config isolated (see below).
new_sandbox() {
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/np-test.XXXXXX")"
  SANDBOX="$(cd -P "$SANDBOX" && pwd)"   # physical path: scripts print canonical paths
  export CORE_DIR="$SANDBOX/Projects/Core"
  export CLAUDE_PLUGIN_DATA="$SANDBOX/plugin-data"   # never the real ~/.claude
  # Nothing from the developer's machine: no real HOME, XDG config, global or system git config
  # (a global excludes file, init.defaultBranch, ...). Git identity comes from the env vars below.
  mkdir -p "$SANDBOX/home" "$SANDBOX/xdg"; : > "$SANDBOX/gitconfig"
  export HOME="$SANDBOX/home" XDG_CONFIG_HOME="$SANDBOX/xdg" GIT_CONFIG_GLOBAL="$SANDBOX/gitconfig" GIT_CONFIG_NOSYSTEM=1
  export COREDEV_TOOLS="$CLAUDE_PLUGIN_DATA/tools"
  export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
  export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
}

# setup_core — creates the Core skeleton in $CORE_DIR (what scaffold.sh requires).
# The Core template no longer ignores */code/ (code lives beside the Core); tests still built in the
# old layout (<Core>/<name>/code) get the line back, folded into the setup commit.
setup_core() {
  bash "$SCRIPTS/setup-core.sh" "$CORE_DIR" >/dev/null || return 1
  printf '*/code/\n' >> "$CORE_DIR/.gitignore"
  git -C "$CORE_DIR" add .gitignore && git -C "$CORE_DIR" commit -q --amend --no-edit
}

# scaffold_old <name> — scaffold, then put the code folder where the old layout had it
# (<Core>/<name>/code), for tests of the old-layout paths. Silent.
scaffold_old() {
  bash "$SKILL/scripts/scaffold.sh" --name "$1" >/dev/null || return 1
  mv "$(dirname "$CORE_DIR")/$1" "$CORE_DIR/$1/code" && rm -f "$CORE_DIR/$1/code/CLAUDE.local.md"
}

# sync_tools — copies the plugin's scripts into $COREDEV_TOOLS (what session-start does),
# so git hook shims installed in the sandbox have something to run.
sync_tools() { bash "$SCRIPTS/sync-tools.sh" "$PLUGIN" "$COREDEV_TOOLS" >/dev/null; }

# Checksum of all files under a dir, excluding .git internals.
# (NUL-separated, so names with spaces or non-ASCII characters are summed too.)
tree_sum() { (cd "$1" && find . -type f -not -path '*/.git/*' -print0 | xargs -0 cksum | LC_ALL=C sort -k3); }

finish() {
  echo "$(basename "$0"): $PASSES passed, $FAILS failed"
  [ "$FAILS" -eq 0 ]
}
