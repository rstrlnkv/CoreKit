#!/usr/bin/env bash
# Runs a plugin's trigger evals: does a skill start when it should, and stay quiet when it should not.
# The cases live in evals/<plugin>/ at the repo root, outside the plugin, so an install does not carry them.
# `claude plugin eval` reads the cases from a folder inside the plugin, so this script assembles a copy in a temp
# folder (the plugin, with evals/<plugin>/ as its evals/ folder), runs the eval on the copy and removes the copy.
# It makes real model calls and is not part of tests/run.sh.
# Usage: bash scripts/eval.sh <plugin> [more `claude plugin eval` options, for example --case '<glob>']
# Output: what `claude plugin eval <copy> --ablation none --no-publish` prints. The results it writes are copied
#         to evals/<plugin>/results/ (ignored by git).
# Exit:   the exit code of `claude plugin eval`; 1 claude is not on PATH or the copy could not be made;
#         2 refused, nothing run (no plugin name, no plugins/<plugin>/, or no evals/<plugin>/).
set -u
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

refuse() { echo "eval.sh: $1" >&2; exit 2; }
die() { echo "eval.sh: $1" >&2; exit 1; }

[ $# -ge 1 ] && [ -n "$1" ] || refuse "usage: bash scripts/eval.sh <plugin>"
PL="$1"; shift
case "$PL" in */*|.*) refuse "not a plugin name: $PL" ;; esac
[ -f "$ROOT_DIR/plugins/$PL/.claude-plugin/plugin.json" ] || refuse "no plugin plugins/$PL"
[ -d "$ROOT_DIR/evals/$PL" ] || refuse "no trigger evals for $PL: evals/$PL does not exist"
command -v claude >/dev/null 2>&1 || die "claude is not on PATH"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/corekit-eval.XXXXXX")" || die "cannot make a temp folder"
trap 'rm -rf "$STAGE"' EXIT
trap 'exit 130' INT TERM
cp -R "$ROOT_DIR/plugins/$PL" "$STAGE/$PL" && cp -R "$ROOT_DIR/evals/$PL" "$STAGE/$PL/evals" \
  || die "cannot assemble the copy in $STAGE"
rm -rf "$STAGE/$PL/evals/results"   # earlier results stay in the repo folder; the copy starts without them

claude plugin eval "$STAGE/$PL" --ablation none --no-publish "$@"
rc=$?
if [ -d "$STAGE/$PL/evals/results" ]; then
  mkdir -p "$ROOT_DIR/evals/$PL/results" && cp -R "$STAGE/$PL/evals/results/." "$ROOT_DIR/evals/$PL/results/" \
    || echo "eval.sh: could not copy the results to evals/$PL/results" >&2
fi
exit "$rc"
