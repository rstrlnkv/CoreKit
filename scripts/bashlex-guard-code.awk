# scripts/bashlex-guard-code.awk — the guard-code.sh part of the Bash judging: finds the targets of
# redirects and of tee, touch, mkdir, cp and mv. Used with scripts/bash-lex.awk (the tokenizer):
#   awk -f bash-lex.awk -f bashlex-guard-code.awk
# Prints "<kind>\t<path>[\t<name>]": W a file written, D a directory made (mkdir), J a destination (cp/mv)
# that may be a directory: <name> is a source's name.

BEGIN {
  CAP = 100; BADCH = "$`*?[{\t\002"
  split("tee touch mkdir cp mv cd pushd popd", T, " "); for (k in T) TRACK[T[k]] = 1
}
# classify(b) — the commands whose arguments are looked at; cd, pushd and popd also make a relative path unknown
function classify(b) {
  if (b == "cd" || b == "pushd" || b == "popd") cdseen = 1
  return (b in TRACK) ? b : "?"
}
function on_out(w) { emit("W", w, "") }
function on_in(w) { }   # the file read by "< file" is not written
function emit(kind, a, b) {
  if (nomore) return
  if (ne >= CAP) { full = 1; return }
  if (a == "" || index(a, "/dev/") == 1) return
  if (cdseen && substr(a, 1, 1) != "/" && a != "~" && index(a, "~/") != 1) return   # after cd a relative path is unknown
  for (q = 1; q <= length(BADCH); q++) if (index(a, substr(BADCH, q, 1))) return
  ne++
  if (b == "") printf "%s\t%s\n", kind, a; else printf "%s\t%s\t%s\n", kind, a, b
  if (ne >= CAP) full = 1
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
}
