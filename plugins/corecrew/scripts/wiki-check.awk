# scripts/wiki-check.awk — the checks of one wiki page or CLAUDE.md, for wiki-check.sh (which lists the
# checks and their messages in its header):
#   LC_ALL=C WC_MODE=page|claude WC_REL=<file shown> WC_PROJ=<project dir> WC_FDIR=<dir of the file,
#     project-relative> WC_SIZE=<bytes> WC_CODE=<code root or ""> WC_CHANGED=<file> WC_PAGES=<file> WC_FILES=<file> \
#     awk -f wiki-check.awk <file>
# WC_CHANGED holds "C <code path>" / "P <docs-relative page>" lines (--changed), WC_PAGES the wiki pages
# (docs-relative), WC_FILES every file under docs/. Prints "wiki-check: <WC_REL>: <problem>" per
# problem, nothing when the file is green. Runs under LC_ALL=C (ulen counts UTF-8 characters by hand).
# Portable awk (BSD awk, no gawk extensions).

function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
function unq(s) { if (length(s) >= 2 && (s ~ /^".*"$/ || s ~ /^'.*'$/)) s = substr(s, 2, length(s) - 2); return s }
function shq(s) { gsub(/'/, "'\\''", s); return "'" s "'" }
function report(file, msg) { print "wiki-check: " file ": " msg }
function exists(p) { return system("test -e " shq(p)) == 0 }
function isdir(p) { return system("test -d " shq(p)) == 0 }
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
  fdir = ENVIRON["WC_FDIR"]; size = ENVIRON["WC_SIZE"] + 0; code = ENVIRON["WC_CODE"]
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
    # files: entries. Active pages must name paths that exist (--code); done and superseded pages
    # are history: no drift, no existence check; draft pages may name files still to be created.
    # Both loops read an entry as norm() gives it; an absolute one, or one that climbs out of the code
    # root, is no code path: missing here, and never a drift below. The code root itself (./ or .) is the
    # root folder: it exists, and any changed code path drifts.
    st = unq(val["status"])
    if (code != "" && st == "active")
      for (i = 1; i <= nf; i++) {
        f = flist[i]; p = norm(f)
        if (p ~ /^(\/|\.\.(\/|$))/ || (f ~ /\/$/ ? !isdir(code "/" p) : !exists(code "/" p))) report(rel, "missing file " f)
      }
    if (st != "done" && st != "superseded" && !(rel in pagechg)) {
      for (i = 1; i <= nf; i++) {
        f = flist[i]
        dir = (f ~ /\/$/)
        f = norm(f); if (f == "") dir = 1; else if (dir) f = f "/"
        if (dir) { for (k = 1; k <= nc; k++) if (index(codechg[k], f) == 1) drift(codechg[k]) }
        else if (f in codeset) drift(f)
      }
    }
  }
}
function drift(c) { report(rel, "drift: " c " changed, page not updated") }
