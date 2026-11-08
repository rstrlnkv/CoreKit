#!/usr/bin/env bash
# Manual check of the classifier on the real model: the labelled prompts of quality-cases.txt, each
# asked RUNS times (the model does not always answer the same), compared with the right answers.
# Needs the claude CLI and the network, so tests/run.sh does not call it. About 1,500 input tokens a call.
# Usage: bash plugins/coremodel/tests/quality.sh haiku|sonnet [tune|hold|all]
#   RUNS=3 (asks per prompt), JOBS=8 (calls at once), CASES=<file> (default quality-cases.txt)
case "$1" in
  haiku) model=claude-haiku-5-5 ;;
  sonnet) model=claude-sonnet-5-5 ;;
  *) echo "usage: $0 haiku|sonnet [tune|hold|all]" >&2; exit 2 ;;
esac
only="${2:-all}"
case "$only" in tune|hold|all) ;; *) echo "usage: $0 haiku|sonnet [tune|hold|all]" >&2; exit 2 ;; esac
runs="${RUNS:-3}"
jobs="${JOBS:-8}"
here="$(cd "$(dirname "$0")" && pwd)"
src="$here/../hooks/classifier.ts"
cases_file="${CASES:-$here/quality-cases.txt}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/ep-quality.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# The template between the marker lines, without the opening `export const TEMPLATE = \`` and the closing backtick.
sed -n '/^\/\/ TEMPLATE-START$/,/^\/\/ TEMPLATE-END$/p' "$src" | sed '1d;$d' |
  sed '1s/^export const TEMPLATE = `//;$s/`$//' > "$tmp/template"

# Every case line has five fields; a broken line stops the run before any call is paid for.
grep -v '^#' "$cases_file" | grep -v '^[[:space:]]*$' > "$tmp/cases"
bad="$(awk -F'|' 'NF != 5 || ($1 != "tune" && $1 != "hold") { print NR ": " $0 }' "$tmp/cases")"
if [ -n "$bad" ]; then
  echo "broken case lines (need set|levels|models|prompt|reply):" >&2
  printf '%s\n' "$bad" >&2
  exit 2
fi
if [ "$only" != all ]; then
  awk -F'|' -v s="$only" '$1 == s' "$tmp/cases" > "$tmp/cases.only"
  mv "$tmp/cases.only" "$tmp/cases"
fi

# The prompt for one case, as buildPrompt makes it: \n and \t in the case become real ones, the reply
# is cut to 600 characters. The person's text is put in last and never searched again.
build() {
  P="$1" R="$2" awk '
    function unesc(s) { gsub(/\\n/, "\n", s); gsub(/\\t/, "\t", s); return s }
    function rep(line, ph, v,   out, i) {
      out = ""
      while ((i = index(line, ph)) > 0) { out = out substr(line, 1, i - 1) v; line = substr(line, i + length(ph)) }
      return out line
    }
    BEGIN {
      p = unesc(ENVIRON["P"]); r = ENVIRON["R"]
      if (r == "-") r = "(none, this is the first prompt)"; else r = substr(unesc(r), 1, 600)
    }
    { print rep(rep(rep($0, "{{NOW}}", "high"), "{{REPLY}}", r), "{{PROMPT}}", p) }' "$tmp/template"
}

ask() {
  # A bare call: no tools, no settings, no plugins or hooks, no project files, so only the template counts.
  (cd "$tmp" && exec claude -p --model "$model" --effort low --tools "" --setting-sources "" --strict-mcp-config \
    --disable-slash-commands --no-session-persistence --system-prompt "Follow the user's instructions exactly." \
    < "$1" > "$2" 2>&1) &
  pid=$!
  # A call that hangs is cut after 60 s and counts as no answer; the plugin waits far less.
  (sleep 60; kill "$pid" 2>/dev/null) &
  dog=$!
  wait "$pid"
  kill "$dog" 2>/dev/null
}

n=0
started=0
while IFS='|' read -r set levels models prompt reply; do
  n=$((n + 1))
  build "$prompt" "$reply" > "$tmp/prompt.$n"
  r=1
  while [ "$r" -le "$runs" ]; do
    ask "$tmp/prompt.$n" "$tmp/answer.$n.$r" &
    started=$((started + 1))
    [ $((started % jobs)) -eq 0 ] && wait
    r=$((r + 1))
  done
done < "$tmp/cases"
wait

# Rungs: keep sits apart (any confusion with it is a big miss); the others count by distance.
rung() {
  case "$1" in
    low|haiku) echo 1 ;; medium|sonnet) echo 2 ;; high|opus) echo 3 ;; xhigh|fable) echo 4 ;; max) echo 5 ;;
    keep) echo 100 ;; *) echo 1000 ;;
  esac
}
# ok, near (one rung off) or big (two or more, keep confused, no answer).
grade() {
  got="$1"; want="$2"
  [ "$want" = '*' ] && { echo ok; return; }
  case "/$want/" in */"$got"/*) [ -n "$got" ] && { echo ok; return; } ;; esac
  g="$(rung "$got")"; best=1000
  for w in $(printf '%s' "$want" | tr '/' ' '); do
    d=$(( g - $(rung "$w") )); [ "$d" -lt 0 ] && d=$(( -d ))
    [ "$d" -lt "$best" ] && best="$d"
  done
  [ "$best" -le 1 ] && echo near || echo big
}
field() {
  tr '\n' ' ' < "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | tr 'A-Z' 'a-z' | tr -cd 'a-z' |
    sed 's/^extrahigh$/xhigh/'
}

i=0
for s in tune hold; do eval "L_$s=0 M_$s=0 B_$s=0 BL_$s=0 BM_$s=0 T_$s=0"; done
while IFS='|' read -r set levels models prompt reply; do
  i=$((i + 1))
  r=1; seen=''; missed=0; raw=''
  while [ "$r" -le "$runs" ]; do
    got="$(field "$tmp/answer.$i.$r" level)"; gotm="$(field "$tmp/answer.$i.$r" model)"
    gl="$(grade "$got" "$levels")"; gm="$(grade "$gotm" "$models")"
    eval "T_$set=\$((T_$set + 1))"
    [ "$gl" = ok ] && eval "L_$set=\$((L_$set + 1))"
    [ "$gm" = ok ] && eval "M_$set=\$((M_$set + 1))"
    [ "$gl" = ok ] && [ "$gm" = ok ] && eval "B_$set=\$((B_$set + 1))"
    [ "$gl" = big ] && eval "BL_$set=\$((BL_$set + 1))"
    [ "$gm" = big ] && eval "BM_$set=\$((BM_$set + 1))"
    mark=''
    [ "$gl" != ok ] && mark="$mark level-$gl"
    [ "$gm" != ok ] && mark="$mark model-$gm"
    [ -n "$mark" ] && missed=1
    seen="$seen ${got:-?}/${gotm:-?}"
    # An unreadable answer shows its start: a refusal, an error or a cut call (empty).
    [ -z "$got" ] && raw="$raw
     no answer: $(tr '\n' ' ' < "$tmp/answer.$i.$r" | sed -E 's/^(.{0,100}).*$/\1/')"
    r=$((r + 1))
  done
  if [ "$missed" = 1 ]; then
    # sed counts characters where cut counts bytes and splits a Cyrillic letter.
    short="$(printf '%s' "$prompt" | sed -E 's/^(.{0,70}).*$/\1/')"
    printf 'MISS [%s] %s\n     want %s %s, got%s%s\n' "$set" "$short" "$levels" "$models" "$seen" "$raw"
  fi
done < "$tmp/cases"

for s in tune hold; do
  t=0 l=0 m=0 b=0 bl=0 bm=0   # set by the eval below; the defaults keep ShellCheck and set -u calm
  eval "t=\$T_$s l=\$L_$s m=\$M_$s b=\$B_$s bl=\$BL_$s bm=\$BM_$s"
  [ "$t" -eq 0 ] && continue
  printf '%s: level %d/%d, model %d/%d, both %d/%d; big misses: level %d, model %d (%s, %s runs)\n' \
    "$s" "$l" "$t" "$m" "$t" "$b" "$t" "$bl" "$bm" "$1" "$runs"
done
