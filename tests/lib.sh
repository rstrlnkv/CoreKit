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
# md_section <file> <name> — the body of "## <name>" down to the next "## " heading (### headings stay in it)
md_section() { awk -v n="$2" '$0 == "## " n {f=1; next} /^## /{f=0} f' "$1"; }
# md_section_has <file> <name> <text> — that body contains the text (a fixed string)
md_section_has() { md_section "$1" "$2" | grep -qF -- "$3" && pass || fail "$(basename "$1") section '$2' lacks: $3"; }
# commit_count <repo> — the number of commits on HEAD; 0 when there is no repo or no commit
commit_count() { git -C "$1" rev-list --count HEAD 2>/dev/null || echo 0; }
# no_git_identity <cmd...> — runs cmd with no git identity anywhere: no identity variables, no global or system
# config, a HOME with no config in it, and user.useConfigOnly so git does not guess one from the host name
no_git_identity() {
  env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null HOME="$SANDBOX/nohome" \
    GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.useConfigOnly GIT_CONFIG_VALUE_0=true "$@"
}
# assert_exit <code> <cmd...> — runs cmd, output saved in $OUT
assert_exit() {
  local want="$1"; shift
  OUT="$("$@" 2>&1)"; local got=$?
  [ "$got" = "$want" ] && pass || fail "exit $got (want $want): $* :: $OUT"
}

# Every sandbox of this file lives in one temp folder, removed when the file exits (by finish, or by the
# EXIT trap when the file exits another way). KEEP_SANDBOX=1 keeps it and prints its path.
# The EXIT trap is lib.sh's alone: it stops the fake runs, runs the file's at_exit commands, then removes the
# sandboxes. A test file never sets its own EXIT trap (it would lose the kept sandbox): it calls at_exit.
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/np-test.XXXXXX")" || { echo "lib.sh: cannot make a temp folder" >&2; exit 1; }
TEST_TMP="$(cd -P "$TEST_TMP" && pwd)"
remove_sandboxes() {
  [ -d "$TEST_TMP" ] || return 0
  if [ -n "${KEEP_SANDBOX:-}" ]; then
    [ -n "${KEPT_SAID:-}" ] || echo "kept: $TEST_TMP"; KEPT_SAID=1; return 0
  fi
  chmod -R u+rwx "$TEST_TMP" 2>/dev/null; rm -rf "$TEST_TMP"
}
# at_exit <command> — a command line (run with eval) for the file's own cleanup when it exits, after the earlier ones
AT_EXIT=""
at_exit() { AT_EXIT="$AT_EXIT$1
"; }
# exit_cleanup — what the EXIT trap and finish run; the at_exit commands run once
exit_cleanup() {
  local c="$AT_EXIT"; AT_EXIT=""
  stop_fakes; [ -z "$c" ] || eval "$c"; remove_sandboxes
}
trap exit_cleanup EXIT

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

# snap_tree <dir>... — everything a refusal or a failed step must not change, as text to compare. For each dir: the
# file sums (tree_sum), every path with its type (d, f, l, ? for another kind) and a link's target, and for each git
# repo under it (a .git folder or file) its branch, HEAD, `status --porcelain` and which of REVERT_HEAD, MERGE_HEAD,
# CHERRY_PICK_HEAD and index.lock exist. Read errors (an unreadable folder) are left out.
snap_tree() {
  local d
  for d in "$@"; do
    printf '== %s\n' "$d"
    [ -d "$d" ] || { echo "no folder"; continue; }
    tree_sum "$d" 2>/dev/null
    (cd "$d" && find . -name .git -prune -print -o -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r p; do
      if [ -L "$p" ]; then printf 'l %s -> %s\n' "$p" "$(readlink "$p")"
      elif [ -d "$p" ]; then printf 'd %s\n' "$p"
      elif [ -f "$p" ]; then printf 'f %s\n' "$p"
      else printf '? %s\n' "$p"; fi
    done
    find . -name .git -prune -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r g; do
      r="${g%/.git}"; printf 'repo %s\n' "$r"
      git -C "$r" symbolic-ref -q HEAD 2>&1; git -C "$r" rev-parse -q --verify HEAD 2>&1
      git -C "$r" status --porcelain 2>&1
      git -C "$r" rev-parse --git-path REVERT_HEAD --git-path MERGE_HEAD --git-path CHERRY_PICK_HEAD \
        --git-path index.lock 2>/dev/null | while IFS= read -r m; do
        case "$m" in /*) ;; *) m="$r/$m" ;; esac
        [ ! -e "$m" ] || printf 'has %s\n' "${m##*/}"
      done
    done)
  done
}

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

# Speed is judged by CPU time, not wall time: load on the machine (other test files, -j) raises the wall time of a
# run, not its CPU time. A check that times a real wait (a sleep, a lock, a timeout) stays on wall time.
# cpu_run <cmd...> — runs cmd in this shell, so what it sets (RC, OUT, ERR) and its exit code survive. CPU_MS = the
# user+sys time of this shell and of the children it waited for, in ms (the delta of `times`, both lines). The
# `times` output goes to a file under the section's OD, never through $(...).
cpu_run() {
  local _cr_f="${OD:-$TEST_TMP}/cpu-run" _cr_rc _cr_a
  times > "$_cr_f.a"
  "$@"; _cr_rc=$?
  times > "$_cr_f.b"
  _cpu_file "$_cr_f.a"; _cr_a=$_CPU_T; _cpu_file "$_cr_f.b"; CPU_MS=$((_CPU_T - _cr_a))
  return $_cr_rc
}
# _cpu_file <file> — _CPU_T = the sum, in ms, of the four times in a `times` output ("0m1.234s 0m0.010s", two lines)
_cpu_file() {
  local a b c d t m s i f
  { read -r a b; read -r c d; } < "$1"
  _CPU_T=0
  for t in "$a" "$b" "$c" "$d"; do
    m="${t%%m*}"; s="${t#*m}"; s="${s%s}"; s="${s/,/.}"   # some locales print a decimal comma
    i="${s%%.*}"; f="${s#*.}"; [ "$f" = "$s" ] && f=""
    f="${f}000"; f="${f:0:3}"
    _CPU_T=$((_CPU_T + 10#${m:-0} * 60000 + 10#${i:-0} * 1000 + 10#$f))
  done
}
# assert_linear <label> <ratio> <cmd n> <cmd 4n> — the CPU time of <cmd 4n> is at most <ratio> times that of <cmd n>
# (each command line is run with eval, twice; the faster run counts). Four times the input costs about 3 to 4 times
# the CPU in a linear reader (its fixed start cost lowers the ratio) and 16 times in a quadratic one; a ratio of
# about 6 tells them apart. Size n so that the reader's own work dominates the start cost (at least 25k words).
assert_linear() {
  local _al_a _al_b
  cpu_run eval "$3"; _al_a=$CPU_MS; cpu_run eval "$3"; [ "$CPU_MS" -lt "$_al_a" ] && _al_a=$CPU_MS
  cpu_run eval "$4"; _al_b=$CPU_MS; cpu_run eval "$4"; [ "$CPU_MS" -lt "$_al_b" ] && _al_b=$CPU_MS
  [ "$_al_a" -gt 0 ] || _al_a=1
  [ "$_al_b" -le $(($2 * _al_a)) ] && pass \
    || fail "$1: not linear: 4 times the input took $_al_b ms of CPU against $_al_a ms (more than $2 times)"
}

# exec_shims — builds, once per file, the folder EXEC_SHIMS: a logging shim for every program on PATH (the first folder
# that has a name wins, as in a PATH lookup). A shim appends its name to $EXEC_LOG and execs the real program by its
# path, so the PATH it passes on still starts with the shims. Call it once, before the bg sections that count.
exec_shims() {
  EXEC_SHIMS="$TEST_TMP/exec-shims"
  [ -d "$EXEC_SHIMS" ] && return 0
  local tmp dir f n
  tmp="$(mktemp -d "$TEST_TMP/shims.XXXXXX")" || return 1
  local IFS=:
  for dir in $PATH; do
    case "$dir" in /*) [ -d "$dir" ] || continue ;; *) continue ;; esac
    for f in "$dir"/*; do
      n="${f##*/}"
      case "$f" in *\'*) continue ;; esac   # a quote in a name: not shimmed
      [ -x "$f" ] && [ ! -d "$f" ] && [ ! -e "$tmp/$n" ] || continue
      printf '#!/bin/sh\n[ -z "$EXEC_LOG" ] || printf "%%s\\n" %s >> "$EXEC_LOG"\nexec %s "$@"\n' "'$n'" "'$f'" > "$tmp/$n"
    done
  done
  chmod +x "$tmp"/* && mv "$tmp" "$EXEC_SHIMS"
}
# count_execs <cmd...> — runs cmd in this shell with the shims first on PATH. EXECS = the programs it started through
# PATH, nested ones included; EXEC_LOG = their names, one per line. A program run by its full path, or under a PATH
# the command sets itself, is not counted. Returns cmd's exit code.
count_execs() {
  exec_shims || return 1
  local _ce_path="$PATH" _ce_rc _ce_l
  EXEC_LOG="${OD:-$TEST_TMP}/execs.log"; : > "$EXEC_LOG"; export EXEC_LOG
  PATH="$EXEC_SHIMS:$PATH"
  "$@"; _ce_rc=$?
  PATH="$_ce_path"
  EXECS=0; while IFS= read -r _ce_l; do EXECS=$((EXECS + 1)); done < "$EXEC_LOG"
  return $_ce_rc
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
# stop_fakes — kills every fake run this file started (lib.sh's EXIT trap calls it; it does nothing when there is none)
stop_fakes() {
  [ -n "${FAKES:-}" ] || return 0
  # shellcheck disable=SC2086  # a list of pids
  kill $FAKES 2>/dev/null; FAKES=""
}

# finish — prints the counts, runs exit_cleanup (fake runs, at_exit, sandboxes) and exits: 0 when nothing failed, else 1.
# It cleans up itself, so even an EXIT trap set over lib.sh's cannot leave sandboxes behind.
finish() {
  echo "$(basename "$0"): $PASSES passed, $FAILS failed"
  exit_cleanup
  [ "$FAILS" -eq 0 ] && exit 0
  exit 1
}
