#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
new_sandbox; setup_core; sync_tools
scaffold_old hook-app
P="$CORE_DIR/hook-app"; C="$P/code"
assert_exit 0 bash "$SCRIPTS/install-hooks.sh" "$P"
assert_file "$C/.git/hooks/pre-commit"; assert_file "$C/.git/hooks/pre-push"
assert_file "$CORE_DIR/.git/hooks/pre-push"
# the three hooks are shims that run the tools copy; blocked-patterns stays out of .git/hooks
for h in "$C/.git/hooks/pre-commit" "$C/.git/hooks/pre-push" "$CORE_DIR/.git/hooks/pre-push"; do
  assert_contains "$h" "# corecrew hook shim"; [ -x "$h" ] && pass || fail "not executable: $h"
done
assert_contains "$C/.git/hooks/pre-commit" "$COREDEV_TOOLS/git-hooks/pre-commit-code"
assert_contains "$C/.git/hooks/pre-push" "$COREDEV_TOOLS/git-hooks/pre-push-code"
assert_contains "$CORE_DIR/.git/hooks/pre-push" "$COREDEV_TOOLS/git-hooks/pre-push-core"
assert_no_file "$C/.git/hooks/blocked-patterns"
# idempotent
assert_exit 0 bash "$SCRIPTS/install-hooks.sh" "$P"

try_commit() {  # try_commit <path> ; force-add past .gitignore to test the hook itself
  mkdir -p "$C/$(dirname "$1")"; echo x > "$C/$1"
  git -C "$C" add -f "$1"
  git -C "$C" commit -q -m "add $1" >/dev/null 2>&1; local rc=$?
  git -C "$C" reset -q 2>/dev/null; return $rc
}
for bad in CLAUDE.md sub/CLAUDE.local.md AGENTS.md sub/AGENTS.md agents.md .claude/x.json .env .env.local docs/superpowers/plan.md a.pem k.key; do
  try_commit "$bad" && fail "commit allowed: $bad" || pass
  rm -rf "${C:?}/${bad:?}"
done
for ok in .env.example .env.sample .env.template sub/.env.sample src/main.dart docs/README.md MYAGENTS.md AGENTS.md.bak; do
  try_commit "$ok" && pass || fail "commit blocked: $ok"
done
# blocked commit message names the file
echo x > "$C/CLAUDE.md"; git -C "$C" add -f CLAUDE.md
OUT=$(git -C "$C" commit -m t 2>&1); echo "$OUT" | grep -q 'CLAUDE.md' && pass || fail "message lacks file name"
git -C "$C" reset -q; rm -f "$C/CLAUDE.md"

# pre-push catches a --no-verify commit
git init -q --bare "$SANDBOX/remote.git"; git -C "$C" remote add origin "$SANDBOX/remote.git"
git -C "$C" push -q origin main 2>/dev/null && pass || fail "clean push failed"
# pre-push allows the same .env templates (committed with --no-verify, so only pre-push judges them)
for ok in cfg/.env.example cfg/.env.sample cfg/.env.template; do
  mkdir -p "$C/cfg"; echo x > "$C/$ok"; git -C "$C" add -f "$ok"; git -C "$C" commit -q --no-verify -m "add $ok"
done
git -C "$C" push -q origin main 2>/dev/null && pass || fail "push of .env.example/.sample/.template blocked"
echo x > "$C/cfg/.env.prod"; git -C "$C" add -f cfg/.env.prod; git -C "$C" commit -q --no-verify -m "add env"
git -C "$C" push -q origin main 2>/dev/null && fail "push of cfg/.env.prod allowed" || pass
git -C "$C" reset -q --hard HEAD~1
echo x > "$C/CLAUDE.md"; git -C "$C" add -f CLAUDE.md; git -C "$C" commit -q --no-verify -m sneaky
git -C "$C" push -q origin main 2>"$SANDBOX/push.err" && fail "push of CLAUDE.md allowed" || pass
# the advice fits both hosts
assert_contains "$SANDBOX/push.err" "Remove them from history before pushing (ask your assistant to help)."

# pp_repo <dir>: a new repo with corecrew's pre-push shim and a bare remote <dir>.git as origin
pp_repo() {
  git init -q "$1" && cp "$C/.git/hooks/pre-push" "$1/.git/hooks/pre-push" && git init -q --bare "$1.git" \
    && git -C "$1" remote add origin "$1.git"
}
# nv_commit <repo> <path>...: commits the files past .gitignore and pre-commit, so only pre-push judges them
nv_commit() {
  local r="$1" p; shift
  for p in "$@"; do mkdir -p "$r/$(dirname "$p")"; echo x > "$r/$p"; git -C "$r" add -f "$p"; done
  git -C "$r" -c user.name=t -c user.email=t@t commit -q --no-verify -m "add $*"
}
# a root commit is checked too: the first push of a new repo, and of an orphan branch
R1="$SANDBOX/root one"; pp_repo "$R1"; nv_commit "$R1" CLAUDE.md
git -C "$R1" push -q origin HEAD:refs/heads/main 2>/dev/null && fail "first push of a root commit holding CLAUDE.md allowed" || pass
R2="$SANDBOX/root two"; pp_repo "$R2"; nv_commit "$R2" .env; nv_commit "$R2" src/a.txt
git -C "$R2" push -q origin HEAD:refs/heads/main 2>/dev/null && fail "first push of a root commit holding .env allowed" || pass
R3="$SANDBOX/root three"; pp_repo "$R3"; nv_commit "$R3" src/a.txt .env.example; nv_commit "$R3" src/b.txt
git -C "$R3" push -q origin HEAD:refs/heads/main 2>/dev/null && pass || fail "a legitimate first push was blocked"
nv_commit "$R3" src/c.txt
git -C "$R3" push -q origin HEAD:refs/heads/main 2>/dev/null && pass || fail "a legitimate normal push was blocked"
git -C "$R3" checkout -q --orphan side && git -C "$R3" rm -rq --cached . && nv_commit "$R3" AGENTS.md
git -C "$R3" push -q origin side 2>/dev/null && fail "push of an orphan branch whose root commit holds AGENTS.md allowed" || pass
git -C "$R3" checkout -q --orphan pages && git -C "$R3" rm -rq --cached . && nv_commit "$R3" index.html
git -C "$R3" push -q origin pages 2>/dev/null && pass || fail "a legitimate orphan branch push was blocked"
git -C "$R3" checkout -q -f main
# a remote tip this repo never fetched (another clone pushed it): the commits are still checked (a forced push)
git clone -q -b main "$R3.git" "$SANDBOX/other clone" && nv_commit "$SANDBOX/other clone" src/z.txt \
  && git -C "$SANDBOX/other clone" push -q origin HEAD:refs/heads/main && pass || fail "setup: the other clone's push"
nv_commit "$R3" CLAUDE.md
git -C "$R3" push -q --force origin HEAD:refs/heads/main 2>/dev/null && fail "forced push over an unknown remote tip let CLAUDE.md through" || pass
git -C "$R3" reset -q --hard HEAD~1; nv_commit "$R3" src/d.txt
git -C "$R3" push -q --force origin HEAD:refs/heads/main 2>/dev/null && pass || fail "a legitimate forced push over an unknown remote tip was blocked"
# when git cannot list the commits at all, nothing can be checked: the push is blocked with a plain line
NL="$SANDBOX/nolist"; mkdir -p "$NL"
printf '#!/bin/sh\ncase "$*" in *rev-list*) exit 128 ;; esac\nexec "%s" "$@"\n' "$(command -v git)" > "$NL/git"; chmod +x "$NL/git"
(cd "$R3" && printf 'refs/heads/main %s refs/heads/main %s\n' "$(git rev-parse HEAD)" 1111111111111111111111111111111111111111 \
  | PATH="$NL:$PATH" bash "$COREDEV_TOOLS/git-hooks/pre-push-code" origin "$R3.git") 2>"$SANDBOX/nolist.err" \
  && fail "push allowed when the commits could not be listed" || pass
assert_contains "$SANDBOX/nolist.err" "git could not list the commits to push"

# Core pre-push: privacy check via gh
STUB="$SANDBOX/stub"; mkdir -p "$STUB"
printf '#!/bin/sh\necho "$GH_STUB"\n' > "$STUB/gh"; chmod +x "$STUB/gh"
H="$CORE_DIR/.git/hooks/pre-push"; URL=https://github.com/someone/Core.git
GH_STUB=true  PATH="$STUB:$PATH" bash "$H" origin "$URL" </dev/null >/dev/null 2>&1 && pass || fail "private Core push blocked"
GH_STUB=false PATH="$STUB:$PATH" bash "$H" origin "$URL" </dev/null >/dev/null 2>&1 && fail "public Core push allowed" || pass
PATH="$(path_without gh)" bash "$H" origin "$URL" </dev/null >/dev/null 2>"$SANDBOX/nogh" && fail "push allowed without gh" || pass
# the install hint is for every OS, the same as preflight's: the GitHub CLI site, not one package manager
assert_contains "$SANDBOX/nogh" "https://cli.github.com"; assert_not_contains "$SANDBOX/nogh" "brew"
GH_STUB=true PATH="$STUB:$PATH" bash "$H" origin "git@github.com:someone/Core.git" </dev/null >/dev/null 2>&1 && pass || fail "ssh url not parsed"
# a failed gh call (network) is retried: 2 failures then "true" pass, 3 failures block, "false" is final
FL="$SANDBOX/flaky"; mkdir -p "$FL"
cat > "$FL/gh" <<'STUBEOF'
#!/bin/sh
n=$(cat "$GH_COUNT" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$GH_COUNT"
if [ "$n" -le "$GH_FAILS" ]; then echo "TLS handshake timeout" >&2; exit 1; fi
echo "$GH_ANSWER"
STUBEOF
chmod +x "$FL/gh"
CNT="$SANDBOX/gh.count"
rm -f "$CNT"; GH_COUNT="$CNT" GH_FAILS=2 GH_ANSWER=true CORECREW_GH_RETRY_SLEEP=0 PATH="$FL:$PATH" bash "$H" origin "$URL" </dev/null >/dev/null 2>&1 && pass || fail "push blocked after 2 failed gh calls"
assert_eq "$(cat "$CNT")" "3" "gh called three times"
rm -f "$CNT"; GH_COUNT="$CNT" GH_FAILS=3 GH_ANSWER=true CORECREW_GH_RETRY_SLEEP=0 PATH="$FL:$PATH" bash "$H" origin "$URL" </dev/null >/dev/null 2>&1 && fail "push allowed after 3 failed gh calls" || pass
assert_eq "$(cat "$CNT")" "3" "gh tried at most three times"
rm -f "$CNT"; GH_COUNT="$CNT" GH_FAILS=0 GH_ANSWER=false CORECREW_GH_RETRY_SLEEP=0 PATH="$FL:$PATH" bash "$H" origin "$URL" </dev/null >/dev/null 2>&1 && fail "public Core push allowed (flaky stub)" || pass
assert_eq "$(cat "$CNT")" "1" "a public answer is not retried"

# --- shim edge cases
# tools file missing: the commit fails and the message names the fix and the shim
mv "$COREDEV_TOOLS/git-hooks/pre-commit-code" "$SANDBOX/pcc"
echo x > "$C/ok.txt"; git -C "$C" add ok.txt
OUT=$(git -C "$C" commit -m t 2>&1); rc=$?
[ $rc -ne 0 ] && pass || fail "commit allowed with tools file missing"
echo "$OUT" | grep -q 'is missing' && pass || fail "no 'is missing' message: $OUT"
# the shim names the host that installed it (COREKIT_HOST in tests, else the plugin's place on disk)
echo "$OUT" | grep -qF 'Start a Claude Code session with corecrew enabled, or remove this hook' && pass || fail "no fix hint: $OUT"
echo "$OUT" | grep -qF "rm \"$C/.git/hooks/pre-commit\"" && pass || fail "no rm hint: $OUT"
mv "$SANDBOX/pcc" "$COREDEV_TOOLS/git-hooks/pre-commit-code"; git -C "$C" reset -q; rm -f "$C/ok.txt"
# installed from Codex, the shim names Codex
COREKIT_HOST=codex bash "$SCRIPTS/install-hooks.sh" "$P" >/dev/null 2>&1
assert_contains "$C/.git/hooks/pre-commit" "Start a Codex session with corecrew enabled, or remove this hook"
assert_not_contains "$C/.git/hooks/pre-commit" "Claude Code"
mv "$COREDEV_TOOLS/git-hooks/pre-commit-code" "$SANDBOX/pcc"
echo x > "$C/ok.txt"; git -C "$C" add ok.txt
OUT=$(git -C "$C" commit -m t 2>&1) && fail "commit allowed with tools file missing (Codex shim)" || pass
echo "$OUT" | grep -qF 'Start a Codex session with corecrew enabled' && pass || fail "no Codex fix hint: $OUT"
mv "$SANDBOX/pcc" "$COREDEV_TOOLS/git-hooks/pre-commit-code"; git -C "$C" reset -q; rm -f "$C/ok.txt"
COREKIT_HOST=claude bash "$SCRIPTS/install-hooks.sh" "$P" >/dev/null 2>&1
assert_contains "$C/.git/hooks/pre-commit" "Start a Claude Code session with corecrew enabled"

# an old 0.1.x hook (marker "new-project hook") is replaced by a shim
printf '#!/bin/sh\n# new-project hook: OLDBODY\nexit 0\n' > "$C/.git/hooks/pre-commit"
assert_exit 0 bash "$SCRIPTS/install-hooks.sh" "$P"
assert_contains "$C/.git/hooks/pre-commit" "# corecrew hook shim"
assert_not_contains "$C/.git/hooks/pre-commit" "OLDBODY"

# a 0.2.x shim (marker "coredev hook shim") is replaced by a current shim
printf '#!/bin/sh\n# coredev hook shim\nT=OLDSHIM\n' > "$C/.git/hooks/pre-commit"
assert_exit 0 bash "$SCRIPTS/install-hooks.sh" "$P"
assert_contains "$C/.git/hooks/pre-commit" "# corecrew hook shim"
assert_not_contains "$C/.git/hooks/pre-commit" "OLDSHIM"

# a foreign hook is left alone and warned about
printf '#!/bin/sh\n# mine\nexit 0\n' > "$C/.git/hooks/pre-push"
assert_exit 0 bash "$SCRIPTS/install-hooks.sh" "$P"
echo "$OUT" | grep -q 'WARN' && echo "$OUT" | grep -q 'left unchanged' && pass || fail "no WARN for foreign hook: $OUT"
assert_contains "$C/.git/hooks/pre-push" "# mine"; assert_not_contains "$C/.git/hooks/pre-push" "corecrew hook shim"

# --tools overrides the default; a tools dir with a space works
T2="$SANDBOX/my tools"; bash "$SCRIPTS/sync-tools.sh" "$PLUGIN" "$T2" >/dev/null
rm -f "$C/.git/hooks/pre-push"
assert_exit 0 bash "$SCRIPTS/install-hooks.sh" "$P" --tools "$T2"
assert_contains "$C/.git/hooks/pre-push" "$T2/git-hooks/pre-push-code"
# (CLAUDE.md is already tracked by the --no-verify test above, so use a fresh blocked file)
echo secret > "$C/.env.local"; git -C "$C" add -f .env.local
OUT=$(git -C "$C" commit -m t 2>&1) && fail "commit allowed with tools in a path with a space" || pass
echo "$OUT" | grep -q 'Commit blocked' && pass || fail "shim with a spaced tools path did not run the hook body: $OUT"
git -C "$C" reset -q; rm -f "$C/.env.local"
echo ok > "$C/clean.txt"; git -C "$C" add clean.txt
git -C "$C" commit -q -m clean >/dev/null 2>&1 && pass || fail "clean commit blocked with tools in a path with a space"

# install-hooks run from the plugin syncs the tools first: empty tools dir, then a clean commit works
new_sandbox; setup_core
scaffold_old fresh-app
C="$CORE_DIR/fresh-app/code"
assert_no_file "$COREDEV_TOOLS"
assert_exit 0 bash "$SCRIPTS/install-hooks.sh" "$CORE_DIR/fresh-app"
assert_file "$COREDEV_TOOLS/VERSION"; assert_file "$COREDEV_TOOLS/git-hooks/blocked-patterns"
echo ok > "$C/clean.txt"; git -C "$C" add clean.txt
git -C "$C" commit -q -m clean >/dev/null 2>&1 && pass || fail "first commit blocked on a fresh machine"
# run from the tools copy, install-hooks does not sync (no plugin.json next to it)
echo 0.0.0 > "$COREDEV_TOOLS/VERSION"
assert_exit 0 bash "$COREDEV_TOOLS/install-hooks.sh" "$CORE_DIR/fresh-app"
assert_eq "$(cat "$COREDEV_TOOLS/VERSION")" "0.0.0" "install-hooks from the tools copy must not sync"

# missing hook sources: plain message, exit 1
BROKEN="$SANDBOX/broken"; mkdir -p "$BROKEN"; cp "$SCRIPTS/install-hooks.sh" "$BROKEN/"
assert_exit 1 bash "$BROKEN/install-hooks.sh" "$P"
echo "$OUT" | grep -q 'hooks installed' && fail "claimed success without sources" || pass
echo "$OUT" | grep -qi 'missing\|not found' && pass || fail "no plain message: $OUT"
# new layout: code repo beside the Core (<Projects>/Foo), project dir argument is <Core>/foo
new_sandbox; setup_core; sync_tools
F="$SANDBOX/Projects/Foo"; mkdir -p "$F" "$CORE_DIR/foo"; git -C "$F" init -q
assert_exit 0 bash "$SCRIPTS/install-hooks.sh" "$CORE_DIR/foo"
for h in "$F/.git/hooks/pre-commit" "$F/.git/hooks/pre-push" "$CORE_DIR/.git/hooks/pre-push"; do
  assert_contains "$h" "# corecrew hook shim"
done
assert_no_file "$CORE_DIR/foo/code"
# no code folder at all: exit 1, names the missing folder
mkdir -p "$CORE_DIR/bar"
assert_exit 1 bash "$SCRIPTS/install-hooks.sh" "$CORE_DIR/bar"
echo "$OUT" | grep -q 'No git repo at' && pass || fail "no 'No git repo at' message: $OUT"

# the pre-commit hook on non-ASCII paths and case variants; a missing patterns file fails closed
new_sandbox; setup_core; sync_tools; scaffold_old hk-app; C="$CORE_DIR/hk-app/code"
bash "$SCRIPTS/install-hooks.sh" "$CORE_DIR/hk-app" >/dev/null
for bad in "папка/CLAUDE.md" "é/.env" Claude.md .ENV; do
  try_commit "$bad" && fail "commit allowed: $bad" || pass
  rm -rf "${C:?}/${bad:?}"
done
mv "$COREDEV_TOOLS/git-hooks/blocked-patterns" "$SANDBOX/bp"
try_commit src/ok.txt && fail "missing patterns file must fail closed" || pass
# the fix names no single host: the static hook cannot know which one installed it
mkdir -p "$C/src"; echo x > "$C/src/ok.txt"; git -C "$C" add src/ok.txt
OUT=$(git -C "$C" commit -q -m t 2>&1); git -C "$C" reset -q; rm -rf "${C:?}/src"
echo "$OUT" | grep -qF "Start a new session of the assistant that installed these hooks (Claude Code or Codex) with corecrew enabled to refresh the tools." \
  && pass || fail "missing patterns: no host-neutral fix: $OUT"
mv "$SANDBOX/bp" "$COREDEV_TOOLS/git-hooks/blocked-patterns"
# the exception list: a missing one fails closed too; a blank line in it (which grep would read as "matches every path")
# lets nothing through
AP="$COREDEV_TOOLS/git-hooks/allowed-patterns"
assert_file "$AP"
mv "$AP" "$SANDBOX/ap"
try_commit src/ok.txt && fail "missing allowed-patterns must fail closed" || pass
mv "$SANDBOX/ap" "$AP"
cp "$AP" "$SANDBOX/ap.keep"; { printf '\n'; cat "$SANDBOX/ap.keep"; printf '  \n\n'; } > "$AP"
try_commit .env && fail "a blank line in allowed-patterns let .env through" || pass
rm -rf "${C:?}/.env"
try_commit .env.example && pass || fail "a blank line in allowed-patterns blocked .env.example"
# pre-push too (a clean root commit first, so only the blank line is judged)
R4="$SANDBOX/blank line"; pp_repo "$R4"; nv_commit "$R4" src/a.txt; nv_commit "$R4" CLAUDE.md
git -C "$R4" push -q origin HEAD:refs/heads/main 2>/dev/null && fail "a blank line in allowed-patterns let CLAUDE.md through pre-push" || pass
git -C "$R4" reset -q --hard HEAD~1; nv_commit "$R4" cfg/.env.example
git -C "$R4" push -q origin HEAD:refs/heads/main 2>/dev/null && pass || fail "a blank line in allowed-patterns blocked .env.example in pre-push"
cp "$SANDBOX/ap.keep" "$AP"

# --- One list. The hooks (blocked-patterns minus allowed-patterns) and templates/code/gitignore-common agree on every
# sample path of the Internal and Secrets sections, through both real hook bodies of the plugin. One difference is on
# purpose (Decision 26 a): a nested .claude/ folder is ignored by .gitignore and blocked by neither hook (ADR 009 and
# guard-code treat only the root .claude/ as private). Case is pinned: the hooks match case-insensitively, so
# check-ignore runs with core.ignorecase=true on every OS. Paths are staged without files (no case clash on disk).
GIC="$SKILL/templates/code/gitignore-common"; GHK="$SCRIPTS/git-hooks"
TB="$SANDBOX/one list"; git init -q "$TB"; cp "$GIC" "$TB/.gitignore"
NESTED="sub/.claude/settings.json"
SAMPLES="CLAUDE.md
sub/CLAUDE.md
CLAUDE.local.md
deep/er/CLAUDE.local.md
c1/Claude.md
AGENTS.md
sub/AGENTS.md
a1/agents.md
.claude/settings.json
.Claude/x.json
docs/superpowers/plan.md
sub/docs/superpowers/plan.md
docs/README.md
MYAGENTS.md
AGENTS.md.bak
.env
sub/.env
e1/.ENV
.env.local
cfg/.env.prod
.env.example
.env.sample
.env.template
sub/.env.sample
e2/.ENV.EXAMPLE
.env.example.bak
.envrc
a.pem
k.key
sub/server.KEY
x.pem.bak
src/main.dart
$NESTED"
EMPTY="$(git -C "$TB" hash-object -w --stdin </dev/null)"
printf '%s\n' "$SAMPLES" | while IFS= read -r p; do git -C "$TB" update-index --add --cacheinfo "100644,$EMPTY,$p"; done
listed() { sed -n 's/^  - //p'; }   # the "  - <path>" lines a hook prints
IGN="$(printf '%s\n' "$SAMPLES" | git -C "$TB" -c core.ignorecase=true -c core.quotePath=false check-ignore --no-index --stdin)"
PC="$( (cd "$TB" && bash "$GHK/pre-commit-code") 2>&1 >/dev/null | listed)"
git -C "$TB" -c user.name=t -c user.email=t@t commit -q --no-verify -m samples
PP="$( (cd "$TB" && printf 'refs/heads/main %s refs/heads/main %s\n' "$(git rev-parse HEAD)" 0000000000000000000000000000000000000000 \
  | bash "$GHK/pre-push-code" origin "$SANDBOX/none.git") 2>&1 >/dev/null | listed)"
[ -n "$IGN" ] && [ -n "$PC" ] && [ -n "$PP" ] && pass || fail "one list: a side printed nothing (ignored: $IGN; pre-commit: $PC; pre-push: $PP)"
has() { printf '%s\n' "$1" | grep -qxF -e "$2"; }
printf '%s\n' "$SAMPLES" > "$SANDBOX/samples"
while IFS= read -r p; do
  if has "$IGN" "$p"; then i=1; else i=0; fi
  if has "$PC" "$p"; then c=1; else c=0; fi
  if has "$PP" "$p"; then u=1; else u=0; fi
  if [ "$p" = "$NESTED" ]; then
    assert_eq "$i$c$u" "100" "one list: a nested .claude/ is ignored by .gitignore and blocked by neither hook"
  else
    assert_eq "$i$c$u" "$i$i$i" "one list: .gitignore, pre-commit and pre-push disagree on $p (ignored, pre-commit, pre-push)"
  fi
done < "$SANDBOX/samples"
# adopt adds to an existing .gitignore only the lines its filter takes: every Internal line and every .env line
ADOPT_CASE="$(sed -n 's/^ *case "\$l" in \(CLAUDE\*|[^)]*\)) ;; \*) continue ;; esac$/\1/p' "$SCRIPTS/adopt.sh")"
[ -n "$ADOPT_CASE" ] && pass || fail "adopt.sh: the .gitignore filter line was not found"
eval "adopt_takes() { case \"\$1\" in $ADOPT_CASE) return 0 ;; esac; return 1; }"
awk '/^# Internal/ { s = 1; next } /^# Secrets/ { s = 2; next } /^#/ || /^$/ { s = 0 } s == 1 || (s == 2 && /^!?\.env/)' "$GIC" \
  > "$SANDBOX/adopt-lines"
assert_eq "$(grep -c . "$SANDBOX/adopt-lines")" "10" "gitignore-common: Internal and .env lines counted"
while IFS= read -r l; do adopt_takes "$l" && pass || fail "adopt's filter misses the gitignore-common line $l"; done < "$SANDBOX/adopt-lines"

finish
