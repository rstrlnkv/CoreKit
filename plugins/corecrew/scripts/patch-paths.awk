# scripts/patch-paths.awk — the file paths of a Codex apply_patch text. Used by guard-code.sh and
# guard-secrets.sh (through lib.sh patch_paths):
#   LC_ALL=C awk -f patch-paths.awk
# stdin: the patch text (the tool input "command" of apply_patch). A patch handed to the shell is not read here: the guards refuse it.
# Prints "<kind>\t<path>":
#   W a file written: Add File, Update File without Move to, the destination of Move to
#   S the source of an Update File that has a Move to
#   D a file deleted (kept for completeness: the guards do not consume it)
#   X the text could not be read as a patch: no Begin Patch, an unknown "***" line where a header or a
#     hunk line is expected, or a header ("*** Add File:" ...) after other text on its line
#   C more than 100 paths ("too many files"); printed once, after the 100th path, and no further path
#     is printed: the guards refuse such a patch
# Grammar (codex-rs/apply-patch, rust-v0.166.0): headers are matched on the trimmed line, except inside an
# Update hunk, where a header must start at column 0 (an indented one is context); in an Add body a line
# starting with "+" is content. Lines and paths are trimmed as Rust trim() does (Codex): ASCII space, tab, VT,
# FF, CR and the UTF-8 sequences of U+0085, U+00A0, U+1680, U+2000-200A, U+2028, U+2029, U+202F, U+205F,
# U+3000 (matched as bytes; run under LC_ALL=C). A path is everything after "<header>: " so trimmed,
# then with every TAB and CR inside it deleted (Codex does the same: "do<TAB>cs/a.md" writes docs/a.md; checked with
# the CLI, `codex --codex-run-as-apply-patch`); quotes, "~" and glob characters are not interpreted here. Text outside Begin..End is ignored (heredoc
# wrapper lines). At most 100 paths are printed, then one C line. The script never exits non-zero for odd text.

BEGIN {
  CAP = 100; state = "out"; n = 0; begun = 0; pending = ""; capped = 0
  split("\302\205 \302\240 \341\232\200 \342\200\200 \342\200\201 \342\200\202 \342\200\203 \342\200\204 \342\200\205 \342\200\206 \342\200\207 \342\200\210 \342\200\211 \342\200\212 \342\200\250 \342\200\251 \342\200\257 \342\201\237 \343\200\200", L, " ")
  for (k in L) WS[L[k]] = 1
}
function hasmk(s) { return s ~ /\*\*\* (Add File|Update File|Delete File|Move to|Begin Patch|End Patch)/ }
function asp(c) { return c == " " || c == "\t" || c == "\013" || c == "\014" || c == "\r" }
function wlen(s,   c) {
  c = substr(s, 1, 1)
  if (asp(c)) return 1
  if (c < "\302") return 0
  if (substr(s, 1, 2) in WS) return 2
  if (substr(s, 1, 3) in WS) return 3
  return 0
}
function wrlen(s,   m) {
  m = length(s)
  if (m >= 1 && asp(substr(s, m, 1))) return 1
  if (m >= 2 && (substr(s, m - 1, 2) in WS)) return 2
  if (m >= 3 && (substr(s, m - 2, 3) in WS)) return 3
  return 0
}
function trim(s,   k) {
  while ((k = wlen(s)) > 0) s = substr(s, k + 1)
  while ((k = wrlen(s)) > 0) s = substr(s, 1, length(s) - k)
  return s
}
function emit(kind, p) {
  if (n >= CAP) { if (!capped) { capped = 1; printf "C\ttoo many files\n" }; return }
  n++; printf "%s\t%s\n", kind, p
}
function flush() { if (pending != "") { emit("W", pending); pending = "" } }
function bad() { xd = 1; printf "X\tunreadable\n" }
function pathof(t, prefix,   p) { p = trim(substr(t, length(prefix) + 1)); gsub(/[\t\r]/, "", p); return p }
{
  line = $0; sub(/\r$/, "", line)
  if (state == "out") {
    if (trim(line) == "*** Begin Patch") {
      state = "hdr"; begun = 1
    } else if (!xd && hasmk(line)) bad()
    next
  }
  c1 = substr(line, 1, 1)
  t = line
  if (state != "upd") t = trim(t)
  if (state == "add" && c1 == "+") next
  if (substr(t, 1, 3) != "***") {
    if (!(state == "upd" && (c1 == " " || c1 == "+" || c1 == "-" || c1 == "@")) && hasmk(t)) bad()
    next
  }
  if (state == "upd" && trim(t) == "*** End of File") next
  if (t ~ /^\*\*\* End Patch/) { flush(); state = "out"; next }
  if (t ~ /^\*\*\* Environment ID:/) next
  if (t ~ /^\*\*\* Add File:/) { flush(); p = pathof(t, "*** Add File:"); if (p != "") emit("W", p); else bad(); state = "add"; next }
  if (t ~ /^\*\*\* Delete File:/) { flush(); p = pathof(t, "*** Delete File:"); if (p != "") emit("D", p); else bad(); state = "del"; next }
  if (t ~ /^\*\*\* Update File:/) { flush(); pending = pathof(t, "*** Update File:"); if (pending == "") bad(); state = "upd"; next }
  if (state == "upd" && pending != "" && t ~ /^\*\*\* Move to:/) {
    p = pathof(t, "*** Move to:")
    if (p != "") { emit("S", pending); emit("W", p); pending = "" }
    else bad()
    next
  }
  bad()
}
END {
  flush()
  if (!begun && !xd) bad()
}
