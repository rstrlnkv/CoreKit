#!/usr/bin/env bash
# Claude Code PreToolUse hook on Write|Edit|NotebookEdit (and Bash, best effort): a project's
# internal files must not live in its code repo. It blocks writes of
#   CLAUDE.md (and CLAUDE.local.md), docs/**, .claude/**
# under <Core>/<project>/code/**, with exit 2 and a message naming the right place:
#   coredev: <path> is an internal file and must not live in code/. Write it to <Core>/<project>/<relative path> instead.
# (spec section 14, item 3). Nothing is ever printed to stdout.
#
# Rules, all compared on the canonical path (".." and symlinks resolved, letter case as on disk
# for the part that exists, then folded to lower case for the comparison, ASCII only):
# - The code root is <Core>/<p>/code/, or a worktree root <Core>/<p>/code/.claude/worktrees/<w>/;
#   inside a worktree the path relative to the worktree root is what counts.
# - Blocked: docs and docs/** and .claude/** at the root, and CLAUDE.md / CLAUDE.local.md at ANY depth
#   (the same as scripts/git-hooks/blocked-patterns, so the hook and the commit check agree).
# - Allowed: .claude/settings.local.json, .claude/worktrees/** (the worktree dirs themselves), and the
#   paths on a "public-docs: <paths>" line of <Core>/<p>/CLAUDE.md (space or comma separated, relative
#   to the code root; a directory entry covers everything under it; a glob is not expanded).
# - Bash is best effort. Targets of > >> 2> &> >| >&file, tee, touch, cp, mv (the destination; a
#   destination directory also gets the sources' names), mkdir. mkdir follows the same rules as a
#   write (docs, .claude/rules, ...) except the bare ".claude" dir, which holds settings.local.json.
#   Not followed: cd, variables, globs, `sh -c "..."`, ln, install, in-place sed, rsync, scripts. A target
#   that has $ ` * ? [ { is not judged. Quoted text is not a command, heredoc bodies and comments are
#   skipped. At most 100 targets are looked at. The tokenizer is one linear pass in awk. A command this
#   hook cannot parse passes (exit 0). The git pre-commit hook stays the last layer.
# - Inert outside <Core>/<project>/: a target and a cwd that are not in a Core project pass (exit 0).
#   No network, no git; only canon_dir, project_of and one grep of the CLAUDE.md public-docs line.
# - Input it cannot read (not JSON, no cwd, no path or command) passes.
SELF="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || exit 0
in=""; [ -t 0 ] || in="$(cat)"
. "$SELF/scripts/lib.sh" 2>/dev/null || exit 0

tool="$(json_str "$in" tool_name)"
cwd="$(json_str "$in" cwd)"
[ -n "$cwd" ] || exit 0

# lc <text> — ASCII lower case (bytes above 127 are left alone, so Cyrillic stays as it is).
lc() { printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z'; }

# norm_path <absolute path> — "." and ".." and repeated slashes resolved lexically (what is left after
# canon_dir for a part of the path that does not exist yet).
norm_path() {
  local IFS=/ seg out=""
  set -f
  for seg in $1; do
    case "$seg" in ""|.) ;; ..) out="${out%/*}" ;; *) out="$out/$seg" ;; esac
  done
  set +f
  printf '%s' "${out:-/}"
}

# resolve_abs <path> — sets ABS: the canonical absolute path. A relative path is taken from cwd; the
# directory part goes through canon_dir; a link as the last part is followed (up to 8 times).
resolve_abs() {
  local t="$1" dir base link n=0
  while :; do
    case "$t" in "~"|"~/"*) t="$(expand_home "$t")" ;; esac
    case "$t" in /*) ;; *) t="$cwd/$t" ;; esac
    while [ "${#t}" -gt 1 ] && [ "${t%/}" != "$t" ]; do t="${t%/}"; done
    base="${t##*/}"; dir="${t%/*}"; [ -n "$dir" ] || dir="/"
    case "$base" in
      ""|.|..) ABS="$(norm_path "$(canon_dir "$t")")"; return 0 ;;
    esac
    t="$(norm_path "$(canon_dir "$dir")/$base")"
    if [ -L "$t" ] && [ "$n" -lt 8 ]; then
      link="$(readlink "$t")" || break
      [ -n "$link" ] || break
      n=$((n + 1))
      case "$link" in /*) t="$link" ;; *) t="${t%/*}/$link" ;; esac
      continue
    fi
    break
  done
  ABS="$t"
}

# is_public <project> <lower-case path relative to the code root> — exit 0 when a public-docs: entry covers it.
is_public() {
  local f="$CORE_DIR/$1/CLAUDE.md" line t
  [ -f "$f" ] || return 1
  line="$(LC_ALL=C grep -m1 '^public-docs:' "$f" 2>/dev/null)" || return 1
  line="$(printf '%s' "${line#public-docs:}" | LC_ALL=C tr 'A-Z,\r`' 'a-z   ')"
  set -f
  for t in $line; do
    t="${t#./}"
    while [ "${t%/}" != "$t" ]; do t="${t%/}"; done
    [ -n "$t" ] || continue
    case "$2" in "$t"|"$t"/*) set +f; return 0 ;; esac
  done
  set +f
  return 1
}

# check_path <path> [dir] — exits 2 with the message when the path is an internal file under a
# project's code root; returns 0 otherwise. Mode "dir" (mkdir) lets the bare .claude through.
check_path() {
  local mode="${2:-write}" proj rest rest_l sub sub_l w n tgt
  resolve_abs "$1"
  proj="$(project_of "$ABS")" || return 0
  rest="${ABS#"$CORE_DIR/$proj/"}"
  [ "$rest" != "$ABS" ] || return 0
  rest_l="$(lc "$rest")"
  case "$rest_l" in code/?*) ;; *) return 0 ;; esac
  sub="${rest:5}"; sub_l="${rest_l:5}"
  # a worktree: the path relative to its root counts (repeatedly, a worktree may hold a .claude/worktrees)
  while :; do
    case "$sub_l" in
      .claude/worktrees/*/?*)
        w="${sub_l#.claude/worktrees/}"; w="${w%%/*}"
        n=$((18 + ${#w} + 1))   # ".claude/worktrees/" is 18 bytes
        sub="${sub:$n}"; sub_l="${sub_l:$n}" ;;
      .claude/worktrees|.claude/worktrees/*) return 0 ;;
      *) break ;;
    esac
  done
  case "$sub_l" in
    .claude/settings.local.json) return 0 ;;
    .claude) [ "$mode" = dir ] && return 0 ;;
    .claude/*|docs|docs/*) ;;
    claude.md|claude.local.md|*/claude.md|*/claude.local.md) ;;
    *) return 0 ;;
  esac
  if is_public "$proj" "$sub_l"; then return 0; fi
  # the Core's copy is spelled the usual way even when the path was typed in another letter case
  tgt="$sub"
  case "$sub_l" in docs|docs/*) tgt="docs${sub:4}" ;; .claude/*) tgt=".claude${sub:7}" ;; esac
  case "$sub_l" in
    claude.md) tgt="CLAUDE.md" ;;
    claude.local.md) tgt="CLAUDE.local.md" ;;
    */claude.md) tgt="${tgt%/*}/CLAUDE.md" ;;
    */claude.local.md) tgt="${tgt%/*}/CLAUDE.local.md" ;;
  esac
  printf 'coredev: %s is an internal file and must not live in code/. Write it to %s instead.\n' \
    "$CORE_DIR/$proj/code/${rest:5}" "$CORE_DIR/$proj/$tgt" >&2
  exit 2
}

# --- Write, Edit, NotebookEdit: one path in the tool input.
if [ "$tool" != Bash ]; then
  key=file_path; [ "$tool" = NotebookEdit ] && key=notebook_path
  path="$(json_str "$in" "$key")"
  [ -n "$path" ] || exit 0
  load_settings
  check_path "$path"
  exit 0
fi

# --- Bash: targets of redirects and file commands, found by one awk pass.
cmd="$(json_str "$in" command)"
[ -n "$cmd" ] || exit 0
# Cheap exit: nothing in the command can write a file.
case "$cmd" in *">"*|*tee*|*touch*|*cp*|*mv*|*mkdir*) ;; *) exit 0 ;; esac

# bash_targets — stdin: the command (newlines turned into \002 by the caller). Prints "<kind>\t<path>[\t<name>]":
# W a file written, D a directory made (mkdir), J a destination (cp/mv) that may be a directory: <name> is a source's name.
bash_targets() {
  LC_ALL=C awk '
    function emit(kind, a, b) {
      if (ne >= CAP) { full = 1; return }
      if (a == "" || index(a, "/dev/") == 1) return
      for (q = 1; q <= length(BADCH); q++) if (index(a, substr(BADCH, q, 1))) return
      ne++
      if (b == "") printf "%s\t%s\n", kind, a; else printf "%s\t%s\t%s\n", kind, a, b
      if (ne >= CAP) full = 1
    }
    # seg(a, b) — the characters a..b-1 joined; "\001" when that is longer than 4096 bytes (BWK awk
    # substr() on a long string is slow, so the text is split into characters once and read from C[])
    function seg(a, b,   r, x) {
      if (b - a > 4096) return "\001"
      r = ""
      for (x = a; x < b; x++) r = r C[x]
      return r
    }
    # append text to the word being read; a word longer than 4096 bytes is dropped (it is not a path)
    function app(t) {
      if (wbad) return
      if (t == "\001") { wbad = 1; word = ""; return }
      wl += length(t)
      if (wl > 4096) { wbad = 1; word = ""; return }
      word = word t
    }
    function base(p,   r) {
      r = p
      while (length(r) > 1 && substr(r, length(r), 1) == "/") r = substr(r, 1, length(r) - 1)
      sub(/.*\//, "", r)
      return r
    }
    function skip_heredocs(   k, j, line, found) {
      for (k = 1; k <= hdn; k++) {
        found = 0
        while (i <= len && !found) {
          j = i
          while (j <= len && C[j] != NL) j++
          line = (j - i > 4096) ? "\001" : seg(i, j)
          if (hds[k]) sub(/^\t+/, "", line)
          i = j + 1
          if (line == hd[k]) found = 1
        }
      }
      hdn = 0
    }
    function endword(   w, qd, b) {
      if (!inword) return
      w = word; qd = hasq
      inword = 0; word = ""; hasq = 0; wl = 0; wbad = 0
      if (skip_next) { skip_next = 0; return }
      if (want_hd) { want_hd = 0; hdn++; hd[hdn] = w; hds[hdn] = hdstrip; return }
      if (want_redir) {
        if (want_redir == 2 && w ~ /^([0-9]+-?|-)$/) { want_redir = 0; return }
        want_redir = 0; emit("W", w, ""); return
      }
      if (cmd == "") {
        if (!qd && w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) return
        if (wrapped && substr(w, 1, 1) == "-") return
        b = base(w)
        if (b in WR) { wrapped = 1; return }
        cmd = (b in TRACK) ? b : "?"
        return
      }
      if (cmd != "?") args[++na] = w
    }
    function finalize(   k, a, dd, nop, tdir, j, dest) {
      dd = 0
      if (cmd == "tee") {
        for (k = 1; k <= na && !full; k++) {
          a = args[k]
          if (!dd && a == "--") { dd = 1; continue }
          if (!dd && substr(a, 1, 1) == "-") continue
          emit("W", a, "")
        }
      } else if (cmd == "touch") {
        for (k = 1; k <= na && !full; k++) {
          a = args[k]
          if (!dd && a == "--") { dd = 1; continue }
          if (!dd && (a == "-t" || a == "-d" || a == "-r" || a == "--date" || a == "--reference")) { k++; continue }
          if (!dd && substr(a, 1, 1) == "-") continue
          emit("W", a, "")
        }
      } else if (cmd == "mkdir") {
        for (k = 1; k <= na && !full; k++) {
          a = args[k]
          if (!dd && a == "--") { dd = 1; continue }
          if (!dd && (a == "-m" || a == "--mode")) { k++; continue }
          if (!dd && substr(a, 1, 1) == "-") continue
          emit("D", a, "")
        }
      } else if (cmd == "cp" || cmd == "mv") {
        nop = 0; tdir = ""
        for (k = 1; k <= na; k++) {
          a = args[k]
          if (!dd && a == "--") { dd = 1; continue }
          if (!dd && a == "-t") { tdir = args[k + 1]; k++; continue }
          if (!dd && a ~ /^--target-directory=/) { tdir = substr(a, 20); continue }
          if (!dd && (a == "-S" || a == "--suffix")) { k++; continue }
          if (!dd && substr(a, 1, 1) == "-" && a != "-") continue
          ops[++nop] = a
        }
        if (tdir != "") {
          for (j = 1; j <= nop && !full; j++) emit("J", tdir, base(ops[j]))
        } else if (nop >= 2) {
          dest = ops[nop]
          emit("W", dest, "")
          for (j = 1; j < nop && !full; j++) emit("J", dest, base(ops[j]))
        }
        split("", ops)
      }
      split("", args)
      cmd = ""; na = 0; wrapped = 0; want_redir = 0; skip_next = 0; want_hd = 0
    }
    BEGIN {
      NL = "\002"; CAP = 100; STOP = " \t\002;|" "&<>()`\047\"\\"; BADCH = "$`*?[{\t\002"
      split("tee touch mkdir cp mv", T, " "); for (k in T) TRACK[T[k]] = 1
      split("sudo command nohup time exec env builtin nice then do else elif if while until ! { } ( ) doas", Wd, " "); for (k in Wd) WR[Wd[k]] = 1
    }
    { buf = (NR == 1 ? "" : buf) $0 }
    END {
      len = split(buf, C, ""); i = 1
      while (i <= len && !full) {
        c = C[i]
        if (c == " " || c == "\t") { endword(); i++; continue }
        if (c == NL) { endword(); finalize(); i++; if (hdn > 0) skip_heredocs(); continue }
        if (c == "#" && !inword) { while (i <= len && C[i] != NL) i++; continue }
        if (c == "\\") {
          if (i < len) {
            d = C[i + 1]
            if (d != NL) { app(d); inword = 1; hasq = 1 }
            i += 2
          } else i++
          continue
        }
        if (c == "\047") {
          inword = 1; hasq = 1; j = i + 1
          while (j <= len && C[j] != "\047") j++
          app(seg(i + 1, j))
          i = j + 1; continue
        }
        if (c == "\"") {
          inword = 1; hasq = 1; k = i + 1; j = k
          while (j <= len) {
            d = C[j]
            if (d == "\"") break
            if (d == "\\" && j < len) {
              e = C[j + 1]
              if (e == "\"" || e == "\\" || e == "$" || e == "`") { app(seg(k, j)); app(e); j += 2; k = j; continue }
              if (e == NL) { app(seg(k, j)); j += 2; k = j; continue }
            }
            j++
          }
          app(seg(k, j))
          i = j + 1; continue
        }
        if (c == ";" || c == "|" || c == "(" || c == ")" || c == "`") { endword(); finalize(); i++; continue }
        if (c == "&") {
          endword()
          if (C[i + 1] == ">") {
            i += 2; if (C[i] == ">") i++
            want_redir = 1; continue
          }
          finalize(); i++; continue
        }
        if (c == ">") {
          if (inword && !hasq && !wbad && word ~ /^[0-9]+$/) { inword = 0; word = ""; wl = 0 } else endword()
          i++
          if (C[i] == "(") continue
          d = C[i]
          if (d == ">" || d == "|") { i++; d = C[i] }
          if (d == "&") { i++; want_redir = 2 } else want_redir = 1
          continue
        }
        if (c == "<") {
          endword()
          if (C[i + 1] == "<") {
            if (C[i + 2] == "<") { i += 3; skip_next = 1; continue }
            i += 2; hdstrip = 0
            if (C[i] == "-") { hdstrip = 1; i++ }
            want_hd = 1; continue
          }
          if (C[i + 1] == "(") { i++; continue }
          i++; if (C[i] == "&") i++
          skip_next = 1; continue
        }
        j = i
        while (j <= len && index(STOP, C[j]) == 0) j++
        app(seg(i, j)); inword = 1; i = j
      }
      endword(); finalize()
    }
  '
}

targets="$(printf '%s' "$cmd" | LC_ALL=C tr '\n\r' '\002 ' | bash_targets)"
[ -n "$targets" ] || exit 0
load_settings
TAB="$(printf '\t')"
while IFS="$TAB" read -r kind a b; do
  case "$kind" in
    W) check_path "$a" ;;
    D) check_path "$a" dir ;;
    J)
      case "$b" in ""|.|..) continue ;; esac
      resolve_abs "$a"
      if [ -d "$ABS" ] || [ "${a%/}" != "$a" ]; then check_path "${a%/}/$b"; fi ;;
  esac
done <<< "$targets"
exit 0
