#!/usr/bin/env bash
# The public docs (READMEs, SECURITY.md, ARCHITECTURE.md, CONTRIBUTING.md, docs/*.md) name repo
# paths: every one must exist, so a file that was moved or removed cannot stay in the text.
# A root doc names paths from the repo root (plugins/, docs/, tests/, evals/). A plugin's README may
# also name paths inside its plugin (skills/, scripts/, hooks/, ...) or inside one of its skills,
# which are looked up there first.
# Paths with a placeholder (<name>, *, $) are skipped.
source "$(dirname "$0")/lib.sh"

ROOT_DIRS='plugins|docs|tests|evals'
PLUGIN_DIRS='plugins|docs|tests|evals|skills|scripts|hooks|agents|reference|codex|assets|templates'

# paths_in <file> <dirs> — path-like tokens that start at one of <dirs> (an ERE alternation)
paths_in() {
  LC_ALL=C grep -oE "(^|[^A-Za-z0-9_./~<-])($2)/[A-Za-z0-9_./*<>\$-]*[A-Za-z0-9_*>/]" "$1" \
    | LC_ALL=C sed -E 's/^[^a-z]//' | LC_ALL=C grep -v '[*<>$]' | LC_ALL=C sort -u
}

docs=""
for d in README.md README.*.md SECURITY.md ARCHITECTURE.md CONTRIBUTING.md plugins/*/README.md plugins/*/README.*.md docs/*.md; do
  [ -f "$ROOT/$d" ] && docs="$docs $d"
done
for doc in README.md SECURITY.md ARCHITECTURE.md CONTRIBUTING.md plugins/corecrew/README.md plugins/coremodel/README.md plugins/coreopinion/README.md; do
  assert_file "$ROOT/$doc"
done
for doc in $docs; do
  case "$doc" in
    plugins/*/*) base="$ROOT/${doc%/*}"; dirs="$PLUGIN_DIRS" ;;
    *) base=""; dirs="$ROOT_DIRS" ;;
  esac
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    q="${p%/}"
    if [ -n "$base" ] && [ -e "$base/$q" ]; then pass
    elif [ -n "$base" ] && ls -d "$base"/skills/*/"$q" >/dev/null 2>&1; then pass   # relative to one of its skills
    elif [ -e "$ROOT/$q" ]; then pass
    else fail "$doc names $p, which does not exist"
    fi
  done < <(paths_in "$ROOT/$doc" "$dirs")
done

# the self-check: a made-up path is caught, a real one is not, placeholders are skipped
new_sandbox
printf 'See docs/migration-0.3.md and evals/gone/evals.json, plugins/<name>/x and docs/*.md.\n' > "$SANDBOX/x.md"
got="$(paths_in "$SANDBOX/x.md" "$ROOT_DIRS" | tr '\n' ' ')"
assert_eq "$got" "docs/migration-0.3.md evals/gone/evals.json " "path extraction"
[ -e "$ROOT/evals/gone/evals.json" ] && fail "self-check path exists" || pass
printf 'Run `scripts/ask-gpt.sh` (see skills/x/SKILL.md).\n' > "$SANDBOX/y.md"
assert_eq "$(paths_in "$SANDBOX/y.md" "$PLUGIN_DIRS" | tr '\n' ' ')" "scripts/ask-gpt.sh skills/x/SKILL.md " "plugin-relative paths"
assert_eq "$(paths_in "$SANDBOX/y.md" "$ROOT_DIRS")" "" "root docs ignore plugin-relative paths"
finish
