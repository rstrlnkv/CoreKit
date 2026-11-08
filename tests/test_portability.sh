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
xargs -r|xargs([[:space:]]+-[a-zA-Z]+)*[[:space:]]+-[a-zA-Z]*r
jq as a command|(^|[|;&(`]|(do|then|else)[[:space:]])[[:space:]]*jq([[:space:]]|$)'

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
cat f | jq .x
x=$(jq -r .a f)
EOF
assert_eq "$(scan "$bad" | wc -l | tr -d ' ')" "14" "self-check hits"
good="$SANDBOX/good.sh"
cat > "$good" <<'EOF'
sed -n 's/a/b/p' f > f.tmp && mv f.tmp f
grep -qiE 'x' f
echo "${name:-a,b}" | tr '[:upper:]' '[:lower:]'
cmd > log 2>&1
local dir="$1"
gh api repos/x --jq .private
# hook JSON without jq (no jq)
EOF
assert_eq "$(scan "$good")" "" "portable lines flagged"

# scripts <repo> — shell scripts on disk (tracked or not) in scripts/ (incl. git-hooks/), hooks/,
# skills/ (incl. skills/*/scripts/), tests/ and plugins/ (every plugin of the marketplace): *.sh, or an extensionless file with a shell
# shebang. Other files (*.awk, *.md, templates without a shell shebang) are not shell code.
scripts() {
  (cd "$1" && find skills scripts hooks tests plugins -type f 2>/dev/null | while IFS= read -r f; do
    [ "$f" = tests/test_portability.sh ] && continue
    case "$f" in *.sh) ;; *) head -1 "$f" | grep -qE '^#!.*sh' || continue ;; esac
    echo "$f"
  done)
}

# Self-check: new scripts not yet added to git and names with spaces are scanned too.
R="$SANDBOX/repo"; mkdir -p "$R/skills/s/scripts" "$R/scripts/git-hooks" "$R/hooks"; git -C "$R" init -q
echo 'echo ok' > "$R/scripts/tool.sh"; git -C "$R" add scripts/tool.sh
echo 'mapfile -t x' > "$R/skills/new.sh"; echo 'grep -P x' > "$R/skills/a b.sh"
printf '#!/usr/bin/env bash\necho ok\n' > "$R/scripts/git-hooks/pre-x"      # no extension, shebang
printf '#!/bin/bash\necho ok\n' > "$R/hooks/guard.sh"
printf '#!/bin/bash\necho ok\n' > "$R/skills/s/scripts/run"
printf '#!/usr/bin/awk -f\n{ print }\n' > "$R/scripts/lex.awk"               # awk: not shell
printf '# notes\n' > "$R/skills/s/readme.md"
assert_eq "$(scripts "$R" | LC_ALL=C sort | tr '\n' ';')" \
  "hooks/guard.sh;scripts/git-hooks/pre-x;scripts/tool.sh;skills/a b.sh;skills/new.sh;skills/s/scripts/run;" \
  "script list"

# Every shell script in the repo.
scripts "$ROOT" | while IFS= read -r f; do
  hits="$(scan "$ROOT/$f")"
  [ -z "$hits" ] || echo "$hits"
done > "$SANDBOX/hits"
[ -s "$SANDBOX/hits" ] && fail "not portable to macOS bash 3.2 / BSD: $(cat "$SANDBOX/hits")" || pass
scripts "$ROOT" | grep -qx 'plugins/corecrew/scripts/save' && pass || fail "scripts without .sh not scanned"
for want in plugins/corecrew/hooks/guard-code.sh plugins/corecrew/skills/new-project/scripts/scaffold.sh plugins/corecrew/scripts/git-hooks/pre-commit-code plugins/coreopinion/skills/second-opinion/scripts/ask-gpt.sh; do
  scripts "$ROOT" | grep -qx "$want" && pass || fail "$want not scanned"
done
finish
