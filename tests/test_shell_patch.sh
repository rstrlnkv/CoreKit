#!/usr/bin/env bash
# NOTE: the rule is best effort, not a security boundary; the LIMIT cases below list known ways past it.
# lib.sh shell_patch_refused: a substring hit (apply_patch, applypatch, apply-patch after deleting quotes and backslashes,
# a "*** Begin Patch" with a file marker, or a $' with an escape) refuses the command unless it is in the simple form (one reader,
# an allowlisted pipe, no substitution/list/redirect, no program-running option). Covers every input of the seven review
# passes, the pass twins, the documented over-blocking and limits (LIMIT), and the 1 MB time bound.
source "$(dirname "$0")/lib.sh"
new_sandbox
. "$SCRIPTS/lib.sh"
# shellcheck disable=SC2034  # SELF is read by the functions of the sourced lib.sh
SELF="$PLUGIN"
nl="
"
refused() { shell_patch_refused "$1" && pass || fail "$2: not refused: ${1:0:160}"; }
passes()  { shell_patch_refused "$1" && fail "$2: refused: ${1:0:160}" || pass; }

# --- applying a patch: every spelling is refused
for c in 'apply_patch' 'applypatch' 'apply-patch' 'exec apply_patch' 'nohup apply_patch &' 'time apply_patch' \
  'command apply_patch' '\apply_patch' '/abs/path/apply_patch' './apply_patch' 'sudo apply_patch' 'env X=1 apply_patch' \
  'true && apply_patch' '( cd d && apply_patch )' 'cat p | apply_patch' 'xargs apply_patch' 'xargs -0 -n1 apply_patch' \
  "alias ap=apply_patch; ap" 'F=apply_patch; $F' 'eval apply_patch' 'bash -c "apply_patch"' "sh -c 'cat p | apply_patch'" \
  "apply_pa''tch" "xargs${nl}apply_patch" "apply_patch\\${nl}" '"apply_patch"'; do
  refused "$c" "spelling"
done
refused "cat <<'EOF' | x${nl}*** Begin Patch${nl}*** Add File: docs/a.md${nl}+x${nl}*** End Patch${nl}EOF" "patch text with a file marker"

# --- gaps found by the tester pass
refused 'codex --codex-run-as-apply-patch "*** Begin Pat"' "codex --codex-run-as-apply-patch is apply_patch"
refused 'codex --codex-run-as-apply-patch' "codex --codex-run-as-apply-patch without an argument"
refused 'codex-linux-sandbox --codex-run-as-apply-patch' "another codex binary name"
refused 'find . -name p -exec apply_patch {} \;' "find -exec apply_patch"
refused "\$'apply_patch'" "ANSI-C quoted command word"
refused 'echo apply_patch | sh' "command text piped to a shell"
refused 'sh <<< apply_patch' "command text as a here-string to a shell"
refused "env -S 'apply_patch'" "env -S"
refused 'watch apply_patch' "watch"
refused 'parallel apply_patch' "parallel"
refused 'script -c apply_patch /dev/null' "script -c"
refused 'exec -a apply_patch codex x' "exec -a <spelling>"
refused 'flock /tmp/l apply_patch' "flock"
refused "flock /tmp/l -c 'apply_patch'" "flock -c"
refused 'busybox apply_patch' "busybox"
refused "su -c 'apply_patch' root" "su -c"
refused 'ssh host apply_patch' "ssh host"
refused 'ssh -p 22 host "cd d && apply_patch"' "ssh with an option and a command line"
refused 'find . -execdir apply_patch {} +' "find -execdir"
refused 'xargs -I {} sudo apply_patch {}' "xargs with an option value and a wrapper"
refused 'APPLY_PATCH' "upper case"
refused 'ApplyPatch' "camel case"
refused './Apply-Patch' "mixed case with a path"
refused 'echo applypatch | bash' "echo into bash"
refused "printf '%s' apply_patch | sh -s" "printf into sh -s"
refused 'sh <<< "apply_patch <<EOF"' "here-string with a command line"
refused 'alias ap=ApplyPatch' "alias to a case variant"

# --- the verifier and security passes: wrappers and options a wrapper list missed
refused 'env -Sapply_patch' "env -S glued"
refused 'env --split-string=apply_patch' "env --split-string="
refused 'env -S "A=1 apply_patch -x"' "env -S with a command line"
refused 'xargs --max-args 1 apply_patch' "xargs long option with a value"
refused 'parallel --jobs 2 apply_patch' "parallel long option with a value"
refused 'bash -O extglob -c apply_patch' "bash -O x -c"
refused 'bash --rcfile r -c apply_patch' "bash --rcfile"
refused 'bash -c -- apply_patch' "bash -c --"
refused 'function f { apply_patch; }; f' "function body"
refused 'f() { apply_patch; }; f' "function body, ()"
refused 'strace -f apply_patch' "strace"
refused 'chroot / apply_patch' "chroot"
refused "tmux new-session 'apply_patch'" "tmux new-session"
refused 'tmux send-keys apply_patch Enter' "tmux send-keys"
refused 'env -C Proj apply_patch' "env -C"
refused "c''d Proj && apply_patch" "quoted cd"
refused 'cd Proj; apply_patch' "cd then apply_patch"
refused 'setsid apply_patch' "setsid"
refused 'stdbuf -o0 apply_patch' "stdbuf"
refused 'timeout 5 apply_patch' "timeout"
refused 'cat "$(apply_patch)"' "substitution in double quotes"
refused 'grep x $(apply_patch)' "substitution after a reader"
refused 'grep x `apply_patch`' "backticks after a reader"
refused 'bash <(echo apply_patch)' "process substitution of a visible command"
refused 'grep -rn apply_patch src | sh' "a reader piped into sh"
refused 'grep -rn apply_patch src | bash' "a reader piped into bash"
refused 'cat apply_patch | zsh' "a reader piped into zsh"
refused 'git log -S apply_patch | source /dev/stdin' "a reader piped into source"
refused 'git log --grep=apply_patch; make' "a reader and another command"
refused 'find . -name apply_patch -exec sh -c y {} \;' "find -exec"
refused 'find . -name apply_patch -execdir x {} +' "find -execdir"
refused 'find . -name apply_patch -ok x {} \;' "find -ok"
refused 'find . -name apply_patch -delete' "find -delete"
refused 'sed -n p apply_patch' "sed is not a reader"
refused "sed --in-place s/a/b/ apply_patch" "sed in place"
refused 'rg --pre apply_patch x y' "rg --pre"
refused 'git -c core.pager=apply_patch log' "git -c"
refused 'git log --output=x apply_patch' "git log --output"
refused 'git push apply_patch' "git push"
refused 'man -P apply_patch ls' "man -P"
refused 'ls apply_patch && make' "ls then make"
refused 'FOO=apply_patch make' "VAR= then make (the VAR= rule; documented)"
refused 'cd apply_patch && ls' "cd is not a reader"
refused 'touch apply_patch' "touch is not a reader"

# --- an assignment whose value holds the spelling as a token always refuses (the reader exception never applies)
refused "LESSOPEN='|apply_patch %s' less \"\$(cat p.txt)\"" "LESSOPEN pipe"
refused "LESSOPEN='||apply_patch %s' cat f" "LESSOPEN double pipe before a reader"
refused 'MANPAGER=apply_patch man -l f' "MANPAGER"
refused 'PAGER=apply_patch man ls' "PAGER"
refused 'GIT_EXTERNAL_DIFF=apply_patch git diff' "GIT_EXTERNAL_DIFF before a reader"
refused 'GIT_EXTERNAL_DIFF=/usr/bin/apply_patch git diff' "GIT_EXTERNAL_DIFF with a path"
refused "MANPAGER='sh -c apply_patch' man ls" "a value with blanks"
refused "X='echo; apply_patch'; eval \"\$X\"" "standalone assignment with ;"
refused "X='cat p | apply_patch'; sh -c \"\$X\"" "standalone assignment with a pipe"
refused "export X='echo; apply_patch'" "export of a command line"
refused 'X=apply_patch' "bare standalone assignment"
refused 'X+=apply_patch' "append assignment"
refused 'PAGER=apply_patch cat f' "prefix before cat"

# --- caps fail closed: a full re-lex queue or a dropped long word with the spelling in the raw text refuses
q51="$(LC_ALL=C awk 'BEGIN { for (i = 0; i < 51; i++) printf "bash -c '"'"'ls; ls'"'"'; " }')"
q49="$(LC_ALL=C awk 'BEGIN { for (i = 0; i < 49; i++) printf "bash -c '"'"'ls; ls'"'"'; " }')"
refused "${q51}bash -c 'ls;apply_patch'" "51 shells then the spelling"
refused "${q49}bash -c 'ls;apply_patch'" "49 shells then the spelling"
passes "${q51}bash -c 'ls;ls'" "51 shells without the spelling"
pad="$(LC_ALL=C awk 'BEGIN { for (i = 0; i < 5000; i++) printf "x" }')"
refused "bash -c 'ls; $pad; apply_patch'" "over-long bash -c"
refused "ssh h '$pad; apply_patch'" "over-long ssh command"
passes "bash -c 'ls; $pad; ls'" "over-long bash -c without the spelling"
passes "ssh h '$pad; ls'" "over-long ssh without the spelling"
# the same cap on a word that grows from many small pieces (quote pairs), not from one long slice
pieces="$(LC_ALL=C awk 'BEGIN { for (i = 0; i < 2100; i++) printf "ab" }' | sed "s/ab/'a'b/g")"
refused "bash -c \"ls; $pieces; apply_patch\"" "over-long word of small pieces in a bash -c"
refused "ssh h $pieces\\;apply_patch" "over-long unquoted word of small pieces, then an escaped ;"
passes "ssh h $pieces\\;ls" "over-long word of small pieces without the spelling"


# --- every input of the seven review passes stays refused
for c in 'bash -c '"'ap\"\"ply_patch'" "sh -c 'a\\pply_patch'" 'sh -c "ap'"''"'ply_patch"' "bash -c '\$\"apply_patch\"'" "eval 'ap\"\"ply_patch'" \
  "env bash -c 'a\\pply_patch'" "nohup sh -c 'ap\"\"ply_patch'" "timeout 5 bash -c 'ap\"\"ply_patch'" "echo x | xargs sh -c 'ap\"\"ply_patch'" \
  "find . -exec sh -c 'ap\"\"ply_patch' \;" "time eval 'ap\"\"ply_patch'" \
  "LESSOPEN='|ap\"\"ply_patch %s' less f.txt" "LESSOPEN='|a\\pply_patch %s' less f" "MANPAGER='ap\"\"ply_patch' man ls" \
  "env MANPAGER='ap\"\"ply_patch' man ls" "export MANPAGER=\"ap''ply_patch\"; man ls" "X='ap\"\"ply_patch'; eval \"\$X\"" \
  "git -c alias.x='!ap\"\"ply_patch' x" "git -c alias.x='!apply_patch' x" 'git -c "alias.x=!apply_patch" x' "LESSOPEN='|-apply_patch %s' less f" \
  "git config alias.ap '!apply_patch'" \
  "echo \$'a\\'b'; apply_patch; echo \$'c'" "\$'\\x61pply_patch'" "\$'apply\\x5fpatch' x" "echo \$'\\x61pply_patch' | sh" "\$'\\141pply_patch'" "\$'\\u0061pply_patch'" \
  'echo `echo apply_patch`' 'echo `printf apply_patch` x' 'echo `basename /x/apply_patch`' 'echo `which apply_patch`' 'echo `command -v apply_patch`' \
  'echo `cat <<< apply_patch`' 'PAGER=`echo apply_patch` man ls' 'PAGER=$(echo apply_patch) man ls' \
  'printf -v MANPAGER apply_patch; man ls' 'echo apply_patch > s.sh' "less '+!apply_patch' f.txt" \
  "echo \"\$(cat <<\"EOF\"${nl}a${nl}EOF${nl})\"; apply_patch" "x=\"\$(cat <<\"EOF\"${nl}a${nl}EOF${nl})\"${nl}apply_patch" \
  "cat <<EOF${nl}\$(apply_patch)${nl}EOF" "cat <<EOF${nl}\`apply_patch\`${nl}EOF" "bash <<EOF${nl}apply_patch${nl}EOF"; do
  refused "$c" "review input"
done
refused "${q51}bash -c \"x; apply_pa''tch\"" "51 shells, then a quote in the name"
refused "${q51}bash -c \"x; a\\pply_patch\"" "51 shells, then a backslash in the name"
refused "${q51}bash -c \"x; \\\"apply\\\"_patch\"" "51 shells, then a quoted half"
refused "bash -c \"x; $pad; apply_pa''tch\"" "a 5000-byte word, then a quote in the name"
for c in 'git log -Sapply_patch' 'git log -Gapply_patch' 'rg -eapply_patch src' 'grep -rneapply_patch .' \
  'git log --grep=a apply_patch | sh' 'git log --pretty=x; apply_patch' 'git commit -m x --no-verify --amend -c apply_patch' \
  'git commit -m x -S apply_patch' 'cat apply_patch | tee x' 'grep apply_patch f | xargs wc -l' 'grep apply_patch f | sed p' 'sort apply_patch' \
  'grep -rn apply_patch . || true' 'grep apply_patch b | | cat' 'FOO=1 grep apply_patch f' \
  'rg -z apply_patch f' 'rg -nz apply_patch f' 'rg --search-zip apply_patch f' 'rg --pre-glob=x apply_patch f' 'find . -fprint x -name apply_patch' \
  'find . -name apply_patch -okdir x {} +' 'find . -name apply_patch -fls x' 'git diff -p apply_patch' 'git -C d log apply_patch' 'git log --paginate apply_patch' \
  'grep apply_patch f | sort --compress-program=x' 'grep apply_patch f | sort --compr=x' 'cat apply_patch | tr a b | python3' 'echo apply_patch | tee f' 'xargs -a f apply_patch' \
  'cat !apply_patch' "grep \"apply_patch\" f # c; d" 'grep apply_patch f &' "git commit -m 'x' -- apply_patch" "cat \$'a' apply_patch"; do
  refused "$c" "simple form broken"
done

# --- tester pass 6: unquoted $VAR is word-split by the shell, so an option can hide inside a word that does not start with "-"
# (git grep $IFS--open-files-in-pager=apply_patch hi really starts apply_patch as the pager)
for c in 'git grep $IFS--open-files-in-pager=apply_patch hi' 'git grep -n $IFS--open-files-in-pager=apply_patch hi' \
  'git log --grep=apply_patch $IFS--output=o.txt' 'rg apply_patch$IFS--pre=apply_patch f' 'rg $IFS--pre=apply_patch apply_patch f' \
  'find . -name apply_patch$IFS-delete' 'grep apply_patch f | sort$IFS--compress-program=x' 'git log --grep=apply_patch$IFS--ext-diff' \
  'git grep -e apply_patch$IFS-Oapply_patch'; do
  refused "$c" "word splitting hides an option"
done
# conservative refusals worth pinning (a quote or case the tokenizer does not read)
for c in 'GREP apply_patch f' 'Git log --grep=apply_patch' \
  'rg -e apply_patch --pre-glob x' 'grep --exclude=apply_patch f' "grep apply_patch f${nl}ls" "grep apply_patch f$(printf '\r')" \
  "grep x f$(printf '\r')apply_patch" "grep apply_patch f |$(printf '\r')sort"; do
  refused "$c" "conservative refusal"
done
# tabs and runs of spaces between words are the same simple form; other pinned simple forms
for c in "grep$(printf '\t')-rn$(printf '\t')apply_patch$(printf '\t')." 'grep    -rn    apply_patch    .' 'git log --grep=apply_patch --format=%H' \
  'git diff --no-ext-diff apply_patch.md' 'git show HEAD:apply_patch.md' 'rg -e apply_patch f' 'find . -name apply_patch.rs -print' \
  'head -n 5 apply_patch.md | wc -l' 'git log -- apply_patch'; do
  passes "$c" "pinned simple form"
done

# --- pass twins: a hit in the simple form passes
for c in 'grep -rn apply_patch .' 'grep -rn apply_patch . | sort | uniq' 'rg apply_patch | cut -d: -f1 | sort -u' 'rg -e apply_patch src' 'git log --grep=apply_patch' \
  'git log -S apply_patch' 'git commit -m "Adds apply_patch guard"' 'cat docs/eval-apply_patch.md' 'ls apply_patch_notes.md' 'find . -name apply_patch.rs' \
  'git grep -n apply_patch' 'wc -l apply_patch.md' "grep -c apply_patch f | tr -d ' '" 'git log --author=apply_patch' 'git log --committer=apply_patch' \
  'git log -G apply_patch' 'git grep -e apply_patch' 'rg --regexp=apply_patch src' 'rg -g apply_patch src' 'rg --glob=apply_patch src' 'grep -e apply_patch f' \
  'grep --regexp=apply_patch f' 'find . -iname apply_patch' 'find . -path src/apply_patch' 'egrep apply_patch f' 'fgrep apply_patch f' 'git show apply_patch' \
  'git diff apply_patch' 'git status apply_patch' 'git blame apply_patch' "git commit -am 'alias for apply_patch'" 'git commit --message="uses apply_patch" --amend' \
  'git commit -m x -s --no-edit apply_patch' 'cat apply_patch' 'head apply_patch' 'tail -n 3 apply_patch' 'ls apply_patch' 'find . -name apply_patch -print' \
  'grep -l apply_patch . | head' 'grep -rn apply_patch src | wc -l' 'git log --grep=apply_patch | grep x | sort | uniq' "rg 'apply_patch' tests" \
  'git commit -m "x" apply_patch' 'cat apply_patch_notes.md' 'ls apply_patch ~/x*' 'ls apply-patch.rs' 'cat docs/applypatch.md'; do
  passes "$c" "simple-form twin"
done
# a hit is not needed for a pass
for c in 'ls -la' 'git log --oneline' 'cat src/a.swift' 'make' 'for f in *.md; do echo "$f"; done' 'cd x && ls' "echo '*** Begin Patch'" "grep -n 'Begin Patch' f" \
  'git apply x.patch' 'patch -p1 < x.diff' 'echo hello > f' 'sed -n p f'; do
  passes "$c" "no hit"
done
refused "grep x <<EOF${nl}*** Begin Patch${nl}*** Add File: docs/a.md${nl}EOF" "a patch text in a heredoc is a hit and not simple"
passes "git commit -m 'x *** Begin Patch *** Add File: a'" "marker text in a simple commit message"

# --- engineer pass 7: quoted text is opaque for the structure checks; globs that spell the name; git option abbreviations
for c in "rg -n 'apply_patch|applypatch' ." "grep -E 'apply_patch|applypatch' f" "grep -n 'apply_patch(' f" \
  'git commit -m "corecrew 0.8.0 (apply_patch): x"' 'git commit -m "apply_patch; hooks"' "rg --glob '!docs' apply_patch" \
  'grep -rn "apply_patch|applypatch" .' "git commit -m 'a & b > c; apply_patch' -s" "git commit -m \"line one${nl}apply_patch line two\"" \
  'git log --oneline --grep=apply_patch' 'git log --oneline -- apply_patch' 'git log --oneline apply_patch' "git log --grep='apply_patch' --format=%H" \
  'git commit -m "fix --output handling for apply_patch"' 'grep apply_patch *.md' 'grep -rn apply_patch src/*.sh' 'ls apply_patch_notes.m?' "grep -e 'apply_patch' -- 'a b'"; do
  passes "$c" "opaque quoted text twin"
done
for c in "grep 'a;b' apply_patch.md" 'grep "x|y" apply_patch.md' "grep -e 'apply_patch|x' f" "grep apply_patch f '|' sh"; do
  passes "$c" "opaque quoted text twin (was a conservative refusal)"
done
for c in 'grep "apply_patch$(x)" f' 'grep "a\|apply_patch" f' "git commit -m \"\$(cat <<EOF${nl}apply_patch${nl}EOF${nl})\"" 'grep "apply_patch`x`" f' \
  "grep 'a' ; apply_patch" "grep \"it's\" 'x' \"\$x\" apply_patch" 'grep \"x ; apply_patch' "grep \\' ; apply_patch \\' f" \
  "rg '--pre=apply_patch' x" "rg --'pre'=apply_patch x" "rg ''--pre=apply_patch x" "rg '-'-pre=apply_patch x" "git log '--output=o' --grep=apply_patch" \
  "git log -x'apply_patch' --grep=a" "git commit -m x '-p' apply_patch" "git \"log\" apply_patch" "'grep' apply_patch f" \
  'grep -e "apply_patch" f "$HOME"' "grep apply_patch \"a${nl}b\" ${nl}ls" ; do
  refused "$c" "opaque quoted text: still refused"
done
# unquoted globs that can spell the name
for c in '../bin/apply_pat?h x' '../bin/apply_pat[c]h x' '../bin/appl*_patch x' './a*ly-patch' 'bin/applyp?tch' 'x/APPLY_PAT?H' '../bin/apply[_-]patch' \
  '/a/b/apply_pat[!x]h' '/a/b/apply_pat[^x]h' 'cd d && ../bin/a*patch x' '../b/appl?_patch' 'cat f | ../bin/ap*tch' '../b/*patch' '../b/ap??y?p?t?h' '../b/appl[y]p*'; do
  refused "$c" "glob spells the name"
done
# quoted text glued to a glob character (found by the tester pass): best effort, a documented limit
for c in "./app'l'?_patch x" './app"l"?_patch x' "./app['l']y_patch x" './ap["p"]ly_patch x' "./app[!'x']y_patch x" './app[a-"m"]y_patch x' \
  "./app['l'x]y_patch x" "cd d && ./ap'p'l*_patch x"; do
  passes "$c" "LIMIT quoted part glued to a glob"
done
for c in './apply_p[[:alpha:]]tch x' './apply[[:punct:]]patch x' './apply_p[^b-z]tch x'; do
  refused "$c" "glob class spells the name"
done
for c in "ls ap'pl'?_data" 'ls "a"*.md' "ls 'ap?ly_patch'"; do
  passes "$c" "quoted glued glob, no spelling of the name"
done
# quotes next to a hit: quoted placeholders, unterminated and escaped quotes, quoted first word, $ in and out of quotes
for c in "grep 'apply_patch\$' f" "grep -e 'apply_patch\$' f" "grep x'y'--pre=apply_patch f" "grep \"a'b\" apply_patch f" "grep 'a\"b' apply_patch f" "rg -e'x' apply_patch f"; do
  passes "$c" "quote twin"
done
for c in "grep 'apply_patch f" 'grep "apply_patch f' 'rg apply_patch"$x"' "rg 'a'\$'b' apply_patch" "'grep' apply_patch f" '"rg" -e apply_patch' \
  "grep \\'apply_patch f" "ls appl[\\\"y]_patch" 'grep "apply_patch$" f' "grep 'apply_patch'\$ f" "rg ''--pre=apply_patch f" "rg --p're'=apply_patch f"; do
  refused "$c" "LIMIT quote form outside the simple one"
done
for c in 'grep apply_patch *.md' 'grep -rn apply_patch src/*.sh' 'ls apply_patch ~/x*' 'cd x && ls *.md' 'for f in src/*.sh; do echo "$f"; done' \
  'ls docs/ap?.md' 'cd x && ls [c-d]*' 'grep -n foo [a-z]*.txt'; do
  passes "$c" "glob does not spell the name"
done
# LIMIT: names built at run time are not read
passes 'x=apply; ../bin/${x}_patch' "LIMIT: a variable in the name"
passes '../bin/apply_$(echo patch) x' "LIMIT: command substitution in the name"
passes '../bin/{apply_,x}patch' "LIMIT: brace expansion"
# git option abbreviations that run a program or write a file; --oneline is not one of them
for c in 'git log --o=x --grep=apply_patch' 'git log --out=x --grep=apply_patch' 'git log --outp=x --grep=apply_patch' 'git log --op=x --grep=apply_patch' \
  'git grep --ope=apply_patch hi' 'git grep --open-files-in-pager=apply_patch hi' 'git log --output-indicator-new=x --grep=apply_patch' \
  'git log --ou --grep=apply_patch' 'git log --pag=x --grep=apply_patch' 'git log --ext-diff --grep=apply_patch' 'git log --o --grep=apply_patch' \
  'git grep --open-files-in-pager --grep=apply_patch' 'git log --pager=x apply_patch'; do
  refused "$c" "git abbreviation"
done

# --- a wildcard argument is no command: everyday glob commands with && ; | or a redirect pass (they were refused when
# any glob that could match the name counted, wherever it stood); a heredoc body is data, its * is no command word
for c in 'wc -l a/* b/* 2>/dev/null | tail -1' 'cd x && ls scripts/* && cat .claude-plugin/marketplace.json' 'rm -rf dist/* && npm run build' \
  'cp assets/* public/ 2>/dev/null' 'chmod +x bin/* && ls' 'du -sh * | sort -h > sizes.txt' 'tar czf out.tgz * ; ls' \
  'for f in *; do echo "$f"; done > list.txt' 'git add src/* && git commit -m x' 'npm test && ls dist/*' 'cp [a-z]* out/; ls' \
  'ls src/* >&2' 'ls -d */ 2>&1 | head' 'echo x >| out.txt *' \
  "cat > f.js <<'EOF'${nl}const y = a * b; // *${nl}* x${nl}EOF${nl}node f.js" "cat <<-EOF > f.txt${nl}	* item${nl}	EOF${nl}ls" \
  "cat > a.md <<EOF${nl}it's * here; * x${nl}EOF${nl}ls" "x=\$(cat <<'EOF'${nl}* a${nl}EOF${nl}); echo \"\$x\""; do
  passes "$c" "glob argument or heredoc body"
done
# a heredoc started inside "$(...)" (the usual commit and PR body idiom), after a quoted apostrophe, or after a quote that
# spans lines is a heredoc too; a case pattern and arithmetic are no command words
for c in "git commit -m \"\$(cat <<'EOF'${nl}Fix things${nl}${nl}* bullet one${nl}* bullet two${nl}EOF${nl})\"" \
  "gh pr create --title x --body \"\$(cat <<'EOF'${nl}## Summary${nl}* item${nl}EOF${nl})\"" "echo \"it's\" <<EOF${nl}* item${nl}EOF" \
  "echo 'a \"b' <<EOF${nl}* item${nl}EOF" "echo \"a${nl}b\" && cat <<EOF${nl}* x${nl}EOF" "x=\`cat <<EOF${nl}* a${nl}EOF${nl}\`" \
  "echo \"\$(echo \")\") \$(cat <<'E'${nl}* a${nl}E${nl})\"" "cat <<E\\OF${nl}* a${nl}EOF" "cat <<E\"O\"F${nl}* a${nl}EOF" \
  "case \"\$a\" in${nl}  *.md) echo md ;;${nl}  *) echo other ;;${nl}esac" 'case "$1" in start) x;; *) y;; esac' \
  'case $f in (*) ls;; esac' 'case $f in a|*) ls;; esac' "case \$f in${nl}*)${nl}  ls ;;${nl}esac" \
  'echo $(( $(wc -l < f) * 2 ))' 'x=$(( (a+b) * 2 ))' 'echo "$(( 3 * 4 ))"' 'echo $((1<<2)) && ls *'; do
  passes "$c" "heredoc in a quoted substitution, case pattern or arithmetic"
done
# what only looks like a heredoc start, a case, or arithmetic leaves the next words command words
for c in "echo \"<<EOF\"${nl}* x" "echo '<<EOF'${nl}* x" "echo \\<<EOF${nl}./a* x" "# <<EOF${nl}./a* x" "echo x # it's <<EOF${nl}* x" \
  "echo \"it's${nl}<<EOF\"${nl}* x" 'case x in *) ;; esac; * y' 'case x in a) * y;; esac' 'case x in *) ./a* | sh;; esac' \
  'echo $(( $(./a* x) + 1 ))' 'echo $((./a* x) )' 'x=$(( 2 * 3 )); * y' "echo \$((1<<2))${nl}* x"; do
  refused "$c" "a false heredoc, case or arithmetic"
done
# command positions: a backtick, find -exec, a wrapper's numeric value, a wrapper named by path, coproc
for c in 'echo `./a* x`' 'timeout 5 ./a* x' 'timeout 1.5s ./a* x' 'nice -n 5 ./a* x' 'xargs -n 1 ./a*' 'find . -exec ./a* {} \;' \
  'find . -execdir ./a* {} +' 'find . -ok ./a* {} \;' '/usr/bin/env ./a* x' 'coproc ./a* x'; do
  refused "$c" "a glob in a command position"
done
passes 'echo `ls` * && ls' "a wildcard after a closing backtick is an argument"
passes 'timeout 5 ls dist/*' "a wildcard argument after a wrapper's numeric value"
passes 'find . -exec ls {} \; -name *' "a wildcard argument after find -exec"
# a glob still counts as a command word (first word, after ; && | ( or a newline, after a reserved word, an assignment or a
# wrapper) and, anywhere, when its last part keeps 4 or more literal characters and can match the name
for c in '* x' 'ls; * x' 'ls && ./a* x' 'true | ./ap*' 'if true; then ./a*; fi' '( ./a* )' 'sudo ./a* x' 'xargs -0 ./a*' 'X=1 ./a* x' \
  "ls${nl}./a* x" 'ls 2>/dev/null; ./a*' 'sudo ../bin/apply_pat?h x > /dev/null' 'ls ../bin/appl*_patch; true' 'rm -f ../b/*patch && ls' \
  "bash <<EOF${nl}../bin/apply_pat?h x${nl}EOF" "cat <<EOF${nl}x${nl}EOF${nl}./a* x" "cat <<'A' <<'B'${nl}*${nl}A${nl}*${nl}B${nl}* x"; do
  refused "$c" "glob as a command word, or spelling the name"
done
# the refusal names what matched (SHELL_PATCH_HIT; the hook message shows it)
hit_is() { SHELL_PATCH_HIT=""; shell_patch_refused "$1"; assert_eq "$SHELL_PATCH_HIT" "$2" "$3"; }
hit_is 'cd d && ../bin/apply_pat?h x' '../bin/apply_pat?h' "the hit names the glob word"
hit_is 'ls; * x' '*' "the hit names a bare wildcard"
hit_is 'echo x | Apply_Patch' 'Apply_Patch' "the hit names the spelling as written"
hit_is "apply_pa''tch x" 'apply_patch' "the hit names the spelling with quotes removed"
hit_is "cat <<'E' | x${nl}*** Begin Patch${nl}*** Add File: a${nl}E" '*** Begin Patch' "the hit names a patch text"
hit_is "\$'\\x61pply' x" "\$'\\...'" "the hit names an escape"
# the hit is cut at 80 bytes, never inside a UTF-8 character
e2="$(printf '\303\251')"; long="x"; for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50; do long="$long$e2"; done
want="x"; for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39; do want="$want$e2"; done
hit_is "$long/a* x" "$want" "a long hit is cut before a split UTF-8 character"

# --- documented over-blocking (LIMIT): a hit outside the simple form is refused
for c in 'cd x && grep apply_patch .' 'for f in *.md; do grep -q apply_patch "$f"; done' 'gh pr create --body "apply_patch"' 'echo apply_patch' 'grep apply_patch f > out.txt' \
  'command -v apply_patch' 'man apply_patch' '/usr/bin/grep apply_patch f' 'which apply_patch' 'grep -n apply_patch $FILE' 'less apply_patch' 'ag apply_patch' \
  'touch apply_patch.txt' 'git add apply_patch_notes.md' 'make apply-patch.rs' 'FOO=apply_patch_x make' 'X=apply_patch.md' 'sed -n 1,5p apply_patch_notes.md' \
  'test -f apply_patch' 'cat apply_patch 2>/dev/null' 'grep x <<< apply_patch' 'git log -Sapply_patch' 'git commit apply_patch --no-verify'; do
  refused "$c" "LIMIT: over-blocking"
done
refused 'echo $(ls) * && ls' "LIMIT: over-blocking, a bare wildcard right after )"
refused 'for ((i = 0; i < 3; i++)); do (( (i+1) * 2 )); done' "LIMIT: over-blocking, arithmetic without \$"

# --- documented limits (LIMIT): no hit, no refusal
passes 'a=apply; ${a}_patch' "LIMIT: a computed name"
passes 'git ap' "LIMIT: an alias set by an earlier command (the earlier command is refused)"
passes 'sh s.sh' "LIMIT: a script"
passes 'python3 run.py' "LIMIT: an interpreter"
passes 'x=apply; y=patch; "$x"_"$y"' "LIMIT: a computed name, two variables"
passes "\$'apply'\$'_patch'" "LIMIT: \$'...' splitting"
passes "../bin/'apply_pat'?h" "LIMIT: a quoted part glued to a glob"
passes "shopt -s extglob${nl}../bin/apply_pat@(c)h" "LIMIT: extglob"
passes 'sudo -u x ./a*' "LIMIT: a glob after a wrapper option that takes a non-numeric value"
passes 'exec -a name ./a* x' "LIMIT: a glob after exec -a name"
passes "cat <<EOF | sh${nl}./a* x${nl}EOF" "LIMIT: a short glob in a heredoc body fed to a shell"

# --- a 1 MB command stays well inside the 15 s hook timeout (grep, tr and one awk pass: linear)
timed() { # timed <label> <want: 0 refused | 1 pass> <command>
  local t0=$SECONDS rc dt
  shell_patch_refused "$3"; rc=$?; dt=$((SECONDS - t0))
  [ "$dt" -lt 10 ] && [ "$rc" -eq "$2" ] && pass || fail "$1: took $dt s, rc=$rc (want $2)"
}
timed "1 MB of non-hits" 1 "$(LC_ALL=C awk 'BEGIN { for (i = 0; i < 40000; i++) printf "make apply_pat_x -o a/b/c; "; print "ls" }')"
timed "1 MB of readers in a pipe" 1 "$(LC_ALL=C awk 'BEGIN { printf "grep apply_patch src"; for (i = 0; i < 40000; i++) printf " | sort"; print "" }')"
timed "1 MB of words in a simple form" 1 "$(LC_ALL=C awk 'BEGIN { printf "grep apply_patch "; for (i = 0; i < 100000; i++) printf "a%d ", i; print "" }')"
timed "1 MB of words, then a pipe into apply_patch" 0 "$(LC_ALL=C awk 'BEGIN { printf "echo "; for (i = 0; i < 100000; i++) printf "a%d ", i; print "| apply_patch" }')"
timed "1 MB of 4000-byte words, then apply_patch" 0 "$(LC_ALL=C awk 'BEGIN { for (i = 0; i < 245; i++) { printf "bash -c '"'"'"; for (j = 0; j < 4000; j++) printf "x"; printf "'"'"'; " } print "apply_patch" }')"
timed "1 MB of shells, then bash -c apply_patch" 0 "$(LC_ALL=C awk 'BEGIN { for (i = 0; i < 40000; i++) printf "bash -c '"'"'ls; ls'"'"'; "; print "bash -c apply_patch" }')"
timed "1 MB of shells without a hit" 1 "$(LC_ALL=C awk 'BEGIN { for (i = 0; i < 40000; i++) printf "bash -c '"'"'ls; ls'"'"'; "; print "bash -c ls" }')"
timed "1 MB of quotes, then apply_patch" 0 "$(LC_ALL=C awk 'BEGIN { for (i = 0; i < 300000; i++) printf "\"\"x"; print "; apply_patch" }')"
timed "1 MB of \$' escapes" 0 "$(LC_ALL=C awk 'BEGIN { for (i = 0; i < 100000; i++) printf "$'"'"'a'"'"' "; print "$'"'"'\\x61'"'"'" }')"

# --- find's program-running primaries with the terminator in QUOTES. Quoted text is opaque to the structure checks,
# so `';'` leaves no ; for the "no list" check: only the find rule refuses these (a copy of the rule without it stayed
# green). test_shell_patch_exec.sh shows that such a find really starts apply_patch.
for c in "find . -exec apply_patch ';'" "find . -ok apply_patch ';'" "find . -execdir apply_patch ';'" "find . -okdir apply_patch ';'" \
         "find . -name f -exec apply_patch ';'" "find f -exec apply_patch \"+\""; do
  refused "$c" "find with a quoted terminator"
done
# twins that must pass: the same find reading only
passes "find . -name apply_patch -print" "find -name apply_patch"
passes "find . -iname 'apply_patch*'" "find -iname quoted glob"

# --- the rule needs no file of the plugin
SELF="$SANDBOX/nowhere"
refused 'apply_patch' "no scripts dir: bare word"
passes 'grep -rn apply_patch src' "no scripts dir: simple form"
passes 'ls' "no scripts dir: ls"
# shellcheck disable=SC2034  # SELF is read by the functions of the sourced lib.sh
SELF="$PLUGIN"
finish
