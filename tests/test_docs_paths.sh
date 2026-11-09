#!/usr/bin/env bash
# The public docs (READMEs, SECURITY.md, ARCHITECTURE.md, CONTRIBUTING.md, docs/*.md, .github/) name repo
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
for d in README.md README.*.md SECURITY.md ARCHITECTURE.md CONTRIBUTING.md plugins/*/README.md plugins/*/README.*.md docs/*.md \
  .github/*.md .github/ISSUE_TEMPLATE/*.md; do
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
# coreopinion's agents/openai.yaml keeps its skill out of Codex (coreopinion is Claude Code only): the tree names it
for f in "$ROOT"/plugins/coreopinion/skills/*/agents/openai.yaml; do
  [ -f "$f" ] || continue
  tree_paths "$ROOT/ARCHITECTURE.md" | grep -qxF "${f#"$ROOT"/}" && pass || fail "ARCHITECTURE.md tree does not name ${f#"$ROOT"/}"
done

# anchors_of <file> — the anchors of its headings outside ``` fences, as GitHub makes them: lowercased,
# everything but letters, digits, spaces, - and _ dropped, spaces turned into dashes
anchors_of() {
  LC_ALL=C awk '
    /^```/ { inb = !inb; next }
    inb { next }
    /^#+ / { h = $0; sub(/^#+ /, "", h); h = tolower(h); gsub(/[^a-z0-9 _-]/, "", h); gsub(/ /, "-", h); print h }
  ' "$1"
}
# check_anchors <doc> — every relative ](target) link in <doc>: a link without # names a file or folder that
# exists; a ](path.md#anchor) or ](#anchor) link names a heading of its target. Web and mailto links are not checked.
check_anchors() {
  local l target anchor file
  while IFS= read -r l; do
    l="${l#](}"; l="${l%)}"
    case "$l" in http://*|https://*|mailto:*) continue ;; esac
    target="${l%%#*}"
    case "$target" in
      '') file="$1" ;;
      *) file="$(dirname "$1")/$target" ;;
    esac
    case "$l" in
      *'#'*) anchor="${l#*#}" ;;
      *) [ -e "$file" ] && pass || fail "${1#"$ROOT"/} links $l: no such file"; continue ;;
    esac
    if [ ! -f "$file" ]; then fail "${1#"$ROOT"/} links $l: no such file"
    elif anchors_of "$file" | grep -qxF -- "$anchor"; then pass
    else fail "${1#"$ROOT"/} links $l, but ${target:-it} has no heading for #$anchor"
    fi
  done < <(LC_ALL=C grep -oE '\]\([^)[:space:]]+\)' "$1")
}
for doc in $docs; do check_anchors "$ROOT/$doc"; done
# the README's Claude Code install section points at the deny rules: the host is the boundary, the hooks
# only back it up (SECURITY.md, Recommended host settings)
section() { awk -v h="$2" '$0 == h { s = 1; next } s && /^#{1,3} / { exit } s' "$1"; }
section "$ROOT/README.md" '### Claude Code' | grep -qF 'SECURITY.md#recommended-host-settings' && pass \
  || fail "README's Claude Code install section does not link SECURITY.md#recommended-host-settings"
# SECURITY.md, Known limits: the code guard blocks docs/** while the pre-commit hook (scripts/git-hooks/blocked-patterns)
# does not, so a docs/ file can still be committed by hand; the section says so, and the guard's header no longer
# claims the two sets agree
section "$ROOT/SECURITY.md" '### Known limits of the hooks' | grep -qF 'blocked-patterns' && pass \
  || fail "SECURITY.md Known limits does not name blocked-patterns (the pre-commit hook's list)"
assert_not_contains "$PLUGIN/hooks/guard-code.sh" "so the hook and the commit check agree"
# the network detail lives in the plugin READMEs; SECURITY.md only links them, so no copy can drift
for w in 'gh run' 'gh auth status' 'api.github.com'; do assert_not_contains "$ROOT/SECURITY.md" "$w"; done
# the forbidden bash constructs are listed once, in tests/test_portability.sh: CONTRIBUTING.md and the PR
# template keep the principle and point there instead of copying the list ([P]: test_portability.sh scans this file)
for f in CONTRIBUTING.md .github/pull_request_template.md; do
  assert_contains "$ROOT/$f" 'tests/test_portability.sh'
  LC_ALL=C grep -qE 'mapfile|readarray|grep -[P]|declare -[A]|local -[n]' "$ROOT/$f" \
    && fail "$f copies the forbidden constructs of tests/test_portability.sh" || pass
done
assert_contains "$ROOT/.github/pull_request_template.md" 'CONTRIBUTING.md'
assert_contains "$ROOT/.github/pull_request_template.md" 'commit-subjects'

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
# anchors: a heading inside a fence is none; a link to a missing anchor, or a missing file, fails
printf '%s\n' '# Doc' '## Host settings' '### `new-project` and `task`' '```' '## Not a heading' '```' \
  '[a](#host-settings) [b](#new-project-and-task) [c](other.md#there) [d](https://example.com/x.md#web)' > "$SANDBOX/a.md"
printf '%s\n' '# Other' '## There' > "$SANDBOX/other.md"
assert_eq "$(anchors_of "$SANDBOX/a.md" | tr '\n' ' ')" "doc host-settings new-project-and-task " "anchors of headings"
( FAILS=0; check_anchors "$SANDBOX/a.md" >/dev/null; [ "$FAILS" -eq 0 ] ) && pass || fail "good anchor links fail"
printf '%s\n' '[x](#host-setting) [y](other.md#here) [z](gone.md#there)' > "$SANDBOX/b.md"
( FAILS=0; check_anchors "$SANDBOX/b.md" >/dev/null; [ "$FAILS" -eq 3 ] ) && pass || fail "a missing anchor or file passes the anchor check"
# a link without an anchor names an existing file; web and mailto links are not checked
printf '%s\n' '[g](gone.md) [o](other.md) [d](./) [w](https://example.com/gone.md) [m](mailto:someone)' > "$SANDBOX/c.md"
( FAILS=0; check_anchors "$SANDBOX/c.md" >/dev/null; [ "$FAILS" -eq 1 ] ) && pass || fail "a dead link without an anchor passes the link check"
# Every top-level name in tests/fixtures/ is named in CONTRIBUTING.md's "### Test fixtures" (a code span; a glob such as
# `standard-*.md` counts, a trailing / and a tests/fixtures/ prefix are dropped) and in at least one tests/test_*.sh.
# check_fixtures <doc> <fixtures dir> <tests dir> — one FAIL per name missing from either
check_fixtures() {
  local spans name t found
  spans="$(awk '/^#/ { f = ($0 == "### Test fixtures"); next } f' "$1" | grep -oE '`[^` ]+`' | tr -d '`' \
    | sed -e 's|^tests/fixtures/||' -e 's|/$||')"
  [ -n "$spans" ] || { fail "$(basename "$1") has no ### Test fixtures section with code spans"; return; }
  # every top-level name, dot names too (.[!.]* and ..?* never match . or ..); a glob that matched nothing is skipped
  for name in "$2"/* "$2"/.[!.]* "$2"/..?*; do
    [ -e "$name" ] || [ -L "$name" ] || continue
    name="${name##*/}"
    found=""
    while IFS= read -r t; do
      # shellcheck disable=SC2254  # a span may be a glob on purpose
      case "$name" in $t) found=1; break ;; esac
    done <<< "$spans"
    [ -n "$found" ] && pass || fail "$(basename "$1") does not name the fixture $name under ### Test fixtures"
    grep -qE "(^|[^A-Za-z0-9_.-])$(printf '%s' "$name" | sed 's/\./\\./g')([^A-Za-z0-9_.-]|$)" "$3"/test_*.sh \
      && pass || fail "no tests/test_*.sh names the fixture $name"
  done
}
check_fixtures "$ROOT/CONTRIBUTING.md" "$ROOT/tests/fixtures" "$ROOT/tests"
# self-check: a new fixture that neither the doc nor a test names fails twice; a glob in the doc counts
mkdir -p "$SANDBOX/fx/zz-unnamed" "$SANDBOX/fx/std-a.md" "$SANDBOX/ts"
printf '%s\n' '# C' '### Test fixtures' '- `std-*.md`, `tests/fixtures/wiki-good/`' '## Next' '`zz-unnamed`' > "$SANDBOX/c2.md"
printf '%s\n' 'copy_fixture std-a.md x' > "$SANDBOX/ts/test_a.sh"
( FAILS=0; check_fixtures "$SANDBOX/c2.md" "$SANDBOX/fx" "$SANDBOX/ts" >/dev/null; [ "$FAILS" -eq 2 ] ) \
  && pass || fail "a fixture missing from the doc and the tests does not fail twice"
# a dot-named fixture counts too (.a and ..a, never . or ..): each of the two fails twice more
mkdir -p "$SANDBOX/fx/.zz-hidden" "$SANDBOX/fx/..zz-two"
( FAILS=0; check_fixtures "$SANDBOX/c2.md" "$SANDBOX/fx" "$SANDBOX/ts" >/dev/null; [ "$FAILS" -eq 6 ] ) \
  && pass || fail "a dot-named fixture missing from the doc and the tests is not checked"
finish
