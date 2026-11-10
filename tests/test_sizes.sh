#!/usr/bin/env bash
# One size table for the repo (Decision 37 (a) of the round-3 refactor: today's size plus about 15% per kind, every
# tight limit of today kept per file, named exceptions). It prints every file over its limit.
#
# A row: <pattern> <unit> <limit> [why]. The files are the tracked ones (`git ls-files`). A pattern is a bash `case`
# glob over the repo path, where `*` also matches `/`; a pattern that starts with `sh:` takes only shell files (a .sh
# name, or a first line `#!` that names sh or bash). Units: lines; words (blank-separated); chars (the longest line,
# in characters). For each file and unit the first matching row is the limit, so named exceptions and per-file rows
# come before the kind-wide defaults. A row that matches no file fails: a renamed file must not lose its limit.
#
# Two layout contracts stay where they are, beside the checks they belong to:
# - plugins/corecrew/scripts/lib.sh at most 250 lines (tests/test_lib_layout.sh: its helpers belong in its parts);
# - the Core's standards/README.md and knowledge/README.md at most 15 lines (tests/test_setup_core.sh: a limit on
#   scaffold output, not on a tracked file).
source "$(dirname "$0")/lib.sh"
new_sandbox

IFS= read -r -d '' TABLE <<'EOF'
# Named exceptions: each says what keeps it.
plugins/corecrew/scripts/adopt.sh                         lines  740   one file: E1 of the after-refactor plan (643 today)
plugins/corecrew/scripts/bash-lex.awk                     lines  350   the one tokenizer both guards share: R3-41 to R3-43 (304 today)
plugins/corecrew/skills/task/references/adopt.md          words  1420  adopt's leftover refusal and recovery: R3-45 (1235 today)
plugins/corecrew/agents/engineer.md                       chars  580   one long line kept, not split: R3-71 (506 today)
plugins/corecrew/agents/verifier.md                       chars  590   one long line kept, not split: R3-71 (573 today)

# Tight limits of today, per file.
plugins/corecrew/skills/ship/SKILL.md                     lines  150
plugins/corecrew/skills/task/references/release.md        lines  80
plugins/corecrew/reference/knowledge.md                   lines  80
plugins/corecrew/reference/wiki.md                        lines  80
plugins/corecrew/agents/*.md                              lines  60

# Kind-wide defaults.
plugins/*/skills/*/SKILL.md                               lines  499
plugins/*/skills/*/SKILL.md                               words  2500
plugins/*/skills/*/references/*.md                        words  1200
plugins/*/reference/*.md                                  words  1200
plugins/*/agents/*.md                                     words  900
plugins/*/skills/*/SKILL.md                               chars  400
plugins/*/skills/*/references/*.md                        chars  400
plugins/*/reference/*.md                                  chars  400
plugins/*/agents/*.md                                     chars  400
sh:plugins/*                                              lines  400
sh:scripts/*                                              lines  400
plugins/*.awk                                             lines  300
plugins/coremodel/hooks/*.ts                              lines  500
plugins/coremodel/hooks/*.tsx                             lines  500
tests/*.sh                                                lines  1000
plugins/coremodel/tests/*                                 lines  1000
EOF

# The rows, in order: PAT, UNIT, LIM, and USED (1 once a file matched the row).
PAT=(); UNIT=(); LIM=(); USED=()
while read -r p u l _; do
  case "$p" in ''|'#'*) continue ;; esac
  case "$u" in lines|words|chars) ;; *) fail "row $p: unknown unit $u"; continue ;; esac
  case "$l" in ''|*[!0-9]*) fail "row $p $u: the limit $l is not a number"; continue ;; esac
  PAT+=("$p"); UNIT+=("$u"); LIM+=("$l"); USED+=(0)
done <<< "$TABLE"
[ "${#PAT[@]}" -gt 0 ] && pass || fail "the size table has no rows"

FILES="$(git -C "$ROOT" -c core.quotepath=off ls-files 2>/dev/null)"
[ -n "$FILES" ] && pass || fail "git ls-files lists no file: not a git checkout?"

# is_shell <path> — a .sh name, or a first line #! that names sh or bash
is_shell() {
  local first=""
  case "$1" in *.sh) return 0 ;; esac
  IFS= read -r first < "$ROOT/$1" 2>/dev/null
  case "$first" in '#!'*sh|'#!'*sh' '*|'#!'*bash*) return 0 ;; esac
  return 1
}

# NEED: one line per checked file and unit, "<path> TAB <unit> TAB <limit> TAB <row pattern>"; ARGS: the files to measure.
NEED=""; ARGS=(); n=${#PAT[@]}
while IFS= read -r f; do
  [ -f "$ROOT/$f" ] || continue
  units=" "; sh=""
  i=0
  while [ "$i" -lt "$n" ]; do
    p="${PAT[$i]}"; u="${UNIT[$i]}"
    case "$units" in *" $u "*) i=$((i + 1)); continue ;; esac
    case "$p" in sh:*) p="${p#sh:}" ;; esac
    # shellcheck disable=SC2254  # the pattern is a glob on purpose
    case "$f" in
      $p)
        if [ "$p" != "${PAT[$i]}" ]; then
          [ -n "$sh" ] || { if is_shell "$f"; then sh=yes; else sh=no; fi; }
          [ "$sh" = yes ] || { i=$((i + 1)); continue; }
        fi
        units="$units$u "; USED[i]=1
        NEED="$NEED$f	$u	${LIM[$i]}	${PAT[$i]}
"
        ;;
    esac
    i=$((i + 1))
  done
  [ "$units" = " " ] || ARGS+=("$ROOT/$f")
done <<< "$FILES"

i=0
while [ "$i" -lt "$n" ]; do
  [ "${USED[$i]}" = 1 ] && pass || fail "row ${PAT[$i]} ${UNIT[$i]} ${LIM[$i]} matches no tracked file"
  i=$((i + 1))
done

# Measure every file once: lines, blank-separated words, and the longest line in characters (UTF-8 continuation
# bytes are not counted, so the result is the same in every locale and awk). An empty file prints nothing: 0.
STATS=""
if [ "${#ARGS[@]}" -gt 0 ]; then
  STATS="$(LC_ALL=C awk -v root="$ROOT/" '
    function out() { print substr(f, length(root) + 1) "\t" l "\t" w "\t" c }
    FNR == 1 { if (f != "") out(); f = FILENAME; l = 0; w = 0; c = 0 }
    { l++; w += NF; s = $0; gsub(/[\200-\277]/, "", s); if (length(s) > c) c = length(s) }
    END { if (f != "") out() }' "${ARGS[@]}")"
fi

# Join: every NEED line over its limit is one FAIL line; the rest pass.
over="$(printf '%s\n@@\n%s' "$STATS" "$NEED" | awk -F '\t' '
  $0 == "@@" { join = 1; next }
  !join { if ($1 != "") { s["lines", $1] = $2; s["words", $1] = $3; s["chars", $1] = $4 }; next }
  $1 == "" { next }
  { v = s[$2, $1] + 0; checked++
    if (v > $3 + 0) print $1 ": " v " " $2 ", over the limit " $3 " (row " $4 ")" }
  END { print "checked " checked + 0 }')"
while IFS= read -r line; do
  case "$line" in
    'checked '*) [ "${line#checked }" -gt 0 ] && pass || fail "no file was measured" ;;
    *) fail "$line" ;;
  esac
done <<< "$over"
finish
