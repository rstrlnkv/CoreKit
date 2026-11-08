# shell-patch.sh — the guards' check for a Codex patch handed to the shell. Sourced by hooks/guard-code.sh and
# hooks/guard-secrets.sh after lib.sh (it uses host and json_str from there); nothing else needs it.

# shell_patch_host <hook input JSON> — exit 0 when the shell-patch refusal applies: the host is Codex (host: the plugin
# lies under CODEX_HOME), or the input carries Codex's turn_id (a dev install whose path says nothing; Claude Code sends no
# turn_id). Claude Code has no apply_patch tool, so there a program of that name is the person's own and nothing is refused.
shell_patch_host() {
  [ "$(host)" = codex ] && return 0
  [ -n "$(json_str "${1:-}" turn_id)" ]
}

# shell_patch_refused <command> — exit 0 when a Bash command applies a patch through the shell, which no hook can
# judge (a path may be built by cd, quoting, $(...) or a variable); SHELL_PATCH_HIT is then what matched (the spelling as
# written, "*** Begin Patch", "$'\...'" or the glob word, at most 80 bytes). The hooks call it only when shell_patch_host
# says Codex. The rule reads no shell syntax (seven review passes in all,
# five of them against the tokenizer rule); it is a substring hit plus a narrow allowlist.
# BEST EFFORT, NOT A SECURITY BOUNDARY: it catches plain and accidental shell patches and many disguised ones; it cannot
# see a name the shell builds at run time. The apply_patch tool form is the checked path. Known ways past it: variables
# and ${...}; $(...) and backticks (also empty ones); brace expansion; $'...' / $"..." splitting ($'apply'$'_patch');
# a quoted part glued to a glob ('apply_pat'?h); extglob (shopt -s extglob, then apply_pat@(c)h); a glob that expands to
# an option-named file; IFS changes; scripts and interpreters; write_stdin.
# Hit (any letter case): the text, with every ' " \ and newline deleted, holds apply_patch, applypatch or apply-patch
# (that covers --codex-run-as-apply-patch); or "*** Begin Patch" is followed by an Add File, Update File, Delete File or
# Move to marker; or $' is followed by a \x, \u, \U or octal escape (an encoded name cannot be read); or an unquoted word
# holds ? * or [ and its part after the last / read as a glob can match one of the three spellings (../bin/apply_pat?h,
# ../bin/appl*_patch), and the word either is a command word (the first word, after ; & | ( ) an opening backtick or a
# newline, after a reserved word such as then/do/if/!/{/coproc, an assignment, find -exec/-execdir/-ok/-okdir, or a
# wrapper such as sudo/env/xargs/exec/timeout, also named by path, and its options and numeric values) or keeps 4 or more
# literal characters in that last part. So a wildcard argument (rm -rf dist/*, wc -l a/* 2>/dev/null, cp assets/* out/)
# is no hit, while ls; * x and sudo ../bin/apply_pat?h are. A redirect target is skipped. A case pattern (a word followed
# by ) or by | words and then )) is no command word while a case is open, and * ? [ inside $((...)) are arithmetic. A
# heredoc body is data: its words are never command words (cat > f.js <<'EOF' and git commit -m "$(cat <<'EOF' with a
# * in the body pass); the name and the patch markers are still found there (bash <<EOF / apply_patch / EOF is refused).
# A glob word in a heredoc body counts only when it keeps 4 or more literal characters and: it has a / (Markdown emphasis
# never has a path before it: ../bin/*pply_patch*, /x/*_patch count), or it is Markdown emphasis (* only at its two ends)
# whose text holds apply_ apply- or applyp (*apply_pat* counts; **Patch**, *apply* do not), or it is no emphasis and its
# literal part holds "apply" or it has a ? or [ or a * inside it (apply_pa*, ap?ly_patch, appl*_patch count; *patch*
# and *_patch do not).
# Heredoc starts are found by a quoting-state scan (a << inside quotes, after \ or in a # comment is none). Limits of the
# command-word reading: a bare wildcard in a heredoc body fed to a shell (cat <<EOF | sh / * / EOF); one after a wrapper
# option or argument that takes a non-numeric value (sudo -u x ./a*, exec -a name ./a*); a << inside (( )) without $,
# or a ) of a case pattern inside $(...), which the scan may misread. No hit: pass.
# A hit passes only in the simple form. Quoted text is opaque there: each single-quoted string and each double-quoted
# string without $, backtick or \ is replaced by one placeholder byte (\001; a string that starts with - keeps that -, so
# an option cannot hide in quotes), and then no $ ` \ quote, ; & newline < > ( ) { } ! may be left (so any $ outside single
# quotes makes the line non-simple); the first word is no assignment; the line split on | gives elements whose first word
# is a bare name; the first is a reader (grep egrep fgrep rg, git log|show|diff|grep|status|blame, git commit with only
# -m -a -am --message -s --amend --no-edit, cat head tail ls wc find), the others a filter (sort uniq cut tr nl wc head
# tail grep rg); an option word with a glued quote is only -e -S -G -m -g --regexp= --grep= --author= --committer=
# --message= --glob=; no word is an option that runs a program or writes a file (git -c -C -p --paginate -O, --pag*,
# --ext*, --output*, --open-files-in-pager*, and any --o... that abbreviates --output or --open-files-in-pager, but not
# --oneline; rg --pre* --hostname-bin* --search-zip -z; find -exec -execdir -ok -okdir -delete -fprint* -fls; sort --co*);
# and an option word that holds the spelling is one of -e --regexp= --grep= --author= --committer= -S -G -m --message=
# -g --glob= -name -iname -path -ipath with the value glued by =.
# Over-blocking by design (in Codex only): cd x && grep apply_patch ., a for loop, gh pr create --body "apply_patch",
# echo apply_patch, a redirect, command -v, man, /usr/bin/grep, grep apply_patch $FILE, and a glob argument that spells
# much of the name outside the simple form (ls ../bin/appl*_patch; true), and a bare wildcard right after a ) (echo $(ls) *)
# or after a ( in (( (i+1) * 2 )) without $.
# Limits (no hit, no refusal; pinned as LIMIT in tests/test_shell_patch.sh): a name built at run time (a variable:
# a=apply; ${a}_patch; $(...) or backticks, also empty; brace expansion; $'apply'$'_patch'; 'apply_pat'?h; extglob), a glob
# that expands to a file whose name is an option (-...), a leading-star glob with no / and no apply in a heredoc body fed
# to a shell (bash <<EOF / *ply_patch / EOF), IFS changes, a script or an interpreter that runs it, write_stdin. Plain bash 3.2 + BSD
# grep/sed/awk; linear in the text.
# shellcheck disable=SC2034  # SHELL_PATCH_HIT is read by the guards (their refusal message names it)
shell_patch_refused() {
  local q="'" flat plain hit="" out s one quote_re
  SHELL_PATCH_HIT=""
  one="$(printf '\001')"
  quote_re='s/'"'"'(-?)[^'"'"']*'"'"'|"(-?)[^"$`\]*"/'"$one"'\1\2/g'
  flat="$(printf '%s' "$1" | LC_ALL=C tr '\n\r' '  ')"
  plain="$(printf '%s' "$1" | LC_ALL=C tr -d '\047\042\134\012\015')"
  # s: the text with its quoted strings opaque (see above); newline and CR become \005
  s="$(printf '%s' "$1" | LC_ALL=C tr '\n\r' '\005\005' | LC_ALL=C sed -E "$quote_re")"
  hit="$(printf '%s\n' "$plain" | LC_ALL=C grep -oiE 'apply_patch|applypatch|apply-patch' | head -n 1)"
  [ -n "$hit" ] || { printf '%s\n' "$flat" | LC_ALL=C grep -qE '\*\*\* Begin Patch.*\*\*\* (Add File|Update File|Delete File|Move to):' && hit='*** Begin Patch'; }
  [ -n "$hit" ] || { printf '%s\n' "$flat" | LC_ALL=C grep -qE "\\\$$q.*\\\\([xuU]|[0-7])" && hit="\$'\\...'"; }
  if [ -z "$hit" ]; then
    # Heredoc bodies and arithmetic first, on the raw text, by a quoting-state scan that carries across lines: a stack of
    # S '...', D "...", P $(...) or (...), B `...`, A $((...)) and a ( inside A. A << outside S and D starts a heredoc
    # (<<< does not; \< and a # comment hide it), so "$(cat <<'EOF' is one. Each body line gets a leading \006 word (data,
    # no command words) and loses its quotes, backslashes, $ and backticks, so an apostrophe there cannot pair with a quote
    # outside. In A, * ? [ are operators and become blanks, unless A turns out to be $( (...) ) (a ) not followed by )).
    # Linear: the line is split into characters once (substr on a long line is not O(1) in every awk).
    out="$(printf '%s\n' "$1" | LC_ALL=C awk '
      END { print "\001done" }
      BEGIN { nq = 0; qi = 1; sp = 0; q1 = sprintf("%c", 39) }
      {
        line = $0
        if (qi <= nq) {
          cmp = line
          if (DASH[qi]) sub(/^\t+/, "", cmp)
          if (cmp == Q[qi]) { qi++; print line; next }
          gsub(/["\047`\\$]/, "", line); print "\006 " line; next
        }
        n = split(line, C, ""); nb = 0
        for (i = 1; i <= n; i++) {
          c = C[i]; t = sp ? ST[sp] : "U"
          if (t == "S") { if (c == q1) sp--; continue }
          if (c == "\\") { i++; continue }
          if (c == "$" && C[i + 1] == "(") {
            if (C[i + 2] == "(") { ST[++sp] = "A"; AS[sp] = nb; i += 2 } else { ST[++sp] = "P"; i++ }
            continue
          }
          if (c == "`") { if (t == "B") sp--; else ST[++sp] = "B"; continue }
          if (t == "D") { if (c == "\"") sp--; continue }
          if (c == q1) { ST[++sp] = "S"; continue }
          if (c == "\"") { ST[++sp] = "D"; continue }
          if (t == "A" || t == "a") {
            if (c == "(") ST[++sp] = "a"
            else if (c == ")") {
              if (t == "a") sp--
              else if (C[i + 1] == ")") { sp--; i++ }
              else { while (nb > AS[sp]) { C[BL[nb]] = BC[nb]; nb-- } ST[sp] = "P" }
            }
            else if (c == "*" || c == "?" || c == "[") { BL[++nb] = i; BC[nb] = c; C[i] = " " }
            continue
          }
          if (c == "(") { ST[++sp] = "P"; continue }
          if (c == ")") { if (t == "P") sp--; continue }
          if (c == "#" && (i == 1 || C[i - 1] ~ /[ \t;&|()]/)) break
          if (c != "<" || C[i + 1] != "<") continue
          if (C[i + 2] == "<") { i += 2; continue }
          j = i + 2; dash = 0; d = ""
          if (C[j] == "-") { dash = 1; j++ }
          while (C[j] == " " || C[j] == "\t") j++
          while (j <= n && length(d) < 1000) {
            c = C[j]
            if (c == q1 || c == "\"") { j++; while (j <= n && C[j] != c) d = d C[j++]; j++; continue }
            if (c == "\\") { d = d C[j + 1]; j += 2; continue }
            if (c ~ /[ \t;&|<>()]/) break
            d = d c; j++
          }
          if (d != "" && length(d) < 1000) { nq++; Q[nq] = d; DASH[nq] = dash }
          i = j - 1
        }
        # an A still open at the end of the line may yet turn out to be $( (...) ): keep this line as written
        open = 0; for (k = 1; k <= sp; k++) if (ST[k] == "A") { open = 1; AS[k] = 0 }
        if (nb == 0 || open) { print line; next }
        for (k = 1; k <= n; k++) printf "%s", C[k]
        print ""
      }' 2>/dev/null)"
    # the last line is the \001done the reader prints at its end: without it the reader failed, so the text is unknown
    case "$out" in *"$one"done) out="${out%"$one"done}" ;; *) out="" ;; esac
    [ -n "$out" ] && out="$(printf '%s' "$out" | LC_ALL=C tr '\n\r' '\005\005' | LC_ALL=C sed -E "$quote_re" | LC_ALL=C awk '
      # glob_re: the regex of a glob word; LIT counts its literal characters
      function glob_re(w,   re, i, j, c, L, cls) {
        re = "^"; L = length(w); LIT = 0
        for (i = 1; i <= L; i++) {
          c = substr(w, i, 1)
          if (c == "?") re = re "."
          else if (c == "*") re = re ".*"
          else if (c == "[") {
            j = i + 1
            if (substr(w, j, 1) == "!" || substr(w, j, 1) == "^") j++
            if (substr(w, j, 1) == "]") j++
            while (j <= L && substr(w, j, 1) != "]") j++
            if (j > L) { re = re "\\["; LIT++ }
            else {
              cls = substr(w, i, j - i + 1)
              if (substr(cls, 2, 1) == "!") cls = "[^" substr(cls, 3)
              re = re cls; i = j
            }
          }
          else if (c ~ /[.+(){}^$|\\]/) { re = re "\\" c; LIT++ }
          else { re = re c; LIT++ }
        }
        return re "$"
      }
      # pattern(i): W[i] is a case pattern: the next words are ) or | word | word ... ) (20 words at most)
      function pattern(i,   j, k) {
        j = i + 1
        for (k = 0; k < 20; k++) {
          while (j <= n && W[j] == "") j++
          if (W[j] == ")") return 1
          if (W[j] != "|") return 0
          j++; while (j <= n && W[j] == "") j++
          if (W[j] ~ /^[|;&()`\005\006\007]$/) return 0
          j++
        }
        return 0
      }
      # dataword(b, c): a glob word b (its last part, lower case, runs of * folded; c the whole word) in a heredoc body
      # may still spell the name: it has a / (emphasis never has a path before it), or it is Markdown emphasis (* only at
      # its two ends) whose text holds apply_ apply- or applyp, or it is no emphasis and has a ? or [ or a * inside it,
      # or its literal part holds apply
      function dataword(b, c,   l) {
        if (index(c, "/")) return 1
        if (b ~ /^\*[^*?[]+\*$/) return (b ~ /apply[-_p]/)
        if (b ~ /[?[]/ || b ~ /[^*]\*[^*]/) return 1
        l = b; gsub(/\*/, "", l)
        return index(l, "apply") > 0
      }
      BEGIN { N[1] = "apply_patch"; N[2] = "applypatch"; N[3] = "apply-patch"; hit = ""; bt = 0; incase = 0 }
      {
        line = $0
        gsub(/&?[0-9]*[<>]+[&|]?-?/, " \007 ", line)   # a redirect operator: the next word is its target
        gsub(/[|;&()`\005]/, " & ", line)               # a command separator is a word of its own
        n = split(line, W, /[ \t]+/)
        cmd = 1; skip = 0; data = 0; wrap = 0
        for (i = 1; i <= n && hit == ""; i++) {
          w = W[i]
          if (w == "") continue
          if (w == "\005") { cmd = 1; data = 0; skip = 0; wrap = 0; continue }
          if (w == "`") { bt = !bt; cmd = bt; skip = 0; wrap = 0; continue }   # an opening backtick starts a command
          if (w ~ /^[|;&()]$/) { cmd = !data; skip = 0; wrap = 0; continue }
          if (w == "\006") { data = 1; cmd = 0; continue }
          if (w == "\007") { skip = 1; continue }
          if (skip) { skip = 0; continue }
          c = w; gsub(/[\001"\047`$\\]/, "", c)
          if (!cmd && !data && c ~ /^-(exec|execdir|ok|okdir)$/) { cmd = 1; wrap = 0; continue }   # find runs the next word
          at = cmd
          if (cmd) {
            cb = c; sub(/.*\//, "", cb)
            if (c ~ /^[A-Za-z_][A-Za-z0-9_]*\+?=/ || c ~ /^(!|[{]|then|do|else|elif|if|while|until|time|coproc)$/ || (wrap && c ~ /^(-|[0-9]+([.][0-9]+)?[smhd]?$)/)) ;
            else if (cb ~ /^(exec|command|builtin|sudo|doas|env|nohup|xargs|nice|ionice|timeout|setsid|stdbuf|eval|watch|parallel|strace|ltrace|chroot|flock|busybox)$/) wrap = 1
            else {
              if (c == "case") incase++
              else if (c == "esac" && incase) incase--
              else if (incase && c ~ /[?*[]/ && pattern(i)) at = 0
              cmd = 0; wrap = 0
            }
          }
          if (c !~ /[?*[]/) continue
          m = split(c, P, "/"); b = P[m]
          if (b !~ /[?*[]/) continue
          gsub(/\*+/, "*", b)
          if (length(b) > 200) { hit = c; break }
          re = glob_re(tolower(b))
          for (k = 1; k <= 3; k++) if (N[k] ~ re && (at || (LIT >= 4 && (!data || dataword(tolower(b), c))))) hit = c
        }
      }
      END { if (hit == "") print "none"; else print "hit " hit }' 2>/dev/null)"
    case "$out" in none) ;; "hit "*) hit="${out#hit }" ;; *) hit="a command this check could not read" ;; esac
  fi
  [ -n "$hit" ] || return 1
  # at most 80 bytes; a UTF-8 character the cut would split is dropped
  SHELL_PATCH_HIT="$(printf '%s\n' "$hit" | LC_ALL=C awk '{ s = substr($0, 1, 80); if (length($0) > 80) sub(/[\300-\367][\200-\277]*$/, "", s); print s; exit }')"
  # the simple form: no construct that runs or hides a command (quoted text is already opaque in $s)
  printf '%s\n' "$s" | LC_ALL=C grep -q '[;&<>(){}!`$"\'"$q$(printf '\005')"']' && return 0
  out="$(printf '%s\n' "$s" | LC_ALL=C awk '
    BEGIN { ok = 1 }
    {
      n = split($0, E, "|")
      for (i = 1; i <= n && ok; i++) {
        m = split(E[i], W, " "); nm = W[1]
        if (m == 0 || nm ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || nm !~ /^[A-Za-z0-9._+-]+$/) { ok = 0; break }
        sub_ = W[2]; commit = 0
        if (i == 1) {
          if (nm == "git") {
            if (sub_ !~ /^(log|show|diff|grep|status|blame|commit)$/) { ok = 0; break }
            commit = (sub_ == "commit")
          } else if (nm !~ /^(grep|egrep|fgrep|rg|cat|head|tail|ls|wc|find)$/) { ok = 0; break }
        } else if (nm !~ /^(sort|uniq|cut|tr|nl|wc|head|tail|grep|rg)$/) { ok = 0; break }
        for (j = 2; j <= m; j++) {
          w = W[j]; b = w; sub(/^\001+/, "", b)
          if (substr(b, 1, 1) != "-") continue
          if (index(w, "\001") > 0) {
            p = w; sub(/\001.*/, "", p)
            if (p !~ /^(--regexp=|--grep=|--author=|--committer=|--message=|--glob=|-e|-S|-G|-m|-g)$/) { ok = 0; break }
            w = p
          }
          if (tolower(w) ~ /apply[_-]?patch/ && w !~ /^(-e|--regexp|--grep|--author|--committer|-S|-G|-m|--message|-g|--glob|-name|-iname|-path|-ipath)=/) { ok = 0; break }
          if (commit && j > 2 && w !~ /^(-m|-a|-am|--message(=.*)?|-s|--amend|--no-edit)$/) { ok = 0; break }
          if (nm == "git") {
            x = w; sub(/=.*/, "", x)
            if (w ~ /^(-c|-C|-p|-O)$/ || w ~ /^--(output|open-files-in-pager|ext|pag)/ || w ~ /^-[A-Za-z]*O/ || \
                (x ~ /^--o/ && (index("--output", x) == 1 || index("--open-files-in-pager", x) == 1))) { ok = 0; break }
          }
          if (nm == "rg" && (w ~ /^--(pre|hostname-bin|search-zip)/ || w ~ /^-[A-Za-z]*z/)) { ok = 0; break }
          if (nm == "find" && w ~ /^-(exec|execdir|ok|okdir|delete|fprint|fprint0|fprintf|fls)$/) { ok = 0; break }
          if (nm == "sort" && w ~ /^--co/) { ok = 0; break }
        }
      }
    }
    END { print (ok ? "ok" : "no") }' 2>/dev/null)"
  [ "$out" = ok ] && return 1
  return 0
}
