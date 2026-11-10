#!/usr/bin/env bash
# hooks/guard-code.sh, read-only checkers: inside the corecrew agents designer, localizer, security and
# verifier (hook input agent_type), a Bash command that changes files outside the temp folders is
# refused: redirects, tee, touch, cp, mv, mkdir, rm, ln, in-place sed or perl edits, and git commands that change
# the repo. Reading, running tests and writing logs under the temp folders pass. Other agents and the
# main chat are not affected.
source "$(dirname "$0")/lib.sh"
new_sandbox
H="$HOOKS/guard-code.sh"
unset CLAUDE_PLUGIN_OPTION_CORE_DIR
setup_core >/dev/null 2>&1
mkdir -p "$CORE_DIR/ro-app"; : > "$CORE_DIR/ro-app/CLAUDE.md"   # the project: its private folder in the Core
C="$SANDBOX/Projects/ro-app"; mkdir -p "$C/src"; : > "$C/src/a.txt"
TMPD="$(cd "${TMPDIR:-/tmp}" && pwd -P)"

# run_as <agent_type> <command> [cwd] — exit code in RC, stderr in ERR
run_as() {
  local at=""; [ -n "$1" ] && at="$(printf ',"agent_id":"a1","agent_type":"%s"' "$1")"
  local cmd; cmd="$(printf '%s' "$2" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
  ERR="$(printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"}%s}' "${3:-$C}" "$cmd" "$at" | bash "$H" 2>&1 >/dev/null)"; RC=$?
}
refused() { run_as "$1" "$2" "$3"; assert_eq "$RC" "2" "$1 refused: $2"; case "$ERR" in *read-only*) pass ;; *) fail "no read-only reason for: $2 ($ERR)" ;; esac; }
allowed() { run_as "$1" "$2" "$3"; assert_eq "$RC" "0" "${1:-main} allowed: $2 ($ERR)"; }

V=corecrew:verifier
# writes into the project
refused $V 'echo x > src/a.txt'
refused $V 'printf x >> src/new.txt'
refused $V 'tee src/out.txt < /dev/null'
refused $V 'touch src/b.txt'
refused $V 'cp src/a.txt src/c.txt'
refused $V 'mv src/a.txt src/d.txt'
refused $V 'mkdir src/x'
refused $V 'rm -f src/a.txt'
refused $V 'ln -s src/a.txt src/l'
SEDI="sed -""i"   # spelled in two parts: the portability check reads this file too
refused $V "$SEDI '' s/a/b/ src/a.txt"
refused $V "perl -pi -e s/a/b/ src/a.txt"
# perl reads more switches after -e CODE: "perl -e s/a/b/ -pi f" edits f in place
refused $V "perl -e s/a/b/ -pi src/a.txt"
refused $V "perl -e 1 -i src/a.txt"
refused $V 'git commit -qm x'
refused $V 'git -C . add -A'
refused $V 'git checkout -- src/a.txt'
refused $V 'git reset --hard'
refused $V 'git stash'
refused $V 'git branch -D old'
refused $V 'bash -c "rm src/a.txt"'
refused $V "echo x > /opt/ro-elsewhere.txt"   # outside the temp folders
# the bypasses a first review found: cd, substitutions, cut-off parsing, other writers
refused $V 'cd src && rm a.txt'
refused $V 'cd src && echo x > a.txt'
refused $V 'cd "$HOME" && rm a.txt'                 # an unknown folder: a relative write is refused
refused $V 'echo "$(rm src/a.txt)"'
refused $V 'echo $(touch src/b.txt)'
refused $V 'x="`touch src/b.txt`"'
refused $V 'echo "x<<"y""; rm src/a.txt'           # the tokenizer stops reading: refused, not passed
big=""; i=0; while [ $i -lt 101 ]; do big="$big echo n > /tmp/ro-n$i;"; i=$((i + 1)); done
refused $V "$big rm src/a.txt"                      # past the cap of 100 findings
refused $V 'find . -name x -delete'
refused $V 'find src -exec rm {} +'
refused $V 'xargs rm < /tmp/list'
refused $V 'sort -o src/s.txt src/a.txt'
refused $V 'curl -o src/f https://example.com/f'
refused $V 'curl -O https://example.com/f'
refused $V 'wget https://example.com/f'
refused $V 'tar xf /tmp/a.tar'
refused $V 'unzip /tmp/a.zip'
refused $V 'ln -s /tmp/x /tmp/l'                    # a link can lead a later write anywhere
refused $V 'git branch newb'
refused $V 'git branch -f main HEAD'
refused $V 'git config user.name x'
refused $V 'git remote add o https://example.com/r.git'
refused $V 'git fetch'
refused $V 'git diff --output=src/d.txt'
refused $V 'git tag v1'
refused $V 'git stash push'
refused $V 'git -C . commit -m x'
# the second opinion's findings: cd scope, git -C escapes, cp through a link, sed w, grouped curl options
refused $V '(cd /tmp); rm src/a.txt'
refused $V 'cd /tmp | rm src/a.txt'
refused $V 'cd /tmp && echo x > ro-log.txt'              # after any cd a relative write is refused
refused $V 'git -C /tmp/review config --global user.name x'
refused $V 'git -C /tmp/review push origin main'
refused $V 'git -C /tmp/review --git-dir=.git add -A'
refused $V 'git -C /tmp/review worktree add /tmp/w'
RL="ro-link-$$.txt"   # a name of this run alone: two runs of this file may share one temp folder
ln -s "$C/src/a.txt" "$TMPD/$RL" || fail "could not make the link $TMPD/$RL"
refused $V "cp src/$RL $TMPD"                            # the file lands on a link that leads into the project
rm -f "$TMPD/$RL"
allowed $V "cp src/$RL $TMPD"                            # the same command with no link there
refused $V "sed -n 'w src/out.txt' src/a.txt"
refused $V "sed 's/a/b/w src/out.txt' src/a.txt"
refused $V 'sed -f /tmp/script.sed src/a.txt'
refused $V 'curl -sSLo src/out.txt https://example.com/f'
refused $V 'curl -sSLosrc/out.txt https://example.com/f'
refused $V 'curl -sO https://example.com/f'
refused $V 'curl -D src/h.txt https://example.com'
refused $V 'curl -c src/jar.txt https://example.com'
# reading, tests, logs under the temp folders
allowed $V "cp src/a.txt $TMPD/ro-copy.txt && cp src/a.txt $TMPD/"
allowed $V "sed -n 's/w/x/p' src/a.txt && sed -n '/warn/p' src/a.txt"
allowed $V 'curl -sSLo /tmp/out.txt https://example.com/f && curl -XPOST -H "X-O: 1" https://example.com'
allowed $V 'git -C /tmp/review commit -qm x && git -C /tmp/review config user.name x'
allowed $V 'cd src && cat a.txt && ls'
allowed $V 'git tag && git tag -l && git stash list && git worktree list && git submodule status'
allowed $V 'git apply --check /tmp/p.diff && git notes list && git remote -v && git branch -a && git branch --list'
allowed $V 'git config --get user.name && git config -l && git config user.name'
allowed $V 'git -C /tmp/ro-clone checkout -b x'
allowed $V 'git clone . /tmp/ro-copy'
allowed $V 'perl -Ilib -MList::Util -e 1'
allowed $V 'perl -ne print src/a.txt && perl -e 1 -w src/a.txt && perl -eprint src/a.txt'
allowed $V 'truncate -s 0 /tmp/ro-a.txt'   # -s takes the size: the temp file is the target
refused $V 'ln -s /tmp/ro-x /tmp/ro-l'     # ln keeps its own rule, -s or not
allowed $V 'chmod -R u+w /tmp/d'
allowed $V 'curl -s https://example.com && curl -o /tmp/f https://example.com/f && wget -qO- https://example.com'
allowed $V 'unzip -l /tmp/a.zip && tar tf /tmp/a.tar && tar xf /tmp/a.tar -C /tmp/x'
allowed $V 'sort src/a.txt | uniq -c && find src -name "*.txt"'
allowed $V 'xargs grep -n x < /tmp/list'
allowed $V 'cat src/a.txt'
allowed $V 'git status --short && git diff && git log --oneline -3 && git branch'
allowed $V "sed -n 1,5p src/a.txt"
allowed $V "npm test > $TMPD/ro-log.txt 2>&1"
allowed $V "swift test 2>&1 | tee /tmp/ro-log.txt"
allowed $V "cp src/a.txt $TMPD/copy.txt"
allowed $V "cp src/a.txt $TMPD/copy.txt 0</dev/null"   # 0< is a descriptor: the destination is still the last word
allowed $V 'cat src/a.txt 2>&1<src/a.txt'
allowed $V "rm -f /tmp/ro-log.txt"
allowed $V 'ls > /dev/null 2>&1'
allowed $V 'echo x > "$TMPDIR/log.txt"'   # a target with a variable is not judged (fails open)
# --- every word of the reader's lists and every rule of its own, one line each (scripts/bashlex-readonly.awk). The
# hook only reads the command text: nothing here runs.
# the tracked commands that write, each with a target in the project, and its twin under the temp folders
for c in 'rsync -a src/a.txt src/b.txt' 'truncate -s 0 src/a.txt' 'unlink src/a.txt' 'shred src/a.txt' 'chmod +x src/a.txt' \
         'chmod 644 src/a.txt' 'chown me src/a.txt' 'dd if=/dev/zero of=src/a.txt' "g$SEDI s/a/b/ src/a.txt" 'patch -p1 src/a.txt /tmp/a.diff' \
         'rmdir src/x' 'install -m 644 /tmp/a src/a' 'pushd src && rm a.txt' 'popd && rm a.txt' 'mv /tmp/ro-a.txt src/e.txt' \
         'mv src/a.txt /tmp/ro-a.txt' 'touch -- -x' 'cp -- /tmp/a -x' 'ln /tmp/ro-x /tmp/ro-l' 'patch -p1 < /tmp/a.diff' \
         'git branch --unset-upstream' 'chmod -x src/a.txt'; do
  refused $V "$c"
done
for c in 'rsync -a src/a.txt /tmp/ro-b.txt' 'truncate --size 0 /tmp/ro-a.txt' 'unlink /tmp/ro-a.txt' \
         'shred /tmp/ro-a.txt' 'chmod +x /tmp/ro-a.txt' 'chmod 644 /tmp/ro-a.txt' 'chown me /tmp/ro-a.txt' 'dd if=src/a.txt of=/tmp/ro-a.txt' \
         'rmdir /tmp/ro-x' 'install -m 644 src/a.txt /tmp/ro-a' 'mv /tmp/ro-a.txt /tmp/ro-b.txt' 'pushd src && cat a.txt' 'gsed -n 1p src/a.txt'; do
  allowed $V "$c"
done
# after cd, pushd or popd a relative write is refused wherever the hook started, also in a temp folder
for c in 'cd /opt && echo x > ro-log.txt' 'pushd /opt && echo x > ro-log.txt' 'popd && echo x > ro-log.txt'; do refused $V "$c" /tmp; done
allowed $V 'echo x > ro-log.txt' /tmp
# xargs and find -exec: every command that changes files whatever its arguments; a reader passes through xargs
for w in rm rmdir mv cp touch mkdir tee ln chmod chown truncate unlink shred install rsync dd patch sed perl git sh bash zsh; do
  refused $V "echo a | xargs $w"
  refused $V "find . -exec $w {} \;"
done
refused $V 'echo a | xargs -n 1 /bin/rm'
allowed $V 'echo a | xargs -n 1 wc -l'
allowed $V 'echo a | xargs -I rm cat'
# find: every predicate that runs a command or writes a file
for w in -execdir -ok -okdir -fprint -fprint0 -fprintf -fls; do refused $V "find . -name x $w /tmp/ro-out"; done
allowed $V 'find . -name x -print -newer src/a.txt'
# git: every subcommand that always changes the work tree, the index, refs or a remote
for w in add commit push pull reset checkout switch restore merge rebase cherry-pick revert am rm mv clean init fetch gc prune \
         update-index update-ref replace filter-branch; do
  refused $V "git $w"
done
# git options that take a value: the word after them is no subcommand
for w in '-c k=v' '--namespace n' '-C .'; do refused $V "git $w commit -qm x"; allowed $V "git $w status"; done
for w in '--git-dir x' '--git-dir=x' '--work-tree x' '--work-tree=x'; do refused $V "git $w status"; done
# the rules of single commands, and the same command reading or writing under the temp folders
for c in 'wget -O src/f https://example.com/f' 'wget --output-document=src/f https://example.com/f' 'wget -P src https://example.com/f' \
         'tar cf src/a.tar x' 'tar -c -f src/a.tar x' 'tar -c x' 'tar xf /tmp/a.tar -C src' 'unzip /tmp/a.zip -d src' 'dd of=src/a' \
         'git clone https://example.com/r.git' 'git clone https://example.com/r.git src/r' 'sed --in-place s/a/b/ src/a.txt' \
         'git submodule update' 'git notes add -m x' 'git apply /tmp/p.diff' 'git config --unset user.name' 'git worktree prune' \
         'curl --output src/f https://example.com/f' 'curl --output=src/f https://example.com/f' 'curl --remote-name https://example.com/f' \
         'sort --output=src/s.txt src/a.txt'; do
  refused $V "$c"
done
for c in 'wget -O - https://example.com/f' 'wget -O /tmp/ro-f https://example.com/f' 'wget -P /tmp https://example.com/f' \
         'tar -c -f /tmp/ro-a.tar src' 'tar tf /tmp/a.tar' 'unzip /tmp/a.zip -d /tmp/ro-x' 'unzip -l /tmp/a.zip' 'dd if=src/a.txt of=/tmp/ro-a' \
         'git clone https://example.com/r.git /tmp/ro-r' 'git apply --check /tmp/p.diff' 'git apply --stat /tmp/p.diff' 'git submodule status' \
         'git notes show' 'curl --output /tmp/ro-f https://example.com/f' 'sort --output=/tmp/ro-s.txt src/a.txt'; do
  allowed $V "$c"
done
# the temp roots, each alone: with TMPDIR naming a folder outside /tmp and /var/folders, a write under each root passes,
# and the one under that folder passes only while TMPDIR names it
for c in /tmp/ro-x.txt /private/tmp/ro-x.txt /var/folders/ro/x.txt /private/var/folders/ro/x.txt /opt/ro-tmp/x.txt; do
  TMPDIR=/opt/ro-tmp allowed $V "echo x > $c"
done
TMPDIR=/opt/ro-tmp refused $V 'echo x > /opt/ro-other/x.txt'
refused $V 'echo x > /opt/ro-tmp/x.txt'
# every read-only checker, also by its bare name; outside a project too
for a in corecrew:designer corecrew:localizer corecrew:security verifier designer; do refused "$a" 'echo x > src/a.txt'; done
refused $V "echo x > /opt/ro-elsewhere.txt" "$SANDBOX"
# the sandbox (and so this project) sits inside the temp folder: a project there is still the project
refused $V "echo x > $C/src/abs.txt"
# the authors and other agents are not affected
allowed corecrew:engineer 'echo x > src/a.txt'
allowed corecrew:tester 'rm -f src/a.txt'
allowed other:verifier 'rm -f src/a.txt'
allowed Explore 'echo x > src/a.txt'
allowed "" 'rm -f src/a.txt'
# a broken checker refuses instead of letting everything through (it fails closed for these agents)
BP="$SANDBOX/broken-plugin"; mkdir -p "$BP"; cp -R "$PLUGIN/hooks" "$PLUGIN/scripts" "$BP/"
printf 'BEGIN { this is not awk\n' > "$BP/scripts/bashlex-readonly.awk"
OLDH="$H"; H="$BP/hooks/guard-code.sh"
run_as $V 'ls'; assert_eq "$RC" "2" "broken checker: refused"
H="$OLDH"
# with ui_language ru the refusal stays English: only a subagent told to work in English reads it (MSG_EN_ONLY)
CLAUDE_PLUGIN_OPTION_UI_LANGUAGE=ru run_as $V 'rm -f src/a.txt'
assert_eq "$RC" "2" "ru: refused"
case "$ERR" in *"is a read-only checker and must not change anything ("*) pass ;; *) fail "ru: the refusal is not English: $ERR" ;; esac
case "$ERR" in *"только читает"*) fail "ru: the refusal has Russian: $ERR" ;; *) pass ;; esac
finish
