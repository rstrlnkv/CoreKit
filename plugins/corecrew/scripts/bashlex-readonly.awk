# scripts/bashlex-readonly.awk — the read-only checkers' part of guard-code.sh: what a Bash command
# would change. Used with scripts/bash-lex.awk (the tokenizer):
#   awk -f bash-lex.awk -f bashlex-readonly.awk
# Prints one line per finding:
#   P\t<path>   a path the command writes, makes, moves to or removes (redirect targets included)
#   X\t<what>   a change with no path to judge: git that changes the repo, sed -i, perl -i, patch
# A path that holds $ ` * ? [ { is not printed (it cannot be judged here); /dev/... is never a change.

BEGIN {
  CAP = 100; BADCH = "$`*?[{\t\002"
  split("tee touch mkdir cp mv rm rmdir ln install rsync truncate unlink shred chmod chown dd git sed gsed perl patch cd pushd popd", T, " ")
  for (k in T) TRACK[T[k]] = 1
  # git subcommands that change the work tree, the index, refs or a remote
  split("add commit push pull reset checkout switch restore stash merge rebase cherry-pick revert am apply rm mv clean init clone worktree tag notes submodule gc prune update-index update-ref", G, " ")
  for (k in G) GITW[G[k]] = 1
  # git options that take a value as the next word
  split("-C -c --git-dir --work-tree --namespace", GO, " "); for (k in GO) GITOPT[GO[k]] = 1
}
function classify(b) {
  if (b == "cd" || b == "pushd" || b == "popd") cdseen = 1
  return (b in TRACK) ? b : "?"
}
function on_out(w) { path(w) }
function on_in(w) { }
function on_subst(w) { }
function out(kind, a) {
  if (ne >= CAP) { full = 1; return }
  ne++; printf "%s\t%s\n", kind, a
}
function path(a,   q) {
  if (a == "" || index(a, "/dev/") == 1) return
  if (cdseen && substr(a, 1, 1) != "/" && a != "~" && index(a, "~/") != 1) return   # after cd a relative path is unknown
  for (q = 1; q <= length(BADCH); q++) if (index(a, substr(BADCH, q, 1))) return
  out("P", a)
}
function finalize(   k, a, dd, last, sub_, skip) {
  if (cmd == "?" || cmd == "" || cmd == "cd" || cmd == "pushd" || cmd == "popd") return
  if (cmd == "git") {
    skip = 0
    for (k = 1; k <= na; k++) {
      a = args[k]
      if (skip) { skip = 0; continue }
      if (a in GITOPT) { skip = 1; continue }
      if (substr(a, 1, 1) == "-") continue
      sub_ = a; break
    }
    if (sub_ in GITW) { out("X", "git " sub_); return }
    if (sub_ == "branch")
      for (k = k + 1; k <= na; k++) if (args[k] ~ /^-(d|D|m|M|c|C)$|^--(delete|move|copy|force)$/) { out("X", "git branch " args[k]); return }
    return
  }
  if (cmd == "sed" || cmd == "gsed" || cmd == "perl") {
    for (k = 1; k <= na; k++) if (args[k] ~ /^-[A-Za-z]*i/ || args[k] ~ /^--in-place/) { out("X", cmd " -i"); return }
    return
  }
  if (cmd == "patch") { out("X", "patch"); return }
  if (cmd == "dd") {
    for (k = 1; k <= na; k++) if (index(args[k], "of=") == 1) path(substr(args[k], 4))
    return
  }
  # cp, mv, ln, install, rsync: the destination (the last word that is not an option)
  if (cmd == "cp" || cmd == "mv" || cmd == "ln" || cmd == "install" || cmd == "rsync") {
    last = ""; dd = 0
    for (k = 1; k <= na; k++) { a = args[k]; if (!dd && a == "--") { dd = 1; continue }; if (!dd && substr(a, 1, 1) == "-") continue; last = a }
    if (last != "") path(last)
    if (cmd == "mv") for (k = 1; k <= na; k++) { a = args[k]; if (a != last && substr(a, 1, 1) != "-") path(a) }   # the sources go too
    return
  }
  # tee touch mkdir rm rmdir truncate unlink shred chmod chown: every word that is not an option
  dd = 0
  for (k = 1; k <= na && !full; k++) {
    a = args[k]
    if (!dd && a == "--") { dd = 1; continue }
    if (!dd && substr(a, 1, 1) == "-") continue
    if ((cmd == "chmod" || cmd == "chown") && k == 1) continue   # the mode or owner
    if (cmd == "truncate" && args[k - 1] ~ /^-s$/) continue
    path(a)
  }
}
