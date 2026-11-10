#!/usr/bin/env bash
# Runs tests/test_*.sh; exits non-zero if any fails.
#   bash tests/run.sh [-j N] [word ...]
#   word ...        run only the files whose name contains one of the words (run.sh guard patch)
#   -j N            run N files at a time (each file has its own HOME, TMPDIR and sandboxes)
#   VERBOSE=1       print every file's output, not only a failing file's
#   KEEP_SANDBOX=1  keep the run's temp folder and print its path
# Prints one line per file with its time, then ALL TESTS PASSED or SOME TESTS FAILED, then every skip.
# Every file runs with HOME, XDG_CONFIG_HOME, CODEX_HOME, GIT_CONFIG_GLOBAL and TMPDIR in its own folder
# under one throwaway root, so a file that forgets new_sandbox still cannot touch the developer's files.
# REAL_CORE_DIR names the developer's real Core; only test_no_personal.sh gets it (and only reads it).
cd "$(dirname "$0")" || exit 1
HERE="$(pwd)"

# run.sh --one <n> <file> — runs one file in $RUN_ROOT/<n>; writes out, rc and secs there (xargs calls this)
if [ "${1:-}" = "--one" ]; then
  case "$3" in test_no_personal.sh) ;; *) unset REAL_CORE_DIR ;; esac
  d="$RUN_ROOT/$2"; mkdir -p "$d/home" "$d/xdg" "$d/codex" "$d/tmp"; : > "$d/gitconfig"
  start=$(date +%s)
  HOME="$d/home" XDG_CONFIG_HOME="$d/xdg" CODEX_HOME="$d/codex" GIT_CONFIG_GLOBAL="$d/gitconfig" \
    GIT_CONFIG_NOSYSTEM=1 TMPDIR="$d/tmp" bash "$HERE/$3" > "$d/out" 2>&1 < /dev/null
  echo $? > "$d/rc"; echo $(( $(date +%s) - start )) > "$d/secs"
  exit 0
fi

# The real Core, found before the files get a throwaway HOME: test_no_personal.sh reads its PROJECTS.md (and only
# reads it). CORE_DIR when set, else ~/Projects/Core; a value already set (a nested run) is kept. It is exported
# for the --one runs, and each run but test_no_personal.sh's drops it (above).
REAL_CORE_DIR="${REAL_CORE_DIR:-${CORE_DIR:-$HOME/Projects/Core}}"
readonly REAL_CORE_DIR; export REAL_CORE_DIR

jobs=1
if [ "${1:-}" = "-j" ]; then
  case "${2:-}" in ''|*[!0-9]*|0) echo "run.sh: -j needs a number of files at a time" >&2; exit 2 ;; esac
  jobs="$2"; shift 2
fi
files=""
for t in test_*.sh; do
  if [ $# -gt 0 ]; then
    m=0; for w in "$@"; do case "$t" in *"$w"*) m=1 ;; esac; done
    [ $m = 1 ] || continue
  fi
  files="$files $t"
done
[ -n "$files" ] || { echo "run.sh: no test file matches: $*" >&2; exit 2; }

RUN_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/np-run.XXXXXX")" || exit 1
RUN_ROOT="$(cd -P "$RUN_ROOT" && pwd)"; export RUN_ROOT
cleanup() {
  if [ -n "${KEEP_SANDBOX:-}" ]; then echo "kept: $RUN_ROOT"
  else chmod -R u+rwx "$RUN_ROOT" 2>/dev/null; rm -rf "$RUN_ROOT"; fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

rc=0
# report <n> <file> — the file's line, its output when it failed (or VERBOSE=1), its skips into $RUN_ROOT/skips
report() {
  local d="$RUN_ROOT/$1" r s
  r="$(cat "$d/rc" 2>/dev/null)"; s="$(cat "$d/secs" 2>/dev/null)"
  if [ "$r" = 0 ]; then
    printf 'ok   %s (%s s)\n' "$2" "${s:-?}"
    [ -z "${VERBOSE:-}" ] || cat "$d/out"
  else
    rc=1; printf 'FAIL %s (%s s)\n' "$2" "${s:-?}"; cat "$d/out"
  fi
  # SKIP lines (the old forms name no file: the file is added)
  sed -n -E -e 's/^[[:space:]]*SKIP //p' "$d/out" \
    | while IFS= read -r l; do
        case "$l" in "$2: "*) echo "SKIP $l" ;; *) echo "SKIP $2: $l" ;; esac
      done >> "$RUN_ROOT/skips"
}

t0=$(date +%s); n=0
if [ "$jobs" = 1 ]; then
  for t in $files; do n=$((n + 1)); bash "$HERE/run.sh" --one "$n" "$t"; report "$n" "$t"; done
else
  # the largest files start first (size stands in for run time), so a slow file does not start last; the report
  # below keeps the alphabetical order
  for t in $files; do n=$((n + 1)); echo "$(( $(wc -c < "$t") )) $n $t"; done | sort -k1,1nr -k2,2n | cut -d' ' -f2- \
    | xargs -P "$jobs" -n 2 bash "$HERE/run.sh" --one
  n=0; for t in $files; do n=$((n + 1)); report "$n" "$t"; done
fi
if [ $rc -eq 0 ]; then echo "ALL TESTS PASSED"; else echo "SOME TESTS FAILED"; fi
if [ -s "$RUN_ROOT/skips" ]; then
  echo "Skipped parts ($(wc -l < "$RUN_ROOT/skips" | tr -d ' ')):"; cat "$RUN_ROOT/skips"
fi
echo "wall time: $(( $(date +%s) - t0 )) s, $n files, -j $jobs"
exit $rc
