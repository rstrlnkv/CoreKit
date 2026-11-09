# scripts/bash-lex.awk — the shared Bash tokenizer of guard-secrets.sh and of the read-only checkers' rule in
# guard-code.sh. guard-code's write check does not use it: it has its own reader, bashlex-guard-code.awk.
# One linear pass over a command whose newlines were turned into \002 and carriage returns into spaces
# (tr '\n\r' '\002 '). Quoted text is words, heredoc bodies and comments are skipped, wrapper words
# (sudo, env, time, if, do, ...) and VAR=value prefixes are skipped. Run it as
#   awk -f bash-lex.awk -f <hook program>.awk
# Speed: when the command holds no \004 byte, the callers also turn spaces into \004 (tr '\n\r ' '\002\004\004')
# and say so with -v lexsp=1. Then \004 is a blank here like a space, and the text is also split at it once (a fast
# split on one literal byte), so a plain word (no quote, backslash, # first, operator or blank in it) that starts
# right after a blank is taken whole instead of byte by byte, and the text is split into bytes only once the byte loop
# is needed. Any other text (a command line queued by enqueue, or any text when lexsp is not 1: a command with a \004
# byte of its own keeps it as a word byte, as the shell does) is read byte by byte. Every string made from the text
# (seg) has its \004 turned back into spaces, so a hook program never sees one.
# The hook program supplies (see bashlex-guard-secrets.awk, bashlex-readonly.awk):
#   classify(b)  — b is the base name of a command word; returns the command to remember, or "?" to
#                  ignore its arguments (it may also note state, e.g. cdseen for cd)
#   on_out(w)    — w is the target of an output redirect (> >> >| &> >&file)
#   on_in(w)     — w is the word after an input redirect (< file)
#   on_subst(w)  — w is a word with a command substitution inside double quotes ("$(...)" or backticks);
#                  it may call subst_queue(w) to have each substitution lexed as a command line after the
#                  main pass (both programs do), or enqueue(text) for any other text
#   finalize()   — one command is complete: cmd (its name) and args[1..na] (its words) are set
#   globals it may set: full (stop reading); nomore is set here by <<"WORD" inside "$(...)" (reading stops:
#   a hook that must not fail open there can look at it in its END block)
# A shell run with -c (bash -c "...", sh -c, zsh -c, ...) and eval hand their command line to enqueue() too.
# State this file owns: cmd, args, na, wrapped, shk/sargs/nsa (shell -c and eval), and the redirect/heredoc flags.

BEGIN {
  NL = "\002"; BL = (lexsp == 1) ? "\004" : ""; STOP = " \t\002;|" "&<>()`\047\"\\" BL
  WORDCH = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
  split("sudo command nohup time exec env builtin nice then do else elif if while until ! { } ( ) doas timeout gtimeout stdbuf setsid caffeinate ionice unbuffer", Wd, " "); for (k in Wd) WR[Wd[k]] = 1
  # Options of a wrapper that take a value (the next word): `timeout 5 cat .env` and `sudo -u root cat .env`
  # run cat, so the value must not be read as the command. A value written in the same word (-n5, --user=x) needs nothing.
  wopt("sudo", "-u -g -h -p -C -D -R -T -U -r -t -c --user --group --host --prompt --close-from --chdir --chroot --command-timeout --other-user --role --type")
  wopt("doas", "-u -C")
  wopt("env", "-u -C -S --unset --chdir --split-string")
  wopt("nice", "-n --adjustment")
  wopt("timeout", "-s -k --signal --kill-after"); wopt("gtimeout", "-s -k --signal --kill-after")
  wopt("stdbuf", "-i -o -e --input --output --error")
  wopt("ionice", "-c -n -p -P -u --class --classdata --pid --pgid --uid")
  wopt("time", "-f -o --format --output")
  wopt("exec", "-a")
  wopt("caffeinate", "-t -w")
}
function wopt(w, opts,   n, l, x) { n = split(opts, l, " "); for (x = 1; x <= n; x++) WOPT[w, l[x]] = 1 }
# seg(a, b) — the characters a..b-1 joined; "\001" when that is longer than 4096 bytes (BWK awk
# substr() on a long string is slow, so the text is split into characters once and read from C[])
function seg(a, b,   r, x) {
  if (b - a > 4096) return "\001"
  r = ""
  for (x = a; x < b; x++) r = r C[x]
  if (BL != "" && index(r, BL)) gsub(/\004/, " ", r)
  return r
}
# append text to the word being read; a word longer than 4096 bytes is dropped (it is not a path).
# wx is the same word with every $ and backtick that is only text (escaped, or inside single quotes) turned
# into \003: that is what on_subst() gets, so it only sees real substitutions. tx is that text, when it differs.
function app(t, tx) {
  if (wbad) return
  if (t == "\001") { wbad = 1; word = ""; wx = ""; return }
  wl += length(t)
  if (wl > 4096) { wbad = 1; word = ""; wx = ""; return }
  word = word t; wx = wx (tx == "" ? t : tx)
}
# escx(c) — an escaped character as it goes into wx
function escx(c) { return (c == "$" || c == "`") ? "\003" : c }
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
function endword(   w, qd, b, rw, x) {
  if (!inword) return
  w = word; qd = hasq; x = wx
  inword = 0; word = ""; wx = ""; hasq = 0; wl = 0; wbad = 0
  if (wsub) { wsub = 0; on_subst(x) }
  if (skip_next) { skip_next = 0; return }
  if (want_hd) { want_hd = 0; hdn++; hd[hdn] = w; hds[hdn] = hdstrip; return }
  if (want_redir) {
    rw = rwredir; rwredir = 0
    if (want_redir == 2 && w ~ /^([0-9]+-?|-)$/) { want_redir = 0; return }
    want_redir = 0; on_out(w); if (rw) on_in(w); return   # <> reads and writes
  }
  if (want_in) { want_in = 0; on_in(w); return }
  if (cmd == "") {
    if (wskip) { wskip = 0; return }   # the value of a wrapper option
    if (!qd && w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) return
    if (wrapped && substr(w, 1, 1) == "-") { wrapper_opt(w); return }
    if (wdur) { wdur = 0; return }   # timeout's duration
    b = base(w)
    if (b in WR) { wrapped = 1; wname = b; wdur = (b == "timeout" || b == "gtimeout"); return }
    shk = (b == "bash" || b == "sh" || b == "zsh" || b == "dash" || b == "ksh") ? 1 : (b == "eval" ? 2 : 0)
    cmd = classify(b)
    return
  }
  if (cmd != "?") args[++na] = w
  else if (shk && nsa < 64) sargs[++nsa] = w
}
# shell_inner — the command was a shell (bash -c "..." and its kin) or eval: the command line it is handed
# is queued and lexed like any other, so `bash -c "cat .env"` is judged as `cat .env`.
function shell_inner(   k, a, t) {
  if (shk == 2) {
    for (k = 1; k <= nsa; k++) t = t (k > 1 ? " " : "") sargs[k]
    if (t != "") enqueue(t)
    return
  }
  for (k = 1; k <= nsa; k++) {
    a = sargs[k]
    if (a == "--") return
    if (a == "-o" || a == "+o") { k++; continue }          # -o pipefail: the option has a value
    if (a ~ /^-[A-Za-z]*c[A-Za-z]*$/) { if (k < nsa) enqueue(sargs[k + 1]); return }
    if (substr(a, 1, 1) != "-") return                      # a script file: not a command line
  }
}
# wrapper_opt(w) — w is an option of the wrapper wname: when its first value-taking letter ends the word
# (-u, -E -u, --user), the next word is the value
function wrapper_opt(w,   n, p, l) {
  if (w == "--") return
  if (substr(w, 2, 1) == "-") { if ((wname, w) in WOPT) wskip = 1; return }
  n = length(w)
  for (p = 2; p <= n; p++) {
    l = "-" substr(w, p, 1)
    if ((wname, l) in WOPT) { if (p == n) wskip = 1; return }
  }
}
# stmt_end — a command ends (; | & ( ) ` or a newline): the hook-specific finalize() judges it, then the
# state is cleared.
function stmt_end() {
  if (shk) shell_inner()
  finalize()
  split("", args); split("", sargs)
  shk = 0; nsa = 0
  cmd = ""; na = 0; wrapped = 0; wname = ""; wskip = 0; wdur = 0; want_redir = 0; want_in = 0; rwredir = 0; skip_next = 0; want_hd = 0
}
# fdword — a redirect starts: a word of digits right before it (2>, 0<) is the descriptor, not an argument.
# Not when the word is itself the target of a redirect still waiting for one (2>&1<file: 1 is the target).
function fdword() { if (inword && !hasq && !wbad && !want_redir && !want_in && word ~ /^[0-9]+$/) { inword = 0; word = ""; wx = ""; wl = 0 } else endword() }
# enqueue(text) — a command line to lex after the main pass (at most 50)
function enqueue(t) { if (nq < 50) Q[++nq] = t }
# subst_queue(w) — w has a $(...) or backtick substitution from inside double quotes: each body is queued as a
# command line (an unbalanced $( takes the rest of the word). A hook program's on_subst may call it.
function subst_queue(w,   n, p, c, depth, st, q) {
  n = length(w); p = 1
  while (p <= n) {
    c = substr(w, p, 1)
    if (c == "$" && substr(w, p + 1, 1) == "(") {
      st = p + 2; depth = 1; p = st
      while (p <= n && depth > 0) {
        c = substr(w, p, 1)
        if (c == "(") depth++
        else if (c == ")") depth--
        p++
      }
      enqueue(depth == 0 ? substr(w, st, p - 1 - st) : substr(w, st))
    } else if (c == "`") {
      q = index(substr(w, p + 1), "`")
      if (q == 0) { enqueue(substr(w, p + 1)); p = n + 1 }
      else { enqueue(substr(w, p + 1, q - 1)); p += q + 1 }
    } else p++
  }
}
{ buf = (NR == 1 ? "" : buf) $0 }
function lex(text,   lxn, lxk, lxpos, lxw, lxl, lxc) {
  len = length(text); i = 1; lxc = 0
  inword = 0; word = ""; wx = ""; hasq = 0; wl = 0; wbad = 0; hdn = 0; wsub = 0
  # LXW[k]: the k-th run between \004 blanks; LXS[position] = k for the first byte of each run
  split("", LXS); lxn = 0; lxpos = 1
  if (BL != "") lxn = split(text, LXW, BL)
  for (lxk = 1; lxk <= lxn; lxk++) { LXS[lxpos] = lxk; lxpos += length(LXW[lxk]) + 1 }
  while (i <= len && !full) {
    # fast path: a run that starts here and is one plain word is what the byte loop below would read (the plain-run
    # branch at the end), only whole: one app() of the run, or of "\001" when it is longer than 4096 bytes; then the
    # \004 after it (if any) ends the word, as the blank branch below would
    if (lxn > 1 && (i in LXS)) {
      lxw = LXW[LXS[i]]
      if (lxw != "" && (inword || substr(lxw, 1, 1) != "#") && lxw !~ /[ \t\002;|&<>()`'"\\]/) {
        lxl = length(lxw)
        app(lxl > 4096 ? "\001" : lxw); inword = 1; i += lxl
        if (i <= len) { endword(); i++ }
        continue
      }
    }
    # the byte loop: the text is split into bytes the first time it is needed (C[] is read only from here on)
    if (!lxc) { split(text, C, ""); lxc = 1 }
    c = C[i]
    if (c == " " || c == "\t" || c == BL) { endword(); i++; continue }
    if (c == NL) { endword(); stmt_end(); i++; if (hdn > 0) skip_heredocs(); continue }
    if (c == "#" && !inword) { while (i <= len && C[i] != NL) i++; continue }
    if (c == "\\") {
      if (i < len) {
        d = C[i + 1]; if (d == BL) d = " "
        if (d != NL) { app(d, escx(d)); inword = 1; hasq = 1 }
        i += 2
      } else i++
      continue
    }
    if (c == "\047") {
      inword = 1; hasq = 1; j = i + 1
      while (j <= len && C[j] != "\047") j++
      sq = seg(i + 1, j); sqx = sq; gsub(/[$`]/, "\003", sqx); app(sq, sqx)
      i = j + 1; continue
    }
    if (c == "\"") {
      inword = 1; hasq = 1; k = i + 1; j = k
      while (j <= len) {
        d = C[j]
        if (d == "\"") break
        if ((d == "$" && C[j + 1] == "(") || d == "`") wsub = 1
        # a heredoc inside "$(...)": its body (up to the delimiter line) is skipped, so a stray quote
        # in it cannot flip the quoting. <<"WORD" ends this span early: stop judging (fail open).
        if (d == NL && hdn > 0) { app(seg(k, j)); i = j + 1; skip_heredocs(); j = i; k = j; continue }
        if (d == "<" && C[j + 1] == "<" && C[j + 2] != "<") {
          p = j + 2; st = 0
          if (C[p] == "-") { st = 1; p++ }
          # <<"WORD" inside "$(...)": stop judging. A "<<" that is the end of the string ("<<" followed by
          # something that is no delimiter word and quote) is only text.
          if (C[p] == "\"") {
            q = p + 1; while (q <= len && C[q] != "" && index(WORDCH, C[q]) > 0) q++
            if (q > p + 1 && C[q] == "\"") { nomore = 1; break }
          }
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
          if (e == "\"" || e == "\\" || e == "$" || e == "`") { app(seg(k, j)); app(e, escx(e)); j += 2; k = j; continue }
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
      fdword()
      i++
      if (C[i] == "(") continue
      d = C[i]
      if (d == ">" || d == "|") { i++; d = C[i] }
      want_in = 0
      if (d == "&") { i++; want_redir = 2 } else want_redir = 1
      continue
    }
    if (c == "<") {
      fdword()
      if (C[i + 1] == "<") {
        if (C[i + 2] == "<") { i += 3; skip_next = 1; continue }
        i += 2; hdstrip = 0
        if (C[i] == "-") { hdstrip = 1; i++ }
        want_hd = 1; continue
      }
      if (C[i + 1] == "(") { i++; continue }
      if (C[i + 1] == ">") rwredir = 1
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
END {
  lex(buf)
  while (qi < nq && !full && !nomore) { qi++; lex(Q[qi]) }
}
