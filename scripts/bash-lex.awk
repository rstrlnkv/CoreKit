# scripts/bash-lex.awk — the shared Bash tokenizer of the coredev hooks (guard-code.sh, guard-secrets.sh).
# One linear pass over a command whose newlines were turned into \002 and carriage returns into spaces
# (tr '\n\r' '\002 '). Quoted text is words, heredoc bodies and comments are skipped, wrapper words
# (sudo, env, time, if, do, ...) and VAR=value prefixes are skipped. Run it as
#   awk -f bash-lex.awk -f <hook program>.awk
# The hook program supplies (see bashlex-guard-code.awk, bashlex-guard-secrets.awk):
#   classify(b)  — b is the base name of a command word; returns the command to remember, or "?" to
#                  ignore its arguments (it may also note state, e.g. cdseen for cd)
#   on_out(w)    — w is the target of an output redirect (> >> >| &> >&file)
#   on_in(w)     — w is the word after an input redirect (< file)
#   finalize()   — one command is complete: cmd (its name) and args[1..na] (its words) are set
#   globals it may set: full (stop reading), nomore (stop judging, set here too by <<"WORD" in "$(...)")
# State this file owns: cmd, args, na, wrapped, and the redirect/heredoc flags.

BEGIN {
  NL = "\002"; STOP = " \t\002;|" "&<>()`\047\"\\"
  WORDCH = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
  split("sudo command nohup time exec env builtin nice then do else elif if while until ! { } ( ) doas", Wd, " "); for (k in Wd) WR[Wd[k]] = 1
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
    want_redir = 0; on_out(w); return
  }
  if (want_in) { want_in = 0; on_in(w); return }
  if (cmd == "") {
    if (!qd && w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) return
    if (wrapped && substr(w, 1, 1) == "-") return
    b = base(w)
    if (b in WR) { wrapped = 1; return }
    cmd = classify(b)
    return
  }
  if (cmd != "?") args[++na] = w
}
# stmt_end — a command ends (; | & ( ) ` or a newline): the hook-specific finalize() judges it, then the
# state is cleared.
function stmt_end() {
  finalize()
  split("", args)
  cmd = ""; na = 0; wrapped = 0; want_redir = 0; want_in = 0; skip_next = 0; want_hd = 0
}
{ buf = (NR == 1 ? "" : buf) $0 }
END {
  len = split(buf, C, ""); i = 1
  while (i <= len && !full) {
    c = C[i]
    if (c == " " || c == "\t") { endword(); i++; continue }
    if (c == NL) { endword(); stmt_end(); i++; if (hdn > 0) skip_heredocs(); continue }
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
        # a heredoc inside "$(...)": its body (up to the delimiter line) is skipped, so a stray quote
        # in it cannot flip the quoting. <<"WORD" ends this span early: stop judging (fail open).
        if (d == NL && hdn > 0) { app(seg(k, j)); i = j + 1; skip_heredocs(); j = i; k = j; continue }
        if (d == "<" && C[j + 1] == "<" && C[j + 2] != "<") {
          p = j + 2; st = 0
          if (C[p] == "-") { st = 1; p++ }
          if (C[p] == "\"") { nomore = 1; break }
          dl = ""
          if (C[p] == "\047") {
            q = p + 1; while (q <= len && C[q] != "\047" && C[q] != NL && C[q] != "\"") q++
            if (C[q] == "\047") { dl = seg(p + 1, q); p = q + 1 }
          } else {
            q = p; while (q <= len && C[q] != "" && index(WORDCH, C[q]) > 0) q++
            dl = seg(p, q); p = q
          }
          if (dl != "" && dl != "\001") { hdn++; hd[hdn] = dl; hds[hdn] = st; j = p; continue }
        }
        if (d == "\\" && j < len) {
          e = C[j + 1]
          if (e == "\"" || e == "\\" || e == "$" || e == "`") { app(seg(k, j)); app(e); j += 2; k = j; continue }
          if (e == NL) { app(seg(k, j)); j += 2; k = j; continue }
        }
        j++
      }
      app(seg(k, j))
      if (nomore) break
      i = j + 1; continue
    }
    if (c == ";" || c == "|" || c == "(" || c == ")" || c == "`") { endword(); stmt_end(); i++; continue }
    if (c == "&") {
      endword()
      if (C[i + 1] == ">") {
        i += 2; if (C[i] == ">") i++
        want_redir = 1; continue
      }
      stmt_end(); i++; continue
    }
    if (c == ">") {
      if (inword && !hasq && !wbad && word ~ /^[0-9]+$/) { inword = 0; word = ""; wl = 0 } else endword()
      i++
      if (C[i] == "(") continue
      d = C[i]
      if (d == ">" || d == "|") { i++; d = C[i] }
      want_in = 0
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
      i++
      if (C[i] == "&") { i++; skip_next = 1 } else want_in = 1
      continue
    }
    j = i
    while (j <= len && index(STOP, C[j]) == 0) j++
    app(seg(i, j)); inword = 1; i = j
  }
  endword(); stmt_end()
}
