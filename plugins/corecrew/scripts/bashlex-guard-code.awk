# scripts/bashlex-guard-code.awk — guard-code.sh's plain reading of a Bash command: the files it would write.
# Used with scripts/bash-lex.awk (the tokenizer, shared with guard-secrets and the read-only checkers):
#   awk -v lexsp=<0|1> -f bash-lex.awk -f bashlex-guard-code.awk
# It is built for honest mistakes (SECURITY.md, "Threat model"), not against evasion: it switches off the
# tokenizer's following of bash -c, sh -c, eval and "$(...)" (nofollow), reads <<"WORD" inside "$(...)" as a heredoc
# (dqhd), and gets "\001" for a word longer than 4096 bytes (longw). What it does not follow is the LIMIT list in
# the guard-code.sh header. Output, each line at most once:
#   W <path>            a file written: the target of > >> >| &> >&file <>, tee, touch, the files of sed -i and
#                       perl -i, the destination of cp, mv, install, git mv
#   D <path>            a directory made: mkdir, install -d
#   J <dir> <source>    cp, mv, install, git mv: <dir>/<base name of source> is written when <dir> is a directory
#   L <dest> <source>   ln: a link at <dest>, or in it when it is a directory, that points to <source>; the source
#                       is empty when it is made at run time (unknown)
#   C                   the last line: too many targets to check (see below); the hook refuses the whole command
# Not printed: a path with $ ` * ? [ { (made at run time), /dev/..., and after cd, pushd or popd a relative path
# (the folder is unknown then), except after the one simple leading form `cd <absolute folder> &&` (or `;`, or a
# newline), when it is the first command, not in a subshell, with one plain / word: the relative paths after it are
# printed as <folder>/<path>, until another cd, pushd or popd. The first CAP distinct targets are printed; past that only those whose text
# names an internal component (docs, .claude, CLAUDE.md, CLAUDE.local.md, AGENTS.md, any letter case). When more
# than MORE such targets come past the first CAP, the reading stops with a C line, so the hook stays fast. A link
# or a copy into a folder (L, J) counts as three targets toward CAP and MORE: it costs about that much to judge.

BEGIN {
  nofollow = 1; dqhd = 1; longw = "\001"
  CAP = 100; MORE = 100; BAD = "$`*?[{\t\001\002"
  split("tee touch mkdir cp mv ln install sed perl git cd", t, " "); for (k in t) TRACK[t[k]] = 1
  split("docs .claude claude.md claude.local.md agents.md", t, " "); for (k in t) INTERNAL[t[k]] = 1
  # options that take the next word as their value
  vopt("touch", "-t -d -r --date --reference"); vopt("mkdir", "-m --mode"); vopt("install", "-m -o -g -S --mode --owner --group --suffix")
  vopt("cp", "-S --suffix"); vopt("mv", "-S --suffix"); vopt("ln", "-S --suffix"); vopt("sed", "-e -f -l --expression --file")
}
function vopt(c, list,   n, l, x) { n = split(list, l, " "); for (x = 1; x <= n; x++) VOPT[c, l[x]] = 1 }

# --- the tokenizer's hooks
function classify(b) {
  if (b == "cd" || b == "pushd" || b == "popd") cdseen = 1
  return (b in TRACK) ? b : "?"
}
function on_out(w) { emit("W", w, "") }
function on_in(w) { }        # a file read is not a file written
function on_subst(w) { }     # "$(...)" is not followed (LIMIT)

# --- printing
function internal(p,   n, part, x) {
  n = split(tolower(p), part, "/")
  for (x = 1; x <= n; x++) if (part[x] in INTERNAL) return 1
  return 0
}
function plain(p,   x) {
  for (x = 1; x <= length(BAD); x++) if (index(p, substr(BAD, x, 1))) return 0
  return 1
}
function emit(kind, p, src,   key, w) {
  if (p == "" || index(p, "/dev/") == 1 || !plain(p)) return
  if (p !~ /^(\/|~$|~\/)/) { if (cdseen) return; if (cdbase != "") p = cdbase "/" p }
  if (src != "" && src !~ /^(\/|~$|~\/)/ && !cdseen && cdbase != "") src = cdbase "/" src
  if (kind == "J" && !plain(src)) return
  if (kind == "L" && !plain(src)) src = ""     # the link itself is still judged; its source is unknown
  key = kind SUBSEP p SUBSEP src
  if (key in seen) return
  seen[key] = 1
  w = (kind == "L" || kind == "J") ? 3 : 1     # a link or a copy into a folder costs about three plain targets to judge
  ne += w
  if (ne > CAP) {
    if (!internal(p "/" src)) return
    ni += w
    if (ni > MORE) { print "C"; exit }         # too many to check in time: the hook refuses the command
  }
  if (src == "") printf "%s\t%s\n", kind, p; else printf "%s\t%s\t%s\n", kind, p, src
}

# --- one command is complete: cmd and args[1..na]; sep is what ended it (bash-lex.awk, stmt_end)
function finalize() {
  if (sep == "(" || sep == ")" || sep == "`") nosimple = 1
  # the leading `cd <absolute folder>` ended by && ; or a newline: the folder the relative targets after it are in
  if (cmd == "cd" && nstmt == 0 && !nosimple && na == 1 && args[1] ~ /^\// && plain(args[1]) && (sep == "&&" || sep == ";" || sep == "nl")) {
    cdbase = args[1]; sub(/\/+$/, "", cdbase); cdseen = 0
  }
  writes()
  if (cmd != "") nstmt++
}
function writes(   k, a, n, op, dd, tdir, script, inpl, dir, c, val) {
  c = cmd; k = 1
  if (c == "git") { if (args[1] != "mv") return; c = "mv"; k = 2 }
  n = 0; dd = 0; tdir = ""; script = 0; inpl = 0; dir = 0
  for (; k <= na; k++) {
    a = args[k]
    if (!dd && a == "--") { dd = 1; continue }
    if (!dd && a ~ /^-./) {
      if (a == "-t" || a == "--target-directory") { tdir = args[++k]; continue }
      if (a ~ /^--target-directory=/) { tdir = substr(a, 20); continue }
      if (c == "sed" && (a ~ /^-[nrEsuz]*[iI]/ || a ~ /^--in-place/)) inpl = 1
      # BSD sed -i .bak and -i '': the suffix is its own word. A word with a / is a file (GNU sed -i <file>).
      if (c == "sed" && a ~ /^-[nrEsuz]*[iI]$/ && k < na && args[k + 1] ~ /^\.[^\/]*$/) { k++; continue }
      if (c == "perl" && a ~ /^-[acnpstuvwlTUWXS0-9]*i/) inpl = 1
      if (c == "install" && a ~ /^-[a-zA-Z]*d/) dir = 1
      val = ((c, a) in VOPT) || (c == "perl" && a ~ /^-[a-zA-Z]*[eE]$/)   # the next word is its value
      if (c == "perl" && val || c == "sed" && a ~ /^(-e|-f|--expression|--file)/) script = 1   # the script is no file
      if (val) k++
      continue
    }
    if (a != "") op[++n] = a
  }
  if (c == "tee" || c == "touch") { for (k = 1; k <= n; k++) emit("W", op[k], "") }
  else if (c == "mkdir" || (c == "install" && dir)) { for (k = 1; k <= n; k++) emit("D", op[k], "") }
  else if (c == "sed" || c == "perl") { if (inpl) for (k = script ? 1 : 2; k <= n; k++) emit("W", op[k], "") }
  else if (c == "ln") {
    if (tdir != "") { for (k = 1; k <= n; k++) emit("L", tdir, op[k]) }
    else if (n == 1) emit("L", ".", op[1])
    else for (k = 1; k < n; k++) emit("L", op[n], op[k])
  } else if (c == "cp" || c == "mv" || c == "install") {
    if (tdir != "") { for (k = 1; k <= n; k++) emit("J", tdir, op[k]) }
    else if (n >= 2) { emit("W", op[n], ""); for (k = 1; k < n; k++) emit("J", op[n], op[k]) }
  }
}
