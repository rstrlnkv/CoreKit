#!/usr/bin/env bash
# wiki-check.sh — deterministic wiki checks (rules in reference/wiki.md).
#
# Usage: wiki-check.sh <project_dir> [--changed <path>...]
#   <project_dir>  the Core project folder <Core>/<name>: CLAUDE.md, docs/ (map docs/INDEX.md).
#                  The code lives elsewhere (beside the Core, or in the old layout in code/).
#
# Wiki pages are what wiki-pages.sh lists (docs/**/*.md except INDEX.md, knowledge/, standards/,
# superpowers/, .obsidian/). A page's name is its file name without ".md".
#
# Checks (one line per failure, "wiki-check: <file>: <problem>", exit 1; silent and 0 when green):
#   missing front matter field <f>             type/status/description/files/related/updated absent,
#                                              or type/status/description/updated empty
#   unknown front matter field <f>             a key beyond those six (the wiki allows exactly six)
#   bad type: <v>                              not brief architecture decision feature spec plan glossary
#   bad status: <v>                            not draft active done superseded
#   bad updated: <v>                           not YYYY-MM-DD
#   description over 80 chars                 counted in characters, surrounding quotes removed
#   description not one line                  the value starts with > or | (a folded or literal block)
#   related is not a wikilink: <item>          a related: item that is not [[...]] ([] passes)
#   duplicate page name <name>                 on each later page (sorted path order) with a taken name
#   broken wikilink [[<target>]]               no such page/file, or no such heading (alias dropped)
#   use a wikilink: <target>                   a Markdown link from a page to a wiki page
#   broken link <target>                       a Markdown link whose file does not exist
#   unclosed front matter                      opening --- without a closing ---
#   duplicate heading <h>                      the same "## " heading twice in one page
#   page over 8 KB without ## headings
#   INDEX.md stale                             on INDEX.md: "wiki-index.sh --check" fails
#   drift: <code path> changed, page not updated      (only with --changed)
# Two lines stand alone: "wiki-check: INDEX.md: missing" (there is no docs/INDEX.md; the other
# checks still run) and "wiki-check: docs: missing docs/ directory" (exit 1, nothing else checked).
# <file> is relative to docs/ ("features/login.md"); CLAUDE.md is printed as "../CLAUDE.md".
# Pages are read for wikilinks (body and the related: field) and Markdown links; CLAUDE.md for
# Markdown links only; all outside code fences and `inline code`. Markdown links ignore other
# schemes (http:, mailto:...) and pure "#anchor"; "page.md#anchor" checks the file only.
# A wikilink [[t]], [[t#h]], [[t|alias]] or ![[t]] resolves: t with a "/" to docs/t.md or the file
# docs/t; t without one to the page named t, else a file named t anywhere under docs/; an empty
# t to the page itself. h is the exact text of a # to ###### heading of that page, outside fences.
#
# --changed paths: code files as code-root-relative paths (what "git diff --name-only" prints in
# the code root). A changed wiki page is passed as "<project_dir>/docs/<page>.md" (absolute, the
# unambiguous form), "../docs/<page>.md" or "docs/<page>.md"; all mean docs/<page>.md of the project. So a code file that lives in a
# top-level docs/ folder of code/ cannot be told apart from a wiki page; it is taken as a page.
# (An absolute path under another folder is a code path, not a page.) Any other "../<path>" lies
# outside the project's code and docs and is ignored.
# A page's files: entries match a changed path exactly, or by prefix when the entry ends in "/".
#
# Exit: 0 green, 1 problems found, 2 usage or internal error (e.g. awk failed: never "green"). Portable bash 3.2 + BSD awk.

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

HERE="$(cd "$(dirname "$0")" && pwd)"

# Wiki pages (docs-relative, one per line) and every file under docs/ (wikilinks may name any).
"$HERE/wiki-pages.sh" "$DOCS" > "$T/pages" || exit 2
( set -o pipefail; cd "$DOCS" && find . -type f | sed 's|^\./||' | LC_ALL=C sort ) > "$T/files" || exit 2

# Changed paths: "C <code path>" or "P <docs-relative page>".
: > "$T/changed"
if [ "$HAVE_CHANGED" = 1 ]; then
  for a in "$@"; do
    a="${a#./}"
    case "$a" in
      "$PROJ"/docs/*) printf 'P %s\n' "${a#"$PROJ"/docs/}" ;;
      ../docs/*) printf 'P %s\n' "${a#../docs/}" ;;
      docs/*)    printf 'P %s\n' "${a#docs/}" ;;
      ../*)      ;;                         # outside the project's code and docs
      *)         printf 'C %s\n' "$a" ;;
    esac
  done >> "$T/changed"
fi


cat > "$T/check.awk" <<'AWKEOF'
function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
function unq(s) { if (length(s) >= 2 && (s ~ /^".*"$/ || s ~ /^'.*'$/)) s = substr(s, 2, length(s) - 2); return s }
function shq(s) { gsub(/'/, "'\\''", s); return "'" s "'" }
function report(file, msg) { print "wiki-check: " file ": " msg }
function exists(p) { return system("test -e " shq(p)) == 0 }
function base(p) { sub(/.*\//, "", p); return p }
# Heading text: the rest of the line, closing hashes ("## Closed ##") dropped.
function htext(s) { s = trim(s); sub(/[ \t]+#+$/, "", s); return trim(s) }
# Characters of a UTF-8 string (awk runs with LC_ALL=C): continuation bytes do not count.
function ulen(s) { gsub(/[\200-\277]/, "", s); return length(s) }

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
  v = trim(unq(trim(v)))
  if (v == "") return
  nf++; flist[nf] = v
}
# related: items (inline [a, "b"] or block "- a"), each a [[...]] wikilink, quoted or not.
function relitem(v) {
  v = trim(unq(trim(v)))
  if (v != "" && v !~ /^!?\[\[.*\]\]$/) report(rel, "related is not a wikilink: " v)
}
function relflow(v,   i, c, q, cur) {
  if (mode != "page") return
  if (v !~ /^\[/) { relitem(v); return }
  sub(/^\[/, "", v); sub(/\][ \t]*$/, "", v); q = ""; cur = ""
  for (i = 1; i <= length(v); i++) {
    c = substr(v, i, 1)
    if (q != "") { if (c == q) q = ""; cur = cur c; continue }
    if (c == "\"" || c == "'") q = c
    if (c == ",") { relitem(cur); cur = ""; continue }
    cur = cur c
  }
  relitem(cur)
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
    if (!(k in has) && k !~ /^(type|status|description|files|related|updated)$/) unk[++nunk] = k
    has[k] = 1; val[k] = v; curkey = k
    if (k == "files" && v ~ /^\[/) flow(v)
    if (k == "related") { scanwiki(v); relflow(v) }
    return
  }
  if (curkey == "files" && l ~ /^[ \t]*-[ \t]+/) { v = l; sub(/^[ \t]*-[ \t]+/, "", v); additem(v) }
  if (curkey == "related") { scanwiki(l); if (mode == "page" && l ~ /^[ \t]*-[ \t]/) { v = l; sub(/^[ \t]*-[ \t]*/, "", v); relitem(v) } }
}

# Headings (# to ######) of a file, outside its front matter and code fences, cached.
# Headings seen inside a front matter that never closes still count (that page reports "unclosed").
function loadheads(path,   line, n, fm, fence, t, np, pend, i) {
  if (path in loaded) return
  loaded[path] = 1
  n = 0; fm = 0; fence = 0; np = 0
  while ((getline line < path) > 0) {
    sub(/\r$/, "", line); n++
    if (n == 1 && line ~ /^---[ \t]*$/) { fm = 1; continue }
    if (fm && line ~ /^---[ \t]*$/) { fm = 0; fence = 0; np = 0; continue }
    if (line ~ /^[ \t]*(```|~~~)/) { fence = !fence; continue }
    if (!fence && match(line, /^#+[ \t]/) && RLENGTH <= 7) {
      t = htext(substr(line, RLENGTH + 1))
      if (fm) pend[++np] = t; else heads[path SUBSEP t] = 1
    }
  }
  close(path)
  for (i = 1; i <= np; i++) heads[path SUBSEP pend[i]] = 1
}

# The docs-relative file a wikilink target names, or "" when none.
function resolve(t) {
  if (t == "") return rel
  if (index(t, "/") > 0) { if ((t ".md") in fileset) return t ".md"; return (t in fileset) ? t : "" }
  if (t in pagebyname) return pagebyname[t]
  return (t in filebyname) ? filebyname[t] : ""
}

# inner = what stands between [[ and ]]: target[#heading][|alias].
function wikilink(inner,   shown, t, h, c, f) {
  c = index(inner, "|"); shown = (c > 0) ? substr(inner, 1, c - 1) : inner
  if (c > 0) sub(/\\$/, "", shown)                     # table form [[x\|alias]]
  t = shown; h = ""
  c = index(t, "#"); if (c > 0) { h = trim(substr(t, c + 1)); t = substr(t, 1, c - 1) }
  f = resolve(trim(t))
  if (f != "" && h != "") { loadheads(docs "/" f); if (!((docs "/" f SUBSEP h) in heads)) f = "" }
  if (f == "") report(rel, "broken wikilink [[" shown "]]")
}

# Wikilinks of a page line; `inline code` is skipped, a backtick inside [[...]] is part of the link.
function scanwiki(s,   i, b, e) {
  if (mode != "page") return
  while ((i = index(s, "[[")) > 0) {
    b = index(s, "`")
    if (b > 0 && b < i) { s = substr(s, b + 1); e = index(s, "`"); if (e > 0) s = substr(s, e + 1); continue }
    s = substr(s, i + 2); e = index(s, "]]"); if (e == 0) return
    if (e > 1) wikilink(substr(s, 1, e - 1))
    s = substr(s, e + 2)
  }
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
  if (mode == "page" && rp ~ /^docs\// && (substr(rp, 6) in pageset)) { report(rel, "use a wikilink: " raw); return }
  if (!exists(full)) report(rel, "broken link " raw)
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

BEGIN {
  mode = ENVIRON["WC_MODE"]; rel = ENVIRON["WC_REL"]; proj = ENVIRON["WC_PROJ"]; docs = proj "/docs"
  fdir = ENVIRON["WC_FDIR"]; size = ENVIRON["WC_SIZE"] + 0
  changedf = ENVIRON["WC_CHANGED"]; pagesf = ENVIRON["WC_PAGES"]; filesf = ENVIRON["WC_FILES"]
  split("brief architecture decision feature spec plan glossary", a, " "); for (i in a) oktype[a[i]] = 1
  split("draft active done superseded", a, " "); for (i in a) okstatus[a[i]] = 1
  nc = 0
  while ((getline l < changedf) > 0) {
    if (substr(l, 1, 2) == "C ") { nc++; codechg[nc] = substr(l, 3); codeset[substr(l, 3)] = 1 }
    else if (substr(l, 1, 2) == "P ") pagechg[substr(l, 3)] = 1
  }
  close(changedf)
  while ((getline l < pagesf) > 0) {
    pageset[l] = 1; n = base(l); sub(/\.md$/, "", n)
    if (!(n in pagebyname)) pagebyname[n] = l
    else if (mode == "page" && l == rel) report(rel, "duplicate page name " n)
  }
  close(pagesf)
  while ((getline l < filesf) > 0) { fileset[l] = 1; n = base(l); if (!(n in filebyname)) filebyname[n] = l }
  close(filesf)
}

{
  line = $0; sub(/\r$/, "", line)
  if (NR == 1 && line ~ /^---[ \t]*$/) { infm = 1; next }
  if (infm) {
    if (line ~ /^---[ \t]*$/) { infm = 0; next }
    fmline(line); next
  }
  if (line ~ /^[ \t]*(```|~~~)/) { fence = !fence; next }
  if (fence) next
  if (line ~ /^## /) {
    h2++
    t = htext(substr(line, 4))
    if (mode == "page" && seenh[t]++ == 1) report(rel, "duplicate heading " t)
  }
  scanlinks(line)
  scanwiki(line)
}

END {
  if (infm) report(rel, "unclosed front matter")
  if (mode == "page") {
    nreq = split("type status description files related updated", req, " ")
    for (i = 1; i <= nreq; i++) {
      f = req[i]; v = unq(val[f])
      if (!(f in has) || (v == "" && f != "files" && f != "related")) { report(rel, "missing front matter field " f); continue }
      if (f == "type" && !(v in oktype)) report(rel, "bad type: " v)
      if (f == "status" && !(v in okstatus)) report(rel, "bad status: " v)
      if (f == "updated" && v !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) report(rel, "bad updated: " v)
      if (f == "description" && val[f] ~ /^[>|]/) report(rel, "description not one line")
      else if (f == "description" && ulen(v) > 80) report(rel, "description over 80 chars")
    }
    for (i = 1; i <= nunk; i++) report(rel, "unknown front matter field " unk[i])
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
}
function drift(c) { report(rel, "drift: " c " changed, page not updated") }
AWKEOF

# run_awk <mode> <display name> <file> <dir of file relative to project>
run_awk() {
  LC_ALL=C WC_MODE="$1" WC_REL="$2" WC_PROJ="$PROJ" WC_FDIR="$4" WC_SIZE="$(wc -c < "$3" | tr -d ' ')" \
  WC_CHANGED="$T/changed" WC_PAGES="$T/pages" WC_FILES="$T/files" awk -f "$T/check.awk" "$3"
}

# A failing awk must not read as "green": remember it in $T/failed and exit 2 below.
run_checked() { run_awk "$@" || echo "$2" >> "$T/failed"; }

OUT="$(
  if [ ! -f "$DOCS/INDEX.md" ]; then echo "wiki-check: INDEX.md: missing"
  else
    "$HERE/wiki-index.sh" "$PROJ" --check > /dev/null 2>&1; rc=$?      # (no "case" here: bash 3.2 misparses it in $( ))
    if [ "$rc" = 1 ]; then echo "wiki-check: INDEX.md: INDEX.md stale"
    elif [ "$rc" != 0 ]; then echo INDEX.md >> "$T/failed"; fi
  fi
  while IFS= read -r page; do
    d="$(dirname "$page")"; if [ "$d" = . ]; then d=docs; else d="docs/$d"; fi
    run_checked page "$page" "$DOCS/$page" "$d"
  done < "$T/pages"
  if [ -f "$PROJ/CLAUDE.md" ]; then run_checked claude ../CLAUDE.md "$PROJ/CLAUDE.md" ""; fi
)"

if [ -s "$T/failed" ]; then
  echo "wiki-check: internal error: awk failed on: $(tr '\n' ' ' < "$T/failed")" >&2
  exit 2
fi
if [ -n "$OUT" ]; then printf '%s\n' "$OUT"; exit 1; fi
exit 0
