# scripts/bashlex-guard-code.awk — guard-code.sh's plain reading of a Bash command: the files it would write.
# Standalone (it does not use bash-lex.awk). It is built for honest mistakes (ADR 009), not against evasion: it
# reads words, quotes, comments, heredoc bodies, redirects and statement separators, and nothing more. What it
# does not follow is the LIMIT list in the guard-code.sh header.
# Input: the command with newlines turned into \002 (tr '\n\r' '\002 '). Output, each line at most once:
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
  NL = "\002"; CAP = 100; MORE = 100; MAXW = 4096; BAD = "$`*?[{\t\001\002"
  split("tee touch mkdir cp mv ln install sed perl git cd pushd popd", t, " "); for (k in t) TRACK[t[k]] = 1
  split("sudo doas command builtin exec nohup time env nice timeout gtimeout stdbuf setsid caffeinate ionice unbuffer if then else elif do while until ! { }", t, " ")
  for (k in t) WRAP[t[k]] = 1
  split("docs .claude claude.md claude.local.md agents.md", t, " "); for (k in t) INTERNAL[t[k]] = 1
  # options that take the next word as their value
  vopt("touch", "-t -d -r --date --reference"); vopt("mkdir", "-m --mode"); vopt("install", "-m -o -g -S --mode --owner --group --suffix")
  vopt("cp", "-S --suffix"); vopt("mv", "-S --suffix"); vopt("ln", "-S --suffix"); vopt("sed", "-e -f -l --expression --file")
}
function vopt(c, list,   n, l, x) { n = split(list, l, " "); for (x = 1; x <= n; x++) VOPT[c, l[x]] = 1 }

{ text = (NR == 1 ? "" : text "\n") $0 }
END { lex() }

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

# --- one command is complete: cmd and args[1..na]
function finalize(   k, a, n, op, dd, tdir, script, inpl, dir, c, val) {
  # the leading `cd <absolute folder>` ended by && ; or a newline: the folder the relative targets after it are in
  if (cmd == "cd" && nstmt == 0 && !nosimple && na == 1 && args[1] ~ /^\// && plain(args[1]) && (sep == "&&" || sep == ";" || sep == "nl")) {
    cdbase = args[1]; sub(/\/+$/, "", cdbase); cdseen = 0
  }
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
      if (c == "sed" && a ~ /^-[nrEsuz]*[iI]$/ && k < na && (args[k + 1] == "" || args[k + 1] ~ /^\.[^\/]*$/)) { k++; continue }
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
function stmt_end() {
  finalize()
  if (cmd != "") nstmt++
  split("", args); na = 0; cmd = ""; wrapped = 0; wskip = 0; want = ""; dup = 0; sep = ""
}

# --- words
function add(ch) { if (wl >= MAXW) wbad = 1; else { word = word ch; wl++ } }
function endword(   w, b) {
  if (!inword) return
  w = wbad ? "\001" : word
  b = wq; inword = 0; word = ""; wl = 0; wbad = 0; wq = 0
  if (want == "out") { want = ""; if (!(dup && w ~ /^([0-9]+-?|-)$/)) emit("W", w, ""); dup = 0; return }
  if (want == "skip") { want = ""; return }
  if (want == "hd") { want = ""; hd[++hdn] = w; hds[hdn] = hdstrip; return }
  if (cmd == "") {
    if (!b && w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) return          # VAR=value before the command
    if (wrapped) {                                               # sudo -u x, nice -n 5, timeout 5, env -i
      if (wskip) { wskip = 0; return }
      if (w ~ /^-/) { if (w ~ /^-[ugnskCc]$/) wskip = 1; return }
      if (w ~ /^[0-9.]+[smhd]?$/) return
    }
    b = w; sub(/.*\//, "", b)
    if (b in WRAP) { wrapped = 1; return }
    if (b == "cd" || b == "pushd" || b == "popd") cdseen = 1
    cmd = (b in TRACK) ? b : "?"
    return
  }
  if (cmd != "?") args[++na] = w
}
# fdword — a redirect starts: a word of digits right before it is the descriptor (2>), not an argument
function fdword() {
  if (inword && !wq && word ~ /^[0-9]+$/) { inword = 0; word = ""; wl = 0 } else endword()
}

# --- heredocs: the bodies of the heredocs started on the line that just ended are skipped
function skip_bodies(   k, j, line, found, x) {
  for (k = 1; k <= hdn; k++) {
    for (found = 0; i <= len && !found; i = j + 1) {
      for (j = i; j <= len && C[j] != NL; j++) ;
      line = ""
      if (j - i <= MAXW) for (x = i; x < j; x++) line = line C[x]
      if (hds[k]) sub(/^\t+/, "", line)
      found = (line == hd[k])
    }
  }
  hdn = 0
}
# dquote — a double-quoted string from C[i]. A heredoc inside it ("$(cat <<'EOF' ... EOF)", the commit message
# idiom) has its body skipped, so a stray quote there cannot flip the quoting.
function dquote(   j, d, p, q, k, dl, st) {
  inword = 1; wq = 1
  for (j = i + 1; j <= len && C[j] != "\""; ) {
    d = C[j]
    if (d == "\\" && C[j + 1] == NL) { j += 2; continue }
    if (d == "\\" && index("\"\\$`", C[j + 1])) { add(C[j + 1]); j += 2; continue }
    if (d == NL && hdn) { i = j + 1; skip_bodies(); j = i; continue }
    if (d == "<" && C[j + 1] == "<" && C[j + 2] != "<") {
      p = j + 2; st = 0; dl = ""
      if (C[p] == "-") { st = 1; p++ }
      q = C[p]; if (q == "'" || q == "\"") p++; else q = ""
      for (k = p; k <= len && C[k] ~ /[A-Za-z0-9_]/; k++) dl = dl C[k]
      if (dl != "" && (q == "" || C[k] == q)) { hd[++hdn] = dl; hds[hdn] = st; j = k + (q != ""); continue }
    }
    add(d); j++
  }
  i = j + 1
}

function lex(   c) {
  len = split(text, C, ""); i = 1
  while (i <= len) {
    c = C[i]
    if (c == " " || c == "\t") { endword(); i++ }
    else if (c == NL) { endword(); sep = "nl"; stmt_end(); i++; if (hdn) skip_bodies() }
    else if (c == "#" && !inword) { while (i <= len && C[i] != NL) i++ }
    else if (c == "\\") { if (C[i + 1] != NL) { add(C[i + 1]); inword = 1; wq = 1 }; i += 2 }
    else if (c == "'") { inword = 1; wq = 1; for (i++; i <= len && C[i] != "'"; i++) add(C[i]); i++ }
    else if (c == "\"") dquote()
    else if (c == ";" || c == "|") { endword(); sep = c; stmt_end(); i++ }
    else if (c == "(" || c == ")" || c == "`") { endword(); sep = c; nosimple = 1; stmt_end(); i++ }
    else if (c == "&") {
      endword(); i++
      if (C[i] == ">") { i++; if (C[i] == ">") i++; want = "out" }
      else { sep = "&"; if (C[i] == "&") { i++; sep = "&&" }; stmt_end() }
    } else if (c == ">") {                                       # > >> >| >& (>( is a process substitution)
      fdword(); i++
      if (C[i] == "(") continue
      if (C[i] == ">" || C[i] == "|") i++
      if (C[i] == "&") { i++; dup = 1 }
      want = "out"
    } else if (c == "<") {                                       # < <> <& <<< << <<- (<( is a process substitution)
      fdword(); i++
      if (C[i] == "(") continue
      if (C[i] == ">") { i++; want = "out"; continue }
      if (C[i] == "<" && C[i + 1] == "<") { i += 2; want = "skip"; continue }
      if (C[i] == "<") { i++; hdstrip = 0; if (C[i] == "-") { hdstrip = 1; i++ }; want = "hd"; continue }
      if (C[i] == "&") i++
      want = "skip"
    } else { add(c); inword = 1; i++ }
  }
  endword(); stmt_end()
}
