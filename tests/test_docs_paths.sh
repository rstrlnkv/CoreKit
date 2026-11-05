#!/usr/bin/env bash
# The READMEs and CHANGELOG-free docs name repo paths (plugins/..., docs/..., tests/..., evals/...):
# every one must exist, so a file that was moved or removed cannot stay in the text. Paths with a
# placeholder (<name>, *, $) and a trailing "..." are skipped.
source "$(dirname "$0")/lib.sh"

# paths_in <file> — path-like tokens that start at a repo folder
paths_in() {
  LC_ALL=C grep -oE '(^|[^A-Za-z0-9_./~<-])(plugins|docs|tests|evals)/[A-Za-z0-9_./-]*[A-Za-z0-9_]/?' "$1" \
    | LC_ALL=C sed -E 's/^[^pdte]//' | LC_ALL=C sort -u
}

for doc in README.md plugins/coremodel/README.md plugins/coreopinion/README.md; do
  assert_file "$ROOT/$doc"
  n=0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    n=$((n + 1))
    q="${p%/}"
    [ -e "$ROOT/$q" ] && pass || fail "$doc names $p, which does not exist"
  done < <(paths_in "$ROOT/$doc")
  [ "$n" -ge 0 ] && pass
done

# the self-check: a made-up path is caught, a real one is not
T="$(mktemp -d)"; printf 'See docs/migration-0.3.md and evals/gone/evals.json.\n' > "$T/x.md"
got="$(paths_in "$T/x.md" | tr '\n' ' ')"
assert_eq "$got" "docs/migration-0.3.md evals/gone/evals.json " "path extraction"
[ -e "$ROOT/evals/gone/evals.json" ] && fail "self-check path exists" || pass
rm -rf "$T"
finish
