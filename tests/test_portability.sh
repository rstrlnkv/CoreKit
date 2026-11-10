#!/usr/bin/env bash
# Guards macOS compatibility: shell scripts must run on bash 3.2 with BSD utilities.
source "$(dirname "$0")/lib.sh"
new_sandbox

# label|extended regex (BSD grep -E), one per line; a heredoc, so a pattern may hold both quote characters. A label
# may take several lines: BSD grep is many times slower on one long alternation behind a character class.
IFS= read -r -d '' PATTERNS <<'EOF'
sed -i|sed([[:space:]]+-[a-zA-Z]+)*[[:space:]]+-[a-zA-Z]*i
grep -P|grep([[:space:]]+-[a-zA-Z]+)*[[:space:]]+-[a-zA-Z]*P
mapfile/readarray|(^|[^a-zA-Z_])(mapfile|readarray)([[:space:]]|$)
${x,,} case change|\$\{[A-Za-z_][A-Za-z0-9_]*(,|\^)
declare -A / local -n|(declare|local|typeset)[[:space:]]+-[a-zA-Z]*[An]
pipe-stderr or append-both redirect|\|&|&>>
date -d|date([[:space:]]+-[a-zA-Z]+)*[[:space:]]+-d
stat -c|stat[[:space:]]+-c
readlink -f|readlink[[:space:]]+-f
find -printf|find[[:space:]].*-printf
xargs -r|xargs([[:space:]]+-[a-zA-Z]+)*[[:space:]]+-[a-zA-Z]*r
case fall-through|;;&|(^|[^;]);&([[:space:]]|$)
declare -g|(declare|local|typeset)([[:space:]]+-[a-zA-Z]+)*[[:space:]]+-[a-zA-Z]*g
[[ -v / [ -v / test -v|(\[|(^|[^A-Za-z0-9_-])test)[[:space:]]+(![[:space:]]+)?-v[[:space:]]
${x@Q} transform|\$\{([A-Za-z_][A-Za-z0-9_]*|[0-9]+|[@*])(\[[^]]*\])?@[A-Za-z]\}
wait -n|(^|[^A-Za-z0-9_])wait[[:space:]]+-[a-zA-Z]*[nfp]
printf %(..)T|printf[[:space:]].*%\([^)]*\)T
{a..b..step}|(^|[^$])\{[-+]?[0-9A-Za-z]+\.\.[-+]?[0-9A-Za-z]+\.\.[-+]?[0-9]+\}
read -t fraction|read([[:space:]]+-[a-zA-Z]+)*[[:space:]]+-[a-zA-Z]*t[[:space:]]*[0-9]*\.[0-9]
bash 4/5 variable|\$\{?(BASHPID|EPOCHSECONDS|EPOCHREALTIME|SRANDOM|BASH_ARGV0)([^A-Za-z0-9_]|$)
bash 4/5 shopt option|shopt[[:space:]]+-[a-z]+[[:space:]].*(globstar|lastpipe|autocd|checkjobs|dirspell|direxpand|globasciiranges|inherit_errexit|localvar_inherit|localvar_unset|assoc_expand_once|patsub_replacement|varredir_close)
sed block without ; before }|sed([[:space:]]+-[a-zA-Z]+)*[[:space:]]+['"]([^'"]*(;|[^s]/|[0-9]))?[[:space:]]*\{[^{}'"]*[^;{}'"[:space:]][[:space:]]*\}
GNU sed T command|sed([[:space:]]+-[a-zA-Z]+)*[[:space:]]+['"]([^'"]*[;{])?[[:space:]]*T([[:space:]]+[A-Za-z_]+)?[[:space:]]*([;}'"]|$)
gawk-only awk|(gensub|asorti?|strftime|systime|mktime|patsplit|xor|lshift|rshift|compl)\(
gawk-only awk|[^A-Za-z0-9_](and|or)\(
gawk-only awk|PROCINFO|IGNORECASE|BEGINFILE|ENDFILE|FPAT|@include|@load
gawk-only awk|(^|[^A-Za-z0-9_])match\([[:space:]]*(/[^/]*/|"[^"]*"|[^][,()/"]*((\([^()]*\)|\[[^]]*\])[^][,()/"]*)*)[[:space:]]*,[[:space:]]*(/[^/]*/|"[^"]*"|[^][,()/"]*((\([^()]*\)|\[[^]]*\])[^][,()/"]*)*)[[:space:]]*,
gawk-only awk|(^|[^A-Za-z0-9_])split\([[:space:]]*(/[^/]*/|"[^"]*"|[^][,()/"]*((\([^()]*\)|\[[^]]*\])[^][,()/"]*)*)[[:space:]]*,[[:space:]]*(/[^/]*/|"[^"]*"|[^][,()/"]*((\([^()]*\)|\[[^]]*\])[^][,()/"]*)*)[[:space:]]*,[[:space:]]*(/[^/]*/|"[^"]*"|[^][,()/"]*((\([^()]*\)|\[[^]]*\])[^][,()/"]*)*)[[:space:]]*,
EOF
PATTERNS="${PATTERNS%$'\n'}"
# A construct that is forbidden only as a command, label|regex as above. scan() tries it at the line start, after
# | ; & ( ` { or the ) of a case arm, after a shell keyword or command, exec or time, and after a VAR=value, env or
# xargs prefix (AT, one pattern each, for the reason above), and only in the files where the regex alone matches.
# Not seen: a command named by its path (/usr/bin/jq) or behind another wrapper (nice, nohup, builtin).
IFS= read -r -d '' CMDS <<'EOF'
jq as a command|jq([[:space:]]|$)
GNU long option|(sed|date|stat|readlink|cp|mv|ln|rm|head|tail|cut|wc|mktemp|touch|xargs|tr|uniq|du)([[:space:]]+-[^-[:space:]][^[:space:]]*)*[[:space:]]+--[a-z]
head -n -N|head([[:space:]]+[^|;&[:space:]]+)*[[:space:]]+-[nc][[:space:]]*-[0-9]
tac|tac([[:space:]]|$)
EOF
CMDS="${CMDS%$'\n'}"
AT='^
\|
;
&
\(
`
\{
\)
(do|then|else|if|while|until|!|command|exec|time)[[:space:]]
(=[^[:space:]]*|env|xargs([[:space:]]+-[^[:space:]]+)*)[[:space:]]'

# scan <root> <path...> — prints "<path>:<line>: <label>" for each forbidden construct in the files (paths relative to
# <root>, no ":" in them), once per line and label. An *.awk file is awk, not shell: only the gawk-only patterns apply
# to it (they apply to the inline awk of a shell file too). --no-run-if-empty is the one GNU long option macOS takes
# (xargs), so it is dropped first, in a copy under the sandbox; the line numbers stay. One grep per pattern over all
# the files keeps the scan fast.
scan() {
  local base="$1" m="$SANDBOX/scan" f sh=() all=() hit=() label re at
  shift; rm -rf "$m"
  for f in "$@"; do
    mkdir -p "$m/$(dirname "$f")"; sed 's/--no-run-if-empty//g' "$base/$f" > "$m/$f"
    all[${#all[@]}]="$f"; case "$f" in *.awk) ;; *) sh[${#sh[@]}]="$f" ;; esac
  done
  (cd "$m" || exit 1
  # where <label>: prints the hits of grep -nHE as "<path>:<line>: <label>"
  where() { sed "s|^\([^:]*\):\([0-9]*\):.*|\1:\2: $1|"; }
  printf '%s\n' "$PATTERNS" | while IFS='|' read -r label re; do
    if [ "$label" = "gawk-only awk" ]; then set -- "${all[@]}"; else set -- "${sh[@]}"; fi
    [ "$#" -gt 0 ] || continue
    grep -nHE -- "$re" "$@" | where "$label"
  done
  [ "${#sh[@]}" -gt 0 ] || exit 0
  printf '%s\n' "$CMDS" | while IFS='|' read -r label re; do
    hit=(); while IFS= read -r f; do hit[${#hit[@]}]="$f"; done < <(grep -lE -- "$re" "${sh[@]}")
    [ "${#hit[@]}" -gt 0 ] || continue
    printf '%s\n' "$AT" | while IFS= read -r at; do grep -nHE -- "${at}[[:space:]]*$re" "${hit[@]}" | where "$label"; done
  done) | LC_ALL=C sort -u
}

# Self-check: every pattern catches its construct (one hit per bad line, at least one line per label, one more in an
# awk file), and portable lines, the shapes this repo uses among them, pass.
bad="$SANDBOX/bad.sh"
cat > "$bad" <<'EOF'
sed -i '' 's/a/b/' f
grep -oP 'x' f
mapfile -t lines < f
echo "${name,,}"
declare -A map
cmd |& tee log
cmd &>> log
date -d yesterday
stat -c %s f
readlink -f x
find . -printf '%p'
xargs -r rm
cat f | jq .x
x=$(jq -r .a f)
readlink --canonicalize x
  a) echo a ;;&
declare -g x=1
[[ -v name ]] && echo set
echo "${name@Q}"
wait -n
printf '%(%F)T\n' -1
for i in {1..9..2}; do :; done
read -r -t 0.5 line
echo "$BASHPID"
shopt -s globstar
head -n -1 f
tac f
sed -n '/a/{p;q}' f
sed -n '/a/{p}' f
awk '{ print gensub(/a/, "b", "g") }' f
sed 's/a/b/;T' f
sed -n '/x/{s/a/b/}' f
sed -n '/x/{p }' f
awk '{ if (match($0, /a(b)/, m)) print m[1] }' f
awk '{ n = split($0, a, /,/, seps) }' f
LC_ALL=C cut --complement -f1 f
env sed --posix 's/a/b/' f
LC_ALL=C head -n -1 f
xargs tac < list
echo "${@@Q}"
echo "${1@Q}"
[[ ! -v name ]] && echo unset
test -v name
declare -r -g x=1
{ jq -r .a f; }
command jq -r .a f
time jq -r .a f
exec jq -r .a f
case x in x) jq -r .a f ;; esac
f() { jq -r .a "$1"; }
{ tac f; }
EOF
printf '{ t = strftime("%%F") }\n' > "$SANDBOX/bad.awk"
assert_eq "$(scan "$SANDBOX" bad.sh bad.awk | wc -l | tr -d ' ')" "52" "self-check hits"
good="$SANDBOX/good.sh"
cat > "$good" <<'EOF'
sed -n 's/a/b/p' f > f.tmp && mv f.tmp f
grep -qiE 'x' f
echo "${name:-a,b}" | tr '[:upper:]' '[:lower:]'
cmd > log 2>&1
local dir="$1"
gh api repos/x --jq .private
# hook JSON without jq (no jq)
readlink x
git rm --cached f; rm -rf -- "$d"; codex --disable remote_plugin
xargs --no-run-if-empty rm < list
  a) echo a ;;
declare -r x=1
[ -n "${name+x}" ] && echo set
printf '%q\n' "$name"
wait $!
date '+%F'
for i in 1 3 5 7 9; do :; done
read -r -t 1 line
echo "$$ $RANDOM"
shopt -s nullglob extglob
head -n 1 f
tail -r f
sed -n '/a/{p;q;}' f
sed -n "s/^v=\(.*\)\{0,1\}$/\1/p; s|x|${y}|" f
awk '{ print tolower($1) } # T' f
sed 's/a/T/' f
sed -E 's/^(.{0,70}).*$/\1/'; sed -e "s|{{NAME}}|$x|g"
case "$rel" in ../../*) rel="${rel#../../}" ;; esac
find . | xargs -P "$jobs" -n 2 bash run.sh --one; wc -l f' 'git log --author=x
sed 's/{name}/x/' f; sed -n '/x/{s/a/b/;}' f; sed -n '/x/{ p; }' f
awk '{ if (match($0, /a(b)/)) n = split($0, a, /,/) } /x/ && match($1, /y/) { f(a, b) }' f
LC_ALL=C sort -u f; env LC_ALL=C grep --color=never x f; xargs -0 rm -f < list
echo "$@" "${1:-x}"; test -n "$x"; [[ ! -n $x ]]; declare -r x=1
command -v jq > /dev/null; echo "(jq) {tac} ${x} tac"; exec 3>&1; time_left=1; x="$(basename "$f") jq"
EOF
assert_eq "$(scan "$SANDBOX" good.sh)" "" "portable lines flagged"
printf '{ print tolower($0) } # and or not\n' > "$SANDBOX/good.awk"
assert_eq "$(scan "$SANDBOX" good.awk)" "" "portable awk flagged"

# scripts <repo> — the files on disk (tracked or not) under the roots of the CI shellcheck job (plugins, scripts,
# tests): shell scripts (*.sh, or an extensionless file with a shell shebang) and awk programs (*.awk: the hooks run
# them with the macOS awk, so the gawk-only pattern scans them). Other files (*.md, templates without a shell shebang)
# are not code.
scripts() {
  (cd "$1" && find plugins scripts tests -type f 2>/dev/null | while IFS= read -r f; do
    [ "$f" = tests/test_portability.sh ] && continue
    case "$f" in *.sh|*.awk) ;; *) head -1 "$f" | grep -qE '^#!.*sh' || continue ;; esac
    echo "$f"
  done)
}

# Self-check: new scripts not yet added to git and names with spaces are scanned too.
R="$SANDBOX/repo"; mkdir -p "$R/plugins/p/skills/s/scripts" "$R/plugins/p/hooks" "$R/scripts/git-hooks"; git -C "$R" init -q
echo 'echo ok' > "$R/scripts/tool.sh"; git -C "$R" add scripts/tool.sh
echo 'mapfile -t x' > "$R/plugins/p/skills/new.sh"; echo 'grep -P x' > "$R/plugins/p/skills/a b.sh"
printf '#!/usr/bin/env bash\necho ok\n' > "$R/scripts/git-hooks/pre-x"      # no extension, shebang
printf '#!/bin/bash\necho ok\n' > "$R/plugins/p/hooks/guard.sh"
printf '#!/bin/bash\necho ok\n' > "$R/plugins/p/skills/s/scripts/run"
printf '#!/usr/bin/awk -f\n{ print }\n' > "$R/scripts/lex.awk"               # awk: scanned for gawk-only awk
printf '# notes\n' > "$R/plugins/p/skills/s/readme.md"
assert_eq "$(scripts "$R" | LC_ALL=C sort | tr '\n' ';')" \
  "plugins/p/hooks/guard.sh;plugins/p/skills/a b.sh;plugins/p/skills/new.sh;plugins/p/skills/s/scripts/run;scripts/git-hooks/pre-x;scripts/lex.awk;scripts/tool.sh;" \
  "script list"

# Every shell script and awk program in the repo.
LIST=(); while IFS= read -r f; do LIST[${#LIST[@]}]="$f"; done < <(scripts "$ROOT")
scan "$ROOT" "${LIST[@]}" > "$SANDBOX/hits"
[ -s "$SANDBOX/hits" ] && fail "not portable to macOS bash 3.2 / BSD: $(cat "$SANDBOX/hits")" || pass
scripts "$ROOT" | grep -qx 'plugins/corecrew/scripts/save' && pass || fail "scripts without .sh not scanned"
for want in plugins/corecrew/hooks/guard-code.sh plugins/corecrew/skills/new-project/scripts/scaffold.sh plugins/corecrew/scripts/git-hooks/pre-commit-code plugins/coreopinion/skills/second-opinion/scripts/ask-gpt.sh plugins/coremodel/codex/hint.sh; do
  scripts "$ROOT" | grep -qx "$want" && pass || fail "$want not scanned"
done
# every awk program on disk is listed, tracked or not (the count follows the tree; no literal)
assert_eq "$(scripts "$ROOT" | grep -c '\.awk$')" "$(find "$ROOT/plugins" "$ROOT/scripts" "$ROOT/tests" -type f -name '*.awk' | wc -l | tr -d ' ')" "every *.awk is scanned"
finish
