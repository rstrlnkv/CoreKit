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

# tree_paths <file> — the full paths of the tree under "## Where things live" (ARCHITECTURE.md).
# An indented entry is relative to the closest less-indented entry above it that ends in /.
# The entry ends at two spaces (the description follows); "a/, b/" names two entries; a line
# indented 20 or more is a description carried over and is skipped.
tree_paths() {
  LC_ALL=C awk '
    /^## / { sec = ($0 == "## Where things live"); next }
    sec && /^```/ { if (inb) exit; inb = 1; next }
    !inb { next }
    {
      match($0, /^ */); ind = RLENGTH
      if (ind >= 20 || ind == length($0)) next
      line = substr($0, ind + 1)
      cut = index(line, "  "); if (cut) line = substr(line, 1, cut - 1)
      while (n > 0 && ind_s[n] >= ind) n--
      parent = n ? path_s[n] : ""
      k = split(line, ents, /, /)
      for (j = 1; j <= k; j++) print parent ents[j]
      if (k == 1 && line ~ /\/$/) { n++; ind_s[n] = ind; path_s[n] = parent line }
    }' "$1"
}

# check_tree <file> — every path of its tree must exist in the repo, and the tree must have at least
# TREE_MIN entries: a moved heading or fence would leave nothing to check and pass silently.
TREE_MIN=10
check_tree() {
  local p n=0
  while IFS= read -r p; do
    n=$((n + 1))
    case "$p" in *'<'*|*'$'*) continue ;; esac
    # shellcheck disable=SC2086 # $p may hold a * glob, matched in the repo
    if ls -d "$ROOT"/$p >/dev/null 2>&1; then pass
    else fail "${1##*/} tree names $p, which does not exist"
    fi
  done < <(tree_paths "$1")
  [ "$n" -ge "$TREE_MIN" ] && pass \
    || fail "${1##*/}: $n tree entries under \"## Where things live\", want at least $TREE_MIN (did the heading or the fence move?)"
}
check_tree "$ROOT/ARCHITECTURE.md"

# tree_text <file> — the lines of the tree under "## Where things live"
tree_text() {
  LC_ALL=C awk '/^## / { sec = ($0 == "## Where things live"); next }
    sec && /^```/ { if (inb) exit; inb = 1; next }
    inb' "$1"
}
# named_in_tree <name> <file> — the tree names <name> as a word, or through a word with a * (wiki-*.sh)
named_in_tree() {
  local w
  while IFS= read -r w; do
    w="${w%/}"
    case "$w" in
      "$1") return 0 ;;
      '*') ;;
      *'*'*)
        # shellcheck disable=SC2254 # $w is a pattern here on purpose
        case "$1" in $w) return 0 ;; esac ;;
    esac
  done < <(tree_text "$2" | LC_ALL=C tr -s ' ,():;`' '\n')
  return 1
}
# every file and folder in corecrew's scripts/ is named in the tree, so a new or split script is described
for f in "$PLUGIN"/scripts/*; do
  n="${f##*/}"
  named_in_tree "$n" "$ROOT/ARCHITECTURE.md" && pass || fail "ARCHITECTURE.md tree does not name scripts/$n"
done

# the self-check: a made-up path is caught, a real one is not, placeholders are skipped
new_sandbox
# a moved heading leaves no tree to read: that must fail, not pass with nothing checked
sed 's/^## Where things live$/## Where things are/' "$ROOT/ARCHITECTURE.md" > "$SANDBOX/ARCHITECTURE.md"
( FAILS=0; check_tree "$SANDBOX/ARCHITECTURE.md" >/dev/null; [ "$FAILS" -gt 0 ] ) \
  && pass || fail "a doc whose tree heading moved passes the tree check"
printf '%s\n' '# A' '## Where things live' '```' 'top.json   the top' 'plugins/x/      a plugin' \
  '  skills/       skills' '    */agents/a.yaml   per skill' '    task/ref.md   one file' \
  '                    a description carried over' '  tests/, types/   two' 'docs/   docs' '```' \
  '## Hosts' '```' 'manifest   not a path' '```' > "$SANDBOX/tree.md"
assert_eq "$(tree_paths "$SANDBOX/tree.md" | tr '\n' ' ')" \
  "top.json plugins/x/ plugins/x/skills/ plugins/x/skills/*/agents/a.yaml plugins/x/skills/task/ref.md plugins/x/tests/ plugins/x/types/ docs/ " \
  "tree path extraction"
printf 'See docs/migration-0.3.md and evals/gone/evals.json, plugins/<name>/x and docs/*.md.\n' > "$SANDBOX/x.md"
got="$(paths_in "$SANDBOX/x.md" "$ROOT_DIRS" | tr '\n' ' ')"
assert_eq "$got" "docs/migration-0.3.md evals/gone/evals.json " "path extraction"
[ -e "$ROOT/evals/gone/evals.json" ] && fail "self-check path exists" || pass
printf 'Run `scripts/ask-gpt.sh` (see skills/x/SKILL.md).\n' > "$SANDBOX/y.md"
assert_eq "$(paths_in "$SANDBOX/y.md" "$PLUGIN_DIRS" | tr '\n' ' ')" "scripts/ask-gpt.sh skills/x/SKILL.md " "plugin-relative paths"
assert_eq "$(paths_in "$SANDBOX/y.md" "$ROOT_DIRS")" "" "root docs ignore plugin-relative paths"
finish
