# scripts/bashlex-guard-secrets.awk — the guard-secrets.sh part of the Bash judging: finds the words that
# a file-reading command is given and that name a secret. Used with scripts/bash-lex.awk (the tokenizer):
#   awk -f bash-lex.awk -f bashlex-guard-secrets.awk
# Prints "P\t<word>\t<cd>\t<judged>" for each candidate (at most CAP, each word once): a word, as typed, whose last
# path component is .env or .env.* (not .env.example/.sample/.template; glob characters count, so .env*
# is one) or that has a .ssh path component. <cd> is 1 when a cd/pushd/popd came before, which makes a
# relative path unknown (the name is still a secret name, a .ssh folder is not judged). The caller
# judges the candidates (symlinks, the real ~/.ssh). <judged> is the word the caller judges: the same word, or, for a
# glob, the word with each component that can match .ssh or a secret name replaced by that name (see cand).
# Also prints "X\tnomore" or "X\tcap" when reading stopped early (a <<"WORD" inside "$(...)", or more than
# CAP candidates), and "X\tdoubt" when the tokenizer may have skipped a command (bash-lex.awk, doubt): the caller
# does not trust the reading and judges the raw text.
# Command substitutions inside double quotes ("$(cat .env)", backticks) are lexed as command lines of their
# own, once the main pass is done (on_subst -> subst_queue in bash-lex.awk).
# Judged: the arguments of the commands in RD, and the word after an input redirect (< file). Not
# judged: output redirects, commands that do not read (ls, rm, git, echo, ...), quoted text.
BEGIN {
  CAP = 200
  split("cat less more most head tail source . grep egrep fgrep rg ag ack sed awk gawk mawk cp scp base64 xxd od hexdump strings diff cmp comm open vim vi view nvim nano pico emacs code bat nl tac rev cut paste sort uniq fold fmt column ed tar zip gzip rsync", R, " ")
  for (k in R) RD[R[k]] = 1
  # the first operand of these is a pattern or a script, not a file
  split("grep egrep fgrep rg ag ack sed awk gawk mawk", P, " "); for (k in P) PAT[P[k]] = 1
  # these copy: the last operand is the destination (so `cp .env.example .env` is not a read of .env)
  CP["cp"] = 1; CP["scp"] = 1; CP["rsync"] = 1
  # Options that take a value, per command. The value is a pattern (EO, replaces the pattern operand), a file
  # of patterns or a script (FO: judged as a file, replaces the pattern operand), a file name glob (GO:
  # judged, the pattern operand stays), or something else (VO: skipped). Other options take no value.
  reg(EO, "grep egrep fgrep rg sed", "-e --regexp --expression")
  reg(EO, "gawk", "-e --source")
  reg(FO, "grep egrep fgrep rg sed awk gawk mawk", "-f --file")
  reg(GO, "grep egrep fgrep", "--include")
  reg(GO, "rg", "-g --glob --iglob --ignore-file")
  reg(VO, "grep egrep fgrep", "-A -B -C -m -d -D --after-context --before-context --context --max-count --directories --devices --binary-files --exclude --exclude-dir --label --group-separator")
  reg(VO, "rg", "-t -T -m -A -B -C -M -j -r -E -d --type --type-not --type-add --max-count --context --after-context --before-context --max-columns --threads --encoding --replace --max-depth --sort --sortr --pre --colors")
  reg(VO, "ag ack", "-A -B -C -m -G -g --depth --max-count --after --before --context")
  reg(FO, "ag", "-p --path-to-ignore")
  reg(VO, "sed", "-l --line-length")
  reg(VO, "rsync", "--exclude --include --filter -f -e --rsh")
  reg(FO, "rsync", "--exclude-from --include-from")
  reg(VO, "awk gawk mawk", "-v -F --assign --field-separator")
  # a key handed to scp (-i) is used by ssh, not shown to Claude; tar excludes and the archive name are not reads
  reg(VO, "scp", "-i -P -F -o -J -l -c -S")
  reg(VO, "tar", "--exclude -f --file -C --directory")
}
# reg(table, "cmd cmd", "opt opt") — table[cmd, opt] = 1
function reg(tab, cmds, opts,   nc, no, x, y, cl, ol) {
  nc = split(cmds, cl, " "); no = split(opts, ol, " ")
  for (x = 1; x <= nc; x++) for (y = 1; y <= no; y++) tab[cl[x], ol[y]] = 1
}
END {
  if (nomore) print "X\tnomore"
  else if (capped) print "X\tcap"
  else if (doubt) print "X\tdoubt"
}
# on_subst(w) — a $(...) or backtick body inside double quotes is queued as a command line (bash-lex.awk)
function on_subst(w) { subst_queue(w) }
function classify(b) {
  if (b == "cd" || b == "pushd" || b == "popd") cdseen = 1
  return (b in RD) ? b : "?"
}
function on_out(w) { }   # a file written is not a file read
function on_in(w) { cand(w) }
# glob_re(g) — the glob g (as bash reads it: * ? [..] {a,b}) as an anchored regular expression
function glob_re(g,   n, p, c, r, depth, bal, q, cl) {
  n = length(g); depth = 0; bal = 1
  for (p = 1; p <= n; p++) { c = substr(g, p, 1); if (c == "{") depth++; else if (c == "}") { depth--; if (depth < 0) bal = 0 } }
  if (depth != 0) bal = 0
  r = "^"; depth = 0
  for (p = 1; p <= n; p++) {
    c = substr(g, p, 1)
    if (c == "*") r = r ".*"
    else if (c == "?") r = r "."
    else if (c == "[") {
      q = p + 1
      if (substr(g, q, 1) == "!" || substr(g, q, 1) == "^") q++
      if (substr(g, q, 1) == "]") q++
      while (q <= n && substr(g, q, 1) != "]") q++
      if (q > n) r = r "\\["
      else {
        cl = substr(g, p + 1, q - p - 1)
        if (substr(cl, 1, 1) == "!") cl = "^" substr(cl, 2)
        r = r "[" cl "]"; p = q
      }
    }
    else if (c == "{" && bal) { r = r "("; depth++ }
    else if (c == "}" && bal) { r = r ")"; depth-- }
    else if (c == "," && bal && depth > 0) r = r "|"
    else if (index(".+()|^$\\{}", c)) r = r "\\" c
    else r = r c
  }
  return r "$"
}
# glob_hits(comp, want) — the component has a glob character, starts with a dot or a { (a leading * ? [ does
# not match a dot in bash), has a letter or digit in it (so .* and .??* pass), and can match the name want
# (or, for want = ".env", one of the names .env.local, .env.production, ...)
function glob_hits(comp, want,   re, k, ns, smp) {
  if (comp !~ /[*?\[{]/ || comp !~ /^[.{]/ || comp !~ /[a-z0-9]/) return 0
  re = glob_re(comp)
  if (want == ".ssh") return (".ssh" ~ re)
  ns = split(".env .env.local .env.production .env.development .env.test .env.staging", smp, " ")
  for (k = 1; k <= ns; k++) if (smp[k] ~ re) return 1
  return 0
}
# cand(a) — a word to judge. Prints "P\t<word as typed>\t<cd>\t<word to judge>": the last form is the same word, or
# with a glob component that can match .ssh or a secret name replaced by that name (~/.s*/id_rsa -> ~/.ssh/id_rsa).
function cand(a,   l, t, x, nc, comp, k, hit, norm) {
  if (nomore || full || a == "") return
  if (index(a, "\t") || index(a, "\002")) return
  l = tolower(a)
  t = l
  while (length(t) > 1 && substr(t, length(t), 1) == "/") t = substr(t, 1, length(t) - 1)
  x = t; sub(/.*\//, "", x)
  norm = a
  if (!(x ~ /^\.env([*?\[{]|$)/ || (x ~ /^\.env\./ && x !~ /^\.env\.(example|sample|template)$/)) && t !~ /(^|\/)\.ssh(\/|$)/) {
    if (t !~ /[*?\[{]/) return
    # a glob: judge each component
    nc = split(t, comp, "/"); hit = 0
    for (k = nc; k >= 1; k--) {
      if (glob_hits(comp[k], k == nc ? ".env" : ".ssh")) {
        if (k == nc) { hit = 1; comp[k] = ".env" }
        else { hit = 1; comp[k] = ".ssh" }
      }
    }
    if (!hit) return
    # rebuild from the lower-case parts (letter case is folded by the caller anyway)
    norm = comp[1]
    for (k = 2; k <= nc; k++) norm = norm "/" comp[k]
  }
  if (a in seen) return
  seen[a] = 1
  if (ne >= CAP) { full = 1; capped = 1; return }
  ne++
  printf "P\t%s\t%d\t%s\n", a, cdseen, norm
}
# short_opt(a) — a is a short option word (-x, or a cluster such as -rnA). When one of its letters takes a value, sets
# sk (E F G V, or T for cp -t), sl (the letter as "-x") and sv (the value attached after it, "" when the value is the
# next word) and returns 1. The first value-taking letter ends the cluster: what follows it is its value (-A2n).
function short_opt(a,   p, n, l, kind) {
  n = length(a)
  for (p = 2; p <= n; p++) {
    l = "-" substr(a, p, 1); kind = ""
    if ((cmd, l) in EO) kind = "E"
    else if ((cmd, l) in FO) kind = "F"
    else if ((cmd, l) in GO) kind = "G"
    else if ((cmd, l) in VO) kind = "V"
    else if (cmd == "cp" && l == "-t") kind = "T"
    if (kind != "") { sk = kind; sl = l; sv = substr(a, p + 1); return 1 }
  }
  return 0
}
function finalize(   k, a, dd, pat, nm, v, nop, tdir, j, n, ops) {
  if (cmd == "" || cmd == "?") return
  dd = 0; pat = (cmd in PAT); nop = 0; tdir = ""
  for (k = 1; k <= na && !full; k++) {
    a = args[k]
    if (!dd && a == "--") { dd = 1; continue }
    if (!dd && substr(a, 1, 1) == "-" && a != "-") {
      # zip: -x and -i are followed by a list of patterns up to the next option
      if (cmd == "zip" && (a == "-x" || a == "-i" || a == "--exclude" || a == "--include")) {
        while (k < na && substr(args[k + 1], 1, 1) != "-") k++
        continue
      }
      if (cmd == "cp" && a ~ /^--target-directory=/) { tdir = "x"; continue }
      if (a ~ /^-[A-Za-z0-9]/ && short_opt(a)) {
        v = sv
        if (v == "") { v = args[k + 1]; k++ }
        if (sk == "E") pat = 0
        else if (sk == "F") { cand(v); if (sl == "-f") pat = 0 }
        else if (sk == "G") cand(v)
        else if (sk == "T") tdir = "x"
        continue
      }
      if ((cmd, a) in EO) { k++; pat = 0; continue }
      if ((cmd, a) in FO) { cand(args[k + 1]); k++; if (a == "--file") pat = 0; continue }
      if ((cmd, a) in GO) { cand(args[k + 1]); k++; continue }
      if ((cmd, a) in VO) { k++; continue }
      if (a ~ /^--[A-Za-z][A-Za-z-]*=/) {
        nm = substr(a, 1, index(a, "=") - 1); v = substr(a, index(a, "=") + 1)
        if ((cmd, nm) in EO) pat = 0
        else if ((cmd, nm) in FO) { cand(v); if (nm == "--file") pat = 0 }
        else if ((cmd, nm) in GO) cand(v)
        else if ((cmd, nm) in VO) { }
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
