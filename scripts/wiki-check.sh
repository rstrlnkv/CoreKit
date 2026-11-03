#!/usr/bin/env bash
# wiki-check.sh — deterministic wiki checks (spec section 8.3, rules in reference/wiki.md).
#
# Usage: wiki-check.sh <project_dir> [--changed <path>...]
#   <project_dir>  the Core project folder: CLAUDE.md, docs/ (map docs/INDEX.md), code/
#
# Wiki pages are docs/**/*.md except docs/knowledge/, docs/standards/, docs/superpowers/
# and INDEX.md (the map is checked for links only).
#
# Checks (one line per failure, "wiki-check: <file>: <problem>", exit 1; silent and 0 when green):
#   missing front matter field <f>             page lacks title/description/status/files/related/updated
#   not in INDEX.md                            a page on disk the map does not link
#   INDEX.md links missing page <target>       a map link to a page that does not exist
#   broken link <target>                       a Markdown link whose file does not exist
#   broken reference § <heading> (...)         "docs/<page>.md § <heading>" with no such page/heading
#   duplicate heading <h>                      the same "## " heading twice in one page
#   page over 8 KB without ## headings
#   drift: <code path> changed, page not updated      (only with --changed)
# <file> is relative to docs/ ("features/login.md"); CLAUDE.md is printed as "../CLAUDE.md".
# Links and references are read in docs/ pages, INDEX.md and CLAUDE.md, outside code fences;
# links ignore other schemes (http:, mailto:...) and pure "#anchor"; "page.md#anchor" checks
# the file only. A reference heading is the rest of the line, or the text up to the first
# backtick (so wrap a reference in backticks when prose follows it).
#
# --changed paths: code files as code-relative paths (what "git diff --name-only" prints in
# code/). A changed wiki page is passed as "../docs/<page>.md" (the unambiguous form) or as
# "docs/<page>.md"; both mean docs/<page>.md of the project. So a code file that lives in a
# top-level docs/ folder of code/ cannot be told apart from a wiki page; it is taken as a page.
# A page's files: entries match a changed path exactly, or by prefix when the entry ends in "/".
#
# Exit: 0 green, 1 problems found, 2 usage error. Portable bash 3.2 + BSD awk.

set -u

usage() { echo "usage: wiki-check.sh <project_dir> [--changed <path>...]" >&2; exit 2; }

[ $# -ge 1 ] || usage
PROJ="$1"; shift
HAVE_CHANGED=0
if [ $# -gt 0 ]; then
  [ "$1" = "--changed" ] || usage
  HAVE_CHANGED=1; shift
fi
[ -d "$PROJ" ] || { echo "wiki-check: $PROJ: not a directory" >&2; exit 2; }
PROJ="$(cd "$PROJ" && pwd)"
DOCS="$PROJ/docs"
[ -d "$DOCS" ] || { echo "wiki-check: docs: missing docs/ directory"; exit 1; }

T="$(mktemp -d "${TMPDIR:-/tmp}/wiki-check.XXXXXX")" || exit 2
trap 'rm -rf "$T"' EXIT

# Wiki pages (docs-relative, one per line).
( cd "$DOCS" && find . -type f -name '*.md' | sed 's|^\./||' | LC_ALL=C sort ) |
while IFS= read -r p; do
  case "$p" in
    INDEX.md|knowledge/*|standards/*|superpowers/*) ;;
    *) printf '%s\n' "$p" ;;
  esac
done > "$T/pages"

# Changed paths: "C <code path>" or "P <docs-relative page>".
: > "$T/changed"
if [ "$HAVE_CHANGED" = 1 ]; then
  for a in "$@"; do
    a="${a#./}"
    case "$a" in
      ../docs/*) printf 'P %s\n' "${a#../docs/}" ;;
      docs/*)    printf 'P %s\n' "${a#docs/}" ;;
      ../*)      ;;                         # outside the project's code and docs
      *)         printf 'C %s\n' "$a" ;;
    esac
  done >> "$T/changed"
fi

cat > "$T/check.awk" <<'AWKEOF'
function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
function shq(s) { gsub(/'/, "'\\''", s); return "'" s "'" }
function report(file, msg) { print "wiki-check: " file ": " msg }
function exists(p) { return system("test -e " shq(p)) == 0 }

# Collapse "." and ".." and repeated slashes.
function norm(p,   n, parts, i, k, st, out, abs) {
  abs = (substr(p, 1, 1) == "/")
  n = split(p, parts, "/"); k = 0
  for (i = 1; i <= n; i++) {
    if (parts[i] == "" || parts[i] == ".") continue
    if (parts[i] == "..") {
      if (k > 0 && st[k] != "..") { k--; continue }
      if (abs) continue
    }
    st[++k] = parts[i]
  }
  out = ""
  for (i = 1; i <= k; i++) out = out (i > 1 ? "/" : "") st[i]
  return (abs ? "/" : "") out
}

# %XX -> character for ASCII (so "my%20page.md" works); other bytes stay as written.
function unpct(s,   out, i, h, v) {
  out = ""
  while ((i = index(s, "%")) > 0) {
    h = tolower(substr(s, i + 1, 2))
    if (h ~ /^[0-9a-f][0-9a-f]$/) {
      v = (index("0123456789abcdef", substr(h, 1, 1)) - 1) * 16 + index("0123456789abcdef", substr(h, 2, 1)) - 1
      if (v < 128 && v > 0) { out = out substr(s, 1, i - 1) sprintf("%c", v); s = substr(s, i + 3); continue }
    }
    out = out substr(s, 1, i); s = substr(s, i + 1)
  }
  return out s
}

function additem(v) {
  v = trim(v)
  if (v ~ /^".*"$/ || v ~ /^'.*'$/) v = substr(v, 2, length(v) - 2)
  v = trim(v)
  if (v == "") return
  nf++; flist[nf] = v
}
function flow(v,   n, parts, i) {
  sub(/^\[/, "", v); sub(/\][ \t]*$/, "", v)
  n = split(v, parts, ",")
  for (i = 1; i <= n; i++) additem(parts[i])
}
function fmline(l,   k, v) {
  if (l ~ /^[ \t]*#/) return
  if (l ~ /^[A-Za-z_][A-Za-z0-9_-]*[ \t]*:/) {
    k = l; sub(/[ \t]*:.*/, "", k)
    v = trim(substr(l, index(l, ":") + 1))
    has[k] = 1; val[k] = v; curkey = k
    if (k == "files" && v ~ /^\[/) flow(v)
    return
  }
  if (curkey == "files" && l ~ /^[ \t]*-[ \t]+/) { v = l; sub(/^[ \t]*-[ \t]+/, "", v); additem(v) }
}

# "## " headings of a file (outside code fences), cached.
function loadheads(path,   line, fence, t) {
  if (path in loaded) return
  loaded[path] = 1
  fence = 0
  while ((getline line < path) > 0) {
    if (line ~ /^[ \t]*(```|~~~)/) { fence = !fence; continue }
    if (!fence && line ~ /^## /) { t = trim(substr(line, 4)); heads[path SUBSEP t] = 1 }
  }
  close(path)
}

function checklink(raw,   t, c, rp, full) {
  if (raw == "") return
  if (raw ~ /^#/ || raw ~ /^[A-Za-z][A-Za-z0-9+.-]*:/) return
  t = raw
  c = index(t, "#"); if (c > 0) t = substr(t, 1, c - 1)
  c = index(t, "?"); if (c > 0) t = substr(t, 1, c - 1)
  if (t == "") return
  t = unpct(t)
  if (substr(t, 1, 1) == "/") { rp = norm(t); full = rp }
  else { rp = norm((fdir == "" ? "" : fdir "/") t); full = proj "/" rp }
  if (mode == "index" && rp ~ /^docs\//) linked[substr(rp, 6)] = 1
  if (exists(full)) return
  if (mode == "index" && t ~ /\.md$/) report(rel, "INDEX.md links missing page " raw)
  else report(rel, "broken link " raw)
}

function scanlinks(s,   i, e, rest, tgt, t) {
  gsub(/`[^`]*`/, "", s)
  while ((i = index(s, "](")) > 0) {
    rest = substr(s, i + 2)
    if (substr(rest, 1, 1) == "<") {
      e = index(rest, ">"); if (e == 0) break
      tgt = substr(rest, 2, e - 2); s = substr(rest, e + 1)
    } else {
      e = index(rest, ")"); if (e == 0) break
      tgt = substr(rest, 1, e - 1); s = substr(rest, e + 1)
      t = index(tgt, " \""); if (t > 0) tgt = substr(tgt, 1, t - 1)
    }
    checklink(trim(tgt))
  }
}

function scanrefs(s,   p, before, after, last, start, j, page, a, b, c, shown, pf) {
  while ((p = index(s, MARK)) > 0) {
    before = substr(s, 1, p - 1); after = substr(s, p + ml); s = after
    if (before !~ /[ \t]$/) continue
    sub(/[ \t]+$/, "", before); sub(/`$/, "", before)
    if (before !~ /\.md$/) continue
    last = 0; start = 0
    while ((j = index(substr(before, start + 1), "docs/")) > 0) { start += j; last = start }
    if (last == 0) continue
    page = substr(before, last)
    a = trim(after); b = a
    c = index(a, "`"); if (c > 0) b = trim(substr(a, 1, c - 1))
    if (a == "" || b == "") continue
    shown = (c > 0) ? b : a
    pf = proj "/" norm(page)
    if (!exists(pf)) { report(rel, "broken reference § " shown " (no such page " page ")"); continue }
    loadheads(pf)
    if (!((pf SUBSEP a) in heads) && !((pf SUBSEP b) in heads))
      report(rel, "broken reference § " shown " (no such heading in " page ")")
  }
}

BEGIN {
  mode = ENVIRON["WC_MODE"]; rel = ENVIRON["WC_REL"]; proj = ENVIRON["WC_PROJ"]
  fdir = ENVIRON["WC_FDIR"]; size = ENVIRON["WC_SIZE"] + 0
  changedf = ENVIRON["WC_CHANGED"]; pagesf = ENVIRON["WC_PAGES"]
  MARK = "§ "; ml = length(MARK)
  nc = 0
  while ((getline l < changedf) > 0) {
    if (substr(l, 1, 2) == "C ") { nc++; codechg[nc] = substr(l, 3); codeset[substr(l, 3)] = 1 }
    else if (substr(l, 1, 2) == "P ") pagechg[substr(l, 3)] = 1
  }
  close(changedf)
}

{
  line = $0; sub(/\r$/, "", line)
  if (NR == 1 && line ~ /^---[ \t]*$/) { infm = 1; hasfm = 1; next }
  if (infm) {
    if (line ~ /^---[ \t]*$/) { infm = 0; next }
    fmline(line); next
  }
  if (line ~ /^[ \t]*(```|~~~)/) { fence = !fence; next }
  if (fence) next
  if (line ~ /^## /) {
    h2++
    t = trim(substr(line, 4))
    if (mode == "page" && seenh[t]++ == 1) report(rel, "duplicate heading " t)
  }
  scanlinks(line)
  scanrefs(line)
}

END {
  if (mode == "page") {
    nreq = split("title description status files related updated", req, " ")
    for (i = 1; i <= nreq; i++) {
      f = req[i]
      blank = (f == "title" || f == "description" || f == "status" || f == "updated") && \
              (val[f] == "" || val[f] == "\"\"" || val[f] == "''")
      if (!hasfm || !(f in has) || blank) report(rel, "missing front matter field " f)
    }
    if (size > 8192 && h2 == 0) report(rel, "page over 8 KB without ## headings")
    if (!(rel in pagechg)) {
      for (i = 1; i <= nf; i++) {
        f = flist[i]
        isdir = (f ~ /\/$/)
        f = norm(f); if (isdir) f = f "/"
        if (isdir) { for (k = 1; k <= nc; k++) if (index(codechg[k], f) == 1) drift(codechg[k]) }
        else if (f in codeset) drift(f)
      }
    }
  }
  if (mode == "index") {
    while ((getline pg < pagesf) > 0) if (!(pg in linked)) report(pg, "not in INDEX.md")
    close(pagesf)
  }
}
function drift(c) { report(rel, "drift: " c " changed, page not updated") }
AWKEOF

# run_awk <mode> <display name> <file> <dir of file relative to project>
run_awk() {
  WC_MODE="$1" WC_REL="$2" WC_PROJ="$PROJ" WC_FDIR="$4" WC_SIZE="$(wc -c < "$3" | tr -d ' ')" \
  WC_CHANGED="$T/changed" WC_PAGES="$T/pages" awk -f "$T/check.awk" "$3"
}

OUT="$(
  if [ -f "$DOCS/INDEX.md" ]; then run_awk index INDEX.md "$DOCS/INDEX.md" docs
  else echo "wiki-check: INDEX.md: missing"; fi
  while IFS= read -r page; do
    d="$(dirname "$page")"; if [ "$d" = . ]; then d=docs; else d="docs/$d"; fi
    run_awk page "$page" "$DOCS/$page" "$d"
  done < "$T/pages"
  if [ -f "$PROJ/CLAUDE.md" ]; then run_awk claude ../CLAUDE.md "$PROJ/CLAUDE.md" ""; fi
)"

if [ -n "$OUT" ]; then printf '%s\n' "$OUT"; exit 1; fi
exit 0
