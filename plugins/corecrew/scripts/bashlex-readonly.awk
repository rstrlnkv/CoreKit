# scripts/bashlex-readonly.awk — the read-only checkers' part of guard-code.sh: what a Bash command
# would change. Used with scripts/bash-lex.awk (the tokenizer):
#   awk -f bash-lex.awk -f bashlex-readonly.awk
# Prints one line per finding:
#   P\t<path>   a path the command writes, makes, moves to or removes (redirect targets included;
#               a cp/mv into a folder also gives <folder>/<source name>); relative to the hook's cwd
#   X\t<what>   a change with no path to judge: git that changes the repo, an in-place edit, ln,
#               find -delete/-exec, xargs with a writer, a download or unpack into the current folder,
#               sed w or -f, git push / global config / --git-dir, a relative write after any cd,
#               a command this pass could not read whole
# It fails closed where guard-code fails open: these agents should change nothing, so what cannot be
# judged is a finding. A path that holds $ ` * ? [ { cannot be judged and is not printed (a write to
# "$TMPDIR/log" is the usual case). Programs a command runs (a build, python -c, node -e) are not seen.

BEGIN {
  CAP = 100; BADCH = "$`*?[{\t\002"
  split("tee touch mkdir cp mv rm rmdir ln install rsync truncate unlink shred chmod chown dd git sed gsed perl patch find xargs sort curl wget tar unzip cd pushd popd", T, " ")
  for (k in T) TRACK[T[k]] = 1
  # commands that change files whatever their arguments, when xargs or find -exec runs them
  split("rm rmdir mv cp touch mkdir tee ln chmod chown truncate unlink shred install rsync dd patch sed perl git sh bash zsh", W, " ")
  for (k in W) WRITER[W[k]] = 1
  # git subcommands that always change the work tree, the index, refs or a remote
  split("add commit push pull reset checkout switch restore merge rebase cherry-pick revert am rm mv clean init fetch gc prune update-index update-ref replace filter-branch", G, " ")
  for (k in G) GITW[G[k]] = 1
  split("-C -c --git-dir --work-tree --namespace", GO, " "); for (k in GO) GITOPT[GO[k]] = 1
  cdunk = 0
}
function classify(b) { return (b in TRACK) ? b : "?" }
function on_out(w) { path(w) }
function on_in(w) { }
# on_subst(w) — a $(...) or backtick body inside double quotes is a command line too: queue it
function on_subst(w,   n, p, c, depth, st, q) {
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
END { if (nomore || capped) printf "X\t%s\n", "a command this check could not read whole" }
function out(kind, a) {
  if (ne >= CAP) { capped = 1; full = 1; return }
  ne++; printf "%s\t%s\n", kind, a
}
function judgeable(a,   q) {
  for (q = 1; q <= length(BADCH); q++) if (index(a, substr(BADCH, q, 1))) return 0
  return 1
}
function abs_(a) { return substr(a, 1, 1) == "/" || a == "~" || index(a, "~/") == 1 }
function path(a) {
  if (a == "" || a == "-" || index(a, "/dev/") == 1) return
  if (!judgeable(a)) return
  if (!abs_(a)) {
    if (cdunk) { out("X", "a relative write after cd (write to an absolute temp path instead): " a); return }
  }
  out("P", a)
}
# cd, pushd, popd: from here the folder of a relative path is unknown. Tracking it is not safe:
# `(cd /tmp); rm x` and `cd /tmp | rm x` run rm where the command started.
function do_cd() { cdunk = 1 }
# nonopt(n) — the n-th word that is not an option
function nonopt(n,   k, c) {
  c = 0
  for (k = 1; k <= na; k++) if (substr(args[k], 1, 1) != "-") { c++; if (c == n) return args[k] }
  return ""
}
function has(re,   k) { for (k = 1; k <= na; k++) if (args[k] ~ re) return 1; return 0 }
# after(opt) — the word after an option given as its own word, or the value of --opt=value / -oVALUE
function after(short, long,   k, a) {
  for (k = 1; k <= na; k++) {
    a = args[k]
    if ((short != "" && a == short) || (long != "" && a == long)) return (k < na ? args[k + 1] : "")
    if (long != "" && index(a, long "=") == 1) return substr(a, length(long) + 2)
    if (short != "" && length(a) > 2 && index(a, short) == 1 && substr(a, 2, 1) != "-") return substr(a, 3)
  }
  return "\001"
}
function do_git(   k, a, skip, sub_, gc, rest, nn, ch) {
  skip = 0; sub_ = ""; gc = ""
  for (k = 1; k <= na; k++) {
    a = args[k]
    if (skip) { if (args[k - 1] == "-C") gc = a; skip = 0; continue }
    if (a in GITOPT) { skip = 1; continue }
    if (substr(a, 1, 1) == "-") continue
    sub_ = a; break
  }
  rest = ""; nn = 0
  for (k = k + 1; k <= na; k++) { rest = rest " " args[k]; if (substr(args[k], 1, 1) != "-") nn++ }
  if (sub_ == "") return
  # what reaches beyond the repo -C names: a remote, the user's or system config, another git dir
  if (sub_ == "push" || sub_ == "worktree" && rest !~ /^ list( |$)/) { out("X", "git " sub_); return }
  if (sub_ == "config" && rest ~ / --(global|system|file)( |=|$)| -f( |$)/) { out("X", "git config outside the repo"); return }
  for (k = 1; k <= na; k++) if (args[k] ~ /^--(git-dir|work-tree)(=|$)/) { out("X", "git " args[k]); return }
  if (rest ~ /(^| )--output(=| |$)/) { out("X", "git " sub_ " --output"); return }
  if (sub_ == "clone") { if (nn >= 2) path(nonopt_after(sub_, 2)); else out("X", "git clone into the current folder"); return }
  ch = 0
  if (sub_ in GITW) ch = 1
  else if (sub_ == "branch") ch = (rest ~ / -(d|D|m|M|c|C|f|u)( |$)| --(delete|move|copy|force|set-upstream-to|unset-upstream|edit-description)/) || (nn > 0 && rest !~ / (-l|--list|-a|--all|-r|--remotes|--contains|--no-contains|--merged|--no-merged|--points-at|--show-current)( |$)/)
  else if (sub_ == "tag") ch = nn > 0 && rest !~ / (-l|--list|-n[0-9]*|--contains|--no-contains|--merged|--no-merged|--points-at|-v|--verify)( |$)/
  else if (sub_ == "stash") ch = rest !~ /^ (list|show)( |$)/
  else if (sub_ == "worktree") ch = rest !~ /^ list( |$)/
  else if (sub_ == "submodule") ch = rest != "" && rest !~ /^ (status|summary)( |$)/
  else if (sub_ == "notes") ch = rest != "" && rest !~ /^ (list|show)( |$)/
  else if (sub_ == "remote") ch = rest != "" && rest !~ /^ (-v|--verbose|show|get-url)( |$)/
  else if (sub_ == "apply") ch = rest !~ / --(check|stat|numstat|summary)( |$)/
  else if (sub_ == "config") ch = rest ~ / --(unset|unset-all|add|replace-all|rename-section|remove-section|edit)( |$)| -e( |$)/ || (nn >= 2 && rest !~ / --(get|get-all|get-regexp|list)( |$)| -l( |$)/)
  if (!ch) return
  # git -C <folder>: the change happens there; a temp folder is fine
  if (gc != "") path(gc "/.")
  else out("X", "git " sub_)
}
# nonopt_after(sub, n) — the n-th non-option word after the git subcommand
function nonopt_after(s, n,   k, c, seen) {
  c = 0; seen = 0
  for (k = 1; k <= na; k++) {
    if (!seen) { if (args[k] == s) seen = 1; continue }
    if (substr(args[k], 1, 1) != "-") { c++; if (c == n) return args[k] }
  }
  return ""
}
function finalize(   k, a, dd, last, v, first, m, q, c) {
  if (cmd == "?" || cmd == "") return
  if (cmd == "cd" || cmd == "pushd" || cmd == "popd") { do_cd(); return }
  if (cmd == "git") { do_git(); return }
  if (cmd == "ln") { out("X", "ln (a link can lead a later write anywhere)"); return }
  if (cmd == "patch") { out("X", "patch"); return }
  if (cmd == "sed" || cmd == "gsed") {
    for (k = 1; k <= na; k++) {
      a = args[k]
      if (a ~ /^-[A-Za-z]*i/ || index(a, "--in-place") == 1) { out("X", cmd " -i"); return }
      if (a ~ /^-[A-Za-z]*f$/ || index(a, "--file") == 1) { out("X", cmd " -f (a script this check cannot read)"); return }
      # the w command and the s///w flag write a file: "w out", "1w out", "p;w out", "s/a/b/w out"
      if (substr(a, 1, 1) != "-" && a ~ /(^|[;{}\/0-9$])[ \t]*[wW][ \t]+[^ \t]/) { out("X", cmd " w (writes a file)"); return }
    }
    return
  }
  if (cmd == "perl") {
    for (k = 1; k <= na; k++) {
      a = args[k]
      if (a ~ /^-[eE]/) return                     # the code starts: no more options
      if (a ~ /^-[MImx]/) continue                 # -MModule, -Ilib: their letters are names
      if (a ~ /^-[A-Za-z]*i/) { out("X", "perl -i"); return }
    }
    return
  }
  if (cmd == "find") {
    if (has("^-(delete|exec|execdir|ok|okdir|fprint|fprint0|fprintf|fls)$")) out("X", "find with -delete or -exec")
    return
  }
  if (cmd == "xargs") {
    for (k = 1; k <= na; k++) {
      a = args[k]
      if (a ~ /^-[IdEnLPsa]$/ || a ~ /^--(replace|delimiter|eof|max-args|max-lines|max-procs|max-chars|arg-file)$/) { k++; continue }
      if (substr(a, 1, 1) == "-") continue
      m = a; sub(/.*\//, "", m)
      if (m in WRITER) out("X", "xargs " m)
      return
    }
    return
  }
  if (cmd == "sort") { v = after("-o", "--output"); if (v != "\001") path(v); return }
  if (cmd == "curl") {
    for (k = 1; k <= na; k++) {
      a = args[k]
      if (a ~ /^--(output|dump-header|cookie-jar|trace|trace-ascii|stderr|libcurl)$/) { if (k < na) path(args[++k]); continue }
      if (a ~ /^--(output|dump-header|cookie-jar|trace|trace-ascii|stderr|libcurl)=/) { v = a; sub(/^[^=]*=/, "", v); path(v); continue }
      if (a ~ /^--(remote-name|remote-name-all|output-dir|remote-header-name)(=|$)/) { out("X", "curl " a " (a download into the current folder)"); continue }
      if (a ~ /^--/ || a !~ /^-./) continue
      # a group of short options (-sSLo FILE, -sSLoFILE): letters up to the first that takes a value
      for (q = 2; q <= length(a); q++) {
        c = substr(a, q, 1)
        if (c == "o" || c == "D" || c == "c") {
          v = substr(a, q + 1); if (v == "" && k < na) v = args[++k]
          path(v); break
        }
        if (c == "O") { out("X", "curl -O (a download into the current folder)"); break }
        if (index("AbCdeEFHKmPQrtTuUwxXyYz", c)) { if (q == length(a)) k++; break }
      }
    }
    return
  }
  if (cmd == "wget") {
    v = after("-O", "--output-document")
    if (v == "\001") for (k = 1; k <= na; k++) if (args[k] ~ /^-[A-Za-z]*O-$/) v = "-"
    if (v == "-") return
    if (v != "\001") { path(v); return }
    v = after("-P", "--directory-prefix"); if (v != "\001") { path(v); return }
    out("X", "wget (a download into the current folder)"); return
  }
  if (cmd == "tar") {
    first = (na >= 1 && substr(args[1], 1, 1) != "-") ? args[1] : ""; m = ""   # the old style: letters first
    if (has("^(-[A-Za-z]*x[A-Za-z]*|--extract|--get)$") || (first ~ /^[A-Za-z]*x[A-Za-z]*$/ && first !~ /\./)) m = "x"
    else if (has("^(-[A-Za-z]*[cru][A-Za-z]*|--create|--append|--update)$") || (first ~ /^[A-Za-z]*[cru][A-Za-z]*$/ && first !~ /\./)) m = "c"
    if (m == "x") { v = after("-C", "--directory"); if (v != "\001") path(v); else out("X", "tar x (unpacks into the current folder)") }
    if (m == "c") { v = after("-f", "--file"); if (v != "\001") path(v); else out("X", "tar c") }
    return
  }
  if (cmd == "unzip") {
    if (has("^-[A-Za-z]*[ltvZ][A-Za-z]*$")) return
    v = after("-d", ""); if (v != "\001") path(v); else out("X", "unzip (unpacks into the current folder)")
    return
  }
  if (cmd == "dd") {
    for (k = 1; k <= na; k++) if (index(args[k], "of=") == 1) path(substr(args[k], 4))
    return
  }
  # cp, mv, install, rsync: the destination (the last word that is not an option); mv also its sources
  if (cmd == "cp" || cmd == "mv" || cmd == "install" || cmd == "rsync") {
    last = ""; dd = 0
    for (k = 1; k <= na; k++) { a = args[k]; if (!dd && a == "--") { dd = 1; continue }; if (!dd && substr(a, 1, 1) == "-") continue; last = a }
    if (last != "") path(last)
    # a destination folder: the file lands at <folder>/<source name>, which may be a link elsewhere
    dd = 0
    if (last != "") for (k = 1; k <= na; k++) {
      a = args[k]; if (!dd && a == "--") { dd = 1; continue }; if (!dd && substr(a, 1, 1) == "-") continue
      if (a == last) continue
      v = a; sub(/\/+$/, "", v); sub(/.*\//, "", v)
      if (v != "" && v != "." && v != "..") path(last "/" v)
    }
    if (cmd == "mv") for (k = 1; k <= na; k++) { a = args[k]; if (a != last && substr(a, 1, 1) != "-") path(a) }
    return
  }
  # tee touch mkdir rm rmdir truncate unlink shred chmod chown: every word that is not an option
  # (chmod and chown: after the mode or owner word; truncate: after the size)
  dd = 0; first = (cmd == "chmod" || cmd == "chown") ? 1 : 0
  for (k = 1; k <= na && !full; k++) {
    a = args[k]
    if (!dd && a == "--") { dd = 1; continue }
    if (!dd && substr(a, 1, 1) == "-" && a !~ /^-[rwxXst]+$/) { if (cmd == "truncate" && (a == "-s" || a == "--size")) k++; continue }
    if (first) { first = 0; continue }
    path(a)
  }
}
