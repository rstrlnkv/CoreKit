# Shared helpers for bash tests. Source this file; call `finish` at the end (it exits).
FAILS=0; PASSES=0
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN="$ROOT/plugins/corecrew"   # the corecrew plugin; the repo root holds the marketplace
SKILL="$PLUGIN/skills/new-project"
SCRIPTS="$PLUGIN/scripts"
# shellcheck disable=SC2034  # HOOKS is for the test files that source this one
HOOKS="$PLUGIN/hooks"

pass() { PASSES=$((PASSES + 1)); }
fail() { FAILS=$((FAILS + 1)); echo "  FAIL: $*"; }
# skip <label> <reason> — a part of this file did not run. run.sh lists every SKIP line after the result.
# To skip the rest of the file: skip <label> <reason>; finish
skip() { printf 'SKIP %s: %s: %s\n' "$(basename "$0")" "$1" "$2"; }
# note <text> — a remark for the reader; printed only with VERBOSE=1
note() { [ -z "${VERBOSE:-}" ] || echo "  note: $*"; }

assert_file()    { [ -f "$1" ] && pass || fail "missing file $1"; }
assert_dir()     { [ -d "$1" ] && pass || fail "missing dir $1"; }
assert_no_file() { [ ! -e "$1" ] && pass || fail "should not exist: $1"; }
assert_contains() { grep -qF -- "$2" "$1" 2>/dev/null && pass || fail "$1 lacks: $2"; }
assert_not_contains() {
  if [ ! -e "$1" ]; then fail "missing file $1 (cannot check it lacks: $2)"
  elif grep -qF -- "$2" "$1"; then fail "$1 contains: $2"
  else pass; fi
}
assert_eq() { [ "$1" = "$2" ] && pass || fail "${3:-values differ}: '$1' != '$2'"; }
# assert_exit <code> <cmd...> — runs cmd, output saved in $OUT
assert_exit() {
  local want="$1"; shift
  OUT="$("$@" 2>&1)"; local got=$?
  [ "$got" = "$want" ] && pass || fail "exit $got (want $want): $* :: $OUT"
}

# Every sandbox of this file lives in one temp folder, removed when the file exits (by finish, or by the
# EXIT trap when the file exits another way). KEEP_SANDBOX=1 keeps it and prints its path.
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/np-test.XXXXXX")" || { echo "lib.sh: cannot make a temp folder" >&2; exit 1; }
TEST_TMP="$(cd -P "$TEST_TMP" && pwd)"
remove_sandboxes() {
  [ -d "$TEST_TMP" ] || return 0
  if [ -n "${KEEP_SANDBOX:-}" ]; then
    [ -n "${KEPT_SAID:-}" ] || echo "kept: $TEST_TMP"; KEPT_SAID=1; return 0
  fi
  chmod -R u+rwx "$TEST_TMP" 2>/dev/null; rm -rf "$TEST_TMP"
}
trap remove_sandboxes EXIT

# Fresh sandbox: exports CORE_DIR inside a new temp dir; git identity for commits; HOME, XDG and
# git config isolated (see below).
new_sandbox() {
  SANDBOX="$(mktemp -d "$TEST_TMP/sb.XXXXXX")"
  SANDBOX="$(cd -P "$SANDBOX" && pwd)"   # physical path: scripts print canonical paths
  export CORE_DIR="$SANDBOX/Projects/Core"
  export CLAUDE_PLUGIN_DATA="$SANDBOX/plugin-data"   # never the real ~/.claude
  unset CORECREW_CONFIG   # the settings file is looked up under the sandbox XDG_CONFIG_HOME
  # Nothing from the developer's machine: no real HOME, XDG config, global or system git config
  # (a global excludes file, init.defaultBranch, ...). Git identity comes from the env vars below.
  mkdir -p "$SANDBOX/home" "$SANDBOX/xdg"; : > "$SANDBOX/gitconfig"
  export HOME="$SANDBOX/home" XDG_CONFIG_HOME="$SANDBOX/xdg" GIT_CONFIG_GLOBAL="$SANDBOX/gitconfig" GIT_CONFIG_NOSYSTEM=1
  export CODEX_HOME="$SANDBOX/codex-home"   # a test that runs codex never touches the real ~/.codex
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
  mv "$(dirname "$CORE_DIR")/$1" "$CORE_DIR/$1/code" && rm -f "$CORE_DIR/$1/code/CLAUDE.local.md" "$CORE_DIR/$1/code/AGENTS.md"
}

# sync_tools — copies the plugin's scripts into $COREDEV_TOOLS (what session-start does),
# so git hook shims installed in the sandbox have something to run.
sync_tools() { bash "$SCRIPTS/sync-tools.sh" "$PLUGIN" "$COREDEV_TOOLS" >/dev/null; }

# Checksum of all files under a dir, excluding .git internals.
# (NUL-separated, so names with spaces or non-ASCII characters are summed too.)
tree_sum() { (cd "$1" && find . -type f -not -path '*/.git/*' -print0 | xargs -0 cksum | LC_ALL=C sort -k3); }

# path_without <tool>... — prints a PATH (one new folder in the sandbox) with a link to every command of the current
# PATH except the named tools; the first folder that has a name wins, as in a PATH lookup. "/usr/bin:/bin" does not
# hide a tool: a Linux runner keeps gh in /usr/bin beside git.
path_without() {
  local d dir f n skip t links
  d="$(mktemp -d "$SANDBOX/path.XXXXXX")" || return 1
  local IFS=:
  for dir in $PATH; do
    [ -n "$dir" ] && [ -d "$dir" ] || continue
    links=()
    for f in "$dir"/*; do
      n="${f##*/}"; skip=0
      for t in "$@"; do [ "$n" = "$t" ] && skip=1; done
      [ $skip -eq 0 ] && [ -x "$f" ] && [ ! -d "$f" ] && [ ! -e "$d/$n" ] && links[${#links[@]}]="$f"
    done
    [ ${#links[@]} -eq 0 ] || ln -s "${links[@]}" "$d/" 2>/dev/null
  done
  printf '%s' "$d"
}

# bg <function> — runs a section of a test file in the background: a subshell with its own counts and its own
# scratch folder OD. Sections that share nothing run at the same time this way. bg_wait waits for all of them,
# prints their output in the order they were started and adds their counts. A section must not call finish.
BGN=0
bg() {
  BGN=$((BGN + 1)); local n=$BGN
  ( OD="$TEST_TMP/bg$n"; mkdir -p "$OD"; FAILS=0; PASSES=0; "$1"; echo "$PASSES $FAILS" > "$TEST_TMP/bg$n.count" ) > "$TEST_TMP/bg$n.log" 2>&1 &
}
bg_wait() {
  local n p f
  wait
  for n in $(seq 1 $BGN); do
    cat "$TEST_TMP/bg$n.log"
    if [ -f "$TEST_TMP/bg$n.count" ]; then read -r p f < "$TEST_TMP/bg$n.count"; PASSES=$((PASSES + p)); FAILS=$((FAILS + f))
    else fail "background section $n did not finish"; fi
  done
}

# fake <cwd> <argv0> — starts a fake test run for hooks/one-suite.sh: a `sleep 120` renamed to <argv0> (exec -a)
# whose working folder is <cwd>. Its pid goes in FAKE_PID and in FAKES. It returns once ps shows the new name
# (it polls every 0.1 s, up to 5 s), so a hook run right after it can see the run. The hook holds a call only
# for a run whose working folder is in the same place as the call.
FAKES=""
fake() {
  bash -c 'cd "$1" && exec -a "$2" sleep 120' _ "$1" "$2" >/dev/null 2>&1 & FAKE_PID=$!
  disown "$FAKE_PID" 2>/dev/null; FAKES="$FAKES $FAKE_PID"
  local i=0
  while [ $i -lt 50 ]; do
    case "$(ps -ww -p "$FAKE_PID" -o args= 2>/dev/null)" in "$2"*) return 0 ;; esac
    sleep 0.1; i=$((i + 1))
  done
  fail "the fake run '$2' did not start in 5 s"
}
# stop <pid>... — kills fake runs and waits (polling every 0.1 s, up to 2 s each) until they are gone
stop() {
  local p i
  kill "$@" 2>/dev/null
  for p in "$@"; do i=0; while kill -0 "$p" 2>/dev/null && [ $i -lt 20 ]; do sleep 0.1; i=$((i + 1)); done; done
}
# stop_fakes — kills every fake run this file started. A file that calls fake calls this in its EXIT trap.
stop_fakes() {
  [ -n "${FAKES:-}" ] || return 0
  # shellcheck disable=SC2086  # a list of pids
  kill $FAKES 2>/dev/null; FAKES=""
}

# finish — prints the counts, removes the sandboxes and exits: 0 when nothing failed, else 1.
# It exits, so a file's own EXIT trap (which replaces the one above) cannot leave sandboxes behind.
finish() {
  echo "$(basename "$0"): $PASSES passed, $FAILS failed"
  remove_sandboxes
  [ "$FAILS" -eq 0 ] && exit 0
  exit 1
}
