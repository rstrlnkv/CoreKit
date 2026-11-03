# scripts/bashlex-guard-secrets.awk — the guard-secrets.sh part of the Bash judging: finds the words that
# a file-reading command is given and that name a secret. Used with scripts/bash-lex.awk (the tokenizer):
#   awk -f bash-lex.awk -f bashlex-guard-secrets.awk
# Prints "P\t<word>\t<cd>" for each candidate (at most CAP, each word once): a word, as typed, whose last
# path component is .env or .env.* (not .env.example/.sample/.template; glob characters count, so .env*
# is one) or that has a .ssh path component. <cd> is 1 when a cd/pushd/popd came before, which makes a
# relative path unknown (the name is still a secret name, a .ssh folder is not judged). The caller
# judges the candidates (symlinks, the real ~/.ssh).
# Judged: the arguments of the commands in RD, and the word after an input redirect (< file). Not
# judged: output redirects, commands that do not read (ls, rm, git, echo, ...), quoted text.
BEGIN {
  CAP = 200
  split("cat less more most head tail source . grep egrep fgrep rg ag ack sed awk gawk mawk cp scp base64 xxd od hexdump strings diff cmp comm open vim vi view nvim nano pico emacs code bat nl tac rev cut paste sort uniq fold fmt column ed tar zip gzip rsync", R, " ")
  for (k in R) RD[R[k]] = 1
  # the first operand of these is a pattern or a script, not a file
  split("grep egrep fgrep rg ag ack sed awk gawk mawk", P, " "); for (k in P) PAT[P[k]] = 1
  # these copy: the last operand is the destination (so `cp .env.example .env` is not a read of .env)
  CP["cp"] = 1; CP["scp"] = 1
}
function classify(b) {
  if (b == "cd" || b == "pushd" || b == "popd") cdseen = 1
  return (b in RD) ? b : "?"
}
function on_out(w) { }   # a file written is not a file read
function on_in(w) { cand(w) }
function cand(a,   l, t, x) {
  if (nomore || full || a == "") return
  if (index(a, "\t") || index(a, "\002")) return
  l = tolower(a)
  if (index(l, ".env") == 0 && index(l, ".ssh") == 0) return
  t = l
  while (length(t) > 1 && substr(t, length(t), 1) == "/") t = substr(t, 1, length(t) - 1)
  x = t; sub(/.*\//, "", x)
  if (!(x ~ /^\.env([*?\[{]|$)/ || (x ~ /^\.env\./ && x !~ /^\.env\.(example|sample|template)$/)) && t !~ /(^|\/)\.ssh(\/|$)/) return
  if (a in seen) return
  seen[a] = 1
  if (ne >= CAP) { full = 1; return }
  ne++
  printf "P\t%s\t%d\n", a, cdseen
}
function finalize(   k, a, dd, pat, nm, v, nop, tdir, j, n, ops) {
  if (cmd == "" || cmd == "?") return
  dd = 0; pat = (cmd in PAT); nop = 0; tdir = ""
  for (k = 1; k <= na && !full; k++) {
    a = args[k]
    if (!dd && a == "--") { dd = 1; continue }
    if (!dd && substr(a, 1, 1) == "-" && a != "-") {
      if ((cmd in CP) && a == "-t") { tdir = "x"; k++; continue }
      if ((cmd in CP) && a ~ /^--target-directory=/) { tdir = "x"; continue }
      if (pat && (a == "-e" || a == "--regexp")) { k++; pat = 0; continue }
      if (pat && (a == "-f" || a == "--file")) { cand(args[k + 1]); k++; continue }
      if (a ~ /^--[A-Za-z][A-Za-z-]*=/) {
        nm = substr(a, 1, index(a, "=") - 1); v = substr(a, index(a, "=") + 1)
        if (nm == "--regexp") pat = 0
        else if (!(cmd in CP)) cand(v)
      }
      continue
    }
    if (pat) { pat = 0; continue }
    if (cmd in CP) ops[++nop] = a; else cand(a)
  }
  if (cmd in CP) {
    n = (tdir != "") ? nop : nop - 1
    for (j = 1; j <= n && !full; j++) cand(ops[j])
  }
  split("", ops)
}
