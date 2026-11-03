#!/usr/bin/env bash
# Guards macOS compatibility: shell scripts must run on bash 3.2 with BSD utilities.
source "$(dirname "$0")/lib.sh"
new_sandbox

# label|extended regex (BSD grep -E)
PATTERNS='sed -i|sed([[:space:]]+-[a-zA-Z]+)*[[:space:]]+-[a-zA-Z]*i
grep -P|grep([[:space:]]+-[a-zA-Z]+)*[[:space:]]+-[a-zA-Z]*P
mapfile/readarray|(^|[^a-zA-Z_])(mapfile|readarray)([[:space:]]|$)
${x,,} case change|\$\{[A-Za-z_][A-Za-z0-9_]*(,|\^)
declare -A / local -n|(declare|local|typeset)[[:space:]]+-[a-zA-Z]*[An]
pipe-stderr or append-both redirect|\|&|&>>
date -d|date([[:space:]]+-[a-zA-Z]+)*[[:space:]]+-d
stat -c|stat[[:space:]]+-c
readlink -f|readlink[[:space:]]+-f
find -printf|find[[:space:]].*-printf
xargs -r|xargs([[:space:]]+-[a-zA-Z]+)*[[:space:]]+-[a-zA-Z]*r'

# scan <file> — prints "<file>:<line>: <label>" for each forbidden construct
scan() {
  printf '%s\n' "$PATTERNS" | while IFS='|' read -r label re; do
    grep -nE -- "$re" "$1" | sed "s|^\([0-9]*\):.*|$1:\1: $label|"
  done
}

# Self-check: every pattern catches its construct, and portable lines pass.
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
EOF
assert_eq "$(scan "$bad" | wc -l | tr -d ' ')" "12" "self-check hits"
good="$SANDBOX/good.sh"
cat > "$good" <<'EOF'
sed -n 's/a/b/p' f > f.tmp && mv f.tmp f
grep -qiE 'x' f
echo "${name:-a,b}" | tr '[:upper:]' '[:lower:]'
cmd > log 2>&1
local dir="$1"
EOF
assert_eq "$(scan "$good")" "" "portable lines flagged"

# Every shell script in the repo: *.sh or a file with a shell shebang.
cd "$ROOT" || exit 1
for f in install.sh $(git ls-files skills tests); do
  [ "$f" = tests/test_portability.sh ] && continue
  case "$f" in *.sh) ;; *) head -1 "$f" | grep -qE '^#!.*sh' || continue ;; esac
  hits="$(scan "$f")"
  [ -z "$hits" ] && pass || fail "not portable to macOS bash 3.2 / BSD: $hits"
done
finish
