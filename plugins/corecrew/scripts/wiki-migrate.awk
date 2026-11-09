# wiki-migrate.awk — the converter of wiki-migrate.sh: one page in, the page in the current format out; warnings appended to the file WARN. Inputs (-v): SQ (a single quote), NAME (the page name), TYPE (from its folder, or empty), DATE (for a missing updated:), NAMES (file: the page names), HEADS (file: name<TAB>heading lines), WARN (file).
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function unq(s,   a) { s = trim(s); a = substr(s, 1, 1)
  if (length(s) >= 2 && (a == "\"" || a == SQ) && substr(s, length(s), 1) == a) s = substr(s, 2, length(s) - 2)
  return s }
function ulen(s) { gsub(/[\200-\277]/, "", s); return length(s) }
function warn(m) { print "warning: " NAME ": " m >> WARN }
# The wiki page a link target (no anchor) names, or "".
function pagename(t,   n) {
  if (t ~ /^[A-Za-z][A-Za-z0-9+.-]*:/ || t !~ /\.md$/) return ""
  n = t; sub(/.*\//, "", n); n = substr(n, 1, length(n) - 3)
  return (n in page) ? n : ""
}
function wlink(n, anc, txt) {
  if (anc != "" && !((n SUBSEP anc) in head)) { warn("anchor #" anc " dropped"); anc = "" }
  return "[[" n (anc != "" ? "#" anc : "") ((txt == "" || txt == n) ? "" : "|" txt) "]]"
}
# Old page-and-heading references "docs/<page>.md § <text>". hmatch(n, r): the length of the longest
# heading of page n that starts r and ends at a word boundary (HM = that heading), else 0. The text
# after it (a trailing . , ; : or ), the rest of the line) stays.
function hmatch(n, r,   i, k, h, b, best) {
  best = 0; HM = ""
  if (!(n in hl)) return 0
  k = split(hl[n], H, "\n")
  for (i = 1; i <= k; i++) {
    h = H[i]
    if (h == "" || length(h) <= best || substr(r, 1, length(h)) != h) continue
    b = substr(r, length(h) + 1, 1)
    if (b != "" && b ~ /[A-Za-z0-9_\200-\377]/) continue
    best = length(h); HM = h
  }
  return best
}
function rname(p) { sub(/.*\//, "", p); return substr(p, 1, length(p) - 3) }
# A code span holding exactly one reference: the wikilink (plus one mark), or "".
function sect(s,   i, p, n, r, k, tail) {
  if (s !~ /^docs\/[^ \t`]+\.md § [^ \t]/) return ""
  i = index(s, ".md" SECT); p = substr(s, 6, i - 3); n = pagename(p); r = substr(s, i + 3 + length(SECT))
  k = (n == "") ? 0 : hmatch(n, r); tail = substr(r, k + 1)
  if (k > 0 && (tail == "" || index(".,;:)", tail) > 0 && length(tail) == 1)) return "[[" n "#" HM "]]" tail
  warn("reference to " rname(p) SECT trim(r) " not converted"); return ""
}
function rel_item(it,   n) {
  if (unq(it) ~ /^\[\[/) return it
  n = pagename(unq(it))
  if (n == "") return it
  relch = 1; return "\"[[" n "]]\""
}
function rel_inline(v,   s, i, c, q, cur, out, k) {
  s = trim(v); if (s !~ /^\[.*\]$/) return v
  s = substr(s, 2, length(s) - 2); if (trim(s) == "") return v
  q = ""; cur = ""; out = ""; k = 0; relch = 0
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (q != "") { if (c == q) q = ""; cur = cur c; continue }
    if (c == "\"" || c == SQ) q = c
    if (c == ",") { out = out (k++ ? ", " : "") rel_item(trim(cur)); cur = ""; continue }
    cur = cur c
  }
  out = out (k++ ? ", " : "") rel_item(trim(cur))
  return relch ? "[" out "]" : v
}
# Plain text: references (several per line) and Markdown links.
function refs(s,   out, pre, m, p, n, k) {
  out = ""
  while (match(s, /docs\/[^ \t`]+\.md § /)) {
    pre = substr(s, 1, RSTART - 1); m = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
    if (pre ~ /[A-Za-z0-9_.\/-]$/) { out = out links(pre) m; continue }
    p = substr(m, 6, length(m) - 5 - length(SECT)); n = pagename(p)
    k = (n == "") ? 0 : hmatch(n, s)
    if (k == 0) { warn("reference to " rname(p) SECT trim(s) " not converted"); out = out links(pre) m; continue }
    out = out links(pre) "[[" n "#" HM "]]"; s = substr(s, k + 1)
  }
  return out links(s)
}
# Markdown links to wiki pages in plain text. A "|" in the link text becomes "/" (it would end the alias).
function links(s,   out, m, i, txt, tgt, anc, k, n) {
  out = ""
  while (match(s, /!?\[[^]\[]*\]\((<[^<>]*>|[^ ()<>]+)\)/)) {
    m = substr(s, RSTART, RLENGTH); out = out substr(s, 1, RSTART - 1); s = substr(s, RSTART + RLENGTH)
    i = index(m, "](")
    txt = substr(m, 2, i - 2); tgt = substr(m, i + 2, length(m) - i - 2); gsub(/\|/, "/", txt)
    if (tgt ~ /^<.*>$/) tgt = substr(tgt, 2, length(tgt) - 2)
    anc = ""; if ((k = index(tgt, "#")) > 0) { anc = substr(tgt, k + 1); tgt = substr(tgt, 1, k - 1) }
    n = (substr(m, 1, 1) == "!") ? "" : pagename(tgt)
    out = out ((n == "") ? m : wlink(n, anc, txt))
  }
  return out s
}
# The column where a run of exactly L backticks starts in s, or 0.
function closer(s, L,   p, k) {
  p = 0
  while ((k = index(substr(s, p + 1), "`")) > 0) {
    p += k; match(substr(s, p), /^`+/)
    if (RLENGTH == L) return p
    p += RLENGTH - 1
  }
  return 0
}
function body(line,   out, text, i, L, rest, c, code, r, n, after, k) {
  out = ""; text = ""
  while ((i = index(line, "`")) > 0) {
    text = text substr(line, 1, i - 1); line = substr(line, i)
    match(line, /^`+/); L = RLENGTH; rest = substr(line, L + 1)
    c = closer(rest, L)
    if (c == 0) { text = text line; line = ""; break }
    code = substr(rest, 1, c - 1); after = substr(rest, c + L)
    # `docs/x.md` § Heading: the path in backticks, the heading outside
    if (code ~ /^docs\/[^ \t`]+\.md$/ && index(after, SECT) == 1) {
      n = pagename(substr(code, 6)); r = substr(after, length(SECT) + 1)
      k = (n == "") ? 0 : hmatch(n, r)
      if (k > 0) { out = out refs(text) "[[" n "#" HM "]]"; text = ""; line = substr(r, k + 1); continue }
      warn("reference to " rname(code) SECT trim(r) " not converted")
    }
    r = (index(code, SECT) > 0) ? sect(code) : ""
    if (r == "") r = substr(line, 1, L) code substr(line, 1, L)
    out = out refs(text) r; text = ""
    line = after
  }
  return out refs(text line)
}
function emit(s) { printf "%s%s\n", s, EOL }
function field(k, def,   i, j) {
  if (k in at) { i = at[k]; emit(K[i] == "related" ? relline(i) : L[i]); for (j = 1; j <= NC[i]; j++) emit(C[i, j]); return }
  if (def != "") emit(k ": " def)
}
function relline(i,   v, j, it, p) {
  v = substr(L[i], index(L[i], ":") + 1)
  if (trim(v) != "") { relch = 0; v = rel_inline(v); return relch ? "related: " v : L[i] }
  for (j = 1; j <= NC[i]; j++) if (match(C[i, j], /^[ \t]*-[ \t]*/)) {
    p = substr(C[i, j], 1, RLENGTH); it = substr(C[i, j], RLENGTH + 1)
    C[i, j] = p rel_item(trim(it))
  }
  return L[i]
}
function val(k) { return (k in at) ? unq(substr(L[at[k]], index(L[at[k]], ":") + 1)) : "" }
BEGIN {
  split("type status description updated", q, " "); for (i in q) dflt[q[i]] = 1
  while ((getline l < NAMES) > 0) page[l] = 1
  SECT = " § "
  while ((getline l < HEADS) > 0) { t = index(l, "\t"); n = substr(l, 1, t - 1); h = substr(l, t + 1)
    head[n, h] = 1; hl[n] = (n in hl) ? hl[n] "\n" h : h }
}
{ cr[NR] = sub(/\r$/, ""); X[NR] = $0 }
END {
  EOL = cr[1] ? "\r" : ""; start = 1; nk = 0
  if (NR >= 1 && X[1] ~ /^---[ \t]*$/) {
    for (e = 2; e <= NR && X[e] !~ /^---[ \t]*$/; e++) ;
    if (e > NR) { warn("front matter not closed"); for (i = 1; i <= NR; i++) printf "%s%s\n", X[i], cr[i] ? "\r" : ""; exit }
    for (i = 2; i < e; i++) {
      if (match(X[i], /^[A-Za-z_][A-Za-z0-9_-]*[ \t]*:/)) {
        k = substr(X[i], 1, RLENGTH); sub(/[ \t]*:$/, "", k)
        K[++nk] = k; L[nk] = X[i]; NC[nk] = 0
        if (!(k in at)) at[k] = nk; else K[nk] = "\001" k
      } else if (nk > 0) C[nk, ++NC[nk]] = X[i]
      else { K[++nk] = "\001"; L[nk] = X[i]; NC[nk] = 0 }
    }
    start = e + 1
  }
  # an empty value with no continuation lines counts as missing (a folded or indented one is kept)
  for (k in dflt) if ((k in at) && val(k) == "" && NC[at[k]] == 0) delete at[k]
  emit("---")
  field("type", TYPE); field("status", "draft")
  field("description", "\"TODO: describe this page.\""); field("files", "[]")
  field("related", "[]"); field("updated", DATE)
  t = (("type" in at) ? val("type") : TYPE)
  hasprog = 0
  openfence = 0
  for (i = start; i <= NR; i++) {
    if (X[i] ~ /^## Progress[ \t]*$/) hasprog = 1
    if (X[i] ~ /^[ \t]*(```|~~~)/) openfence = !openfence
  }
  mvstage = (t == "brief" && ("stage" in at) && val("stage") != "" && NC[at["stage"]] == 0 && !hasprog && !openfence)
  extras = ""
  for (i = 1; i <= nk; i++) {
    k = K[i]
    if (k == "title" || ((k in at) && at[k] == i && k ~ /^(type|status|description|files|related|updated)$/)) continue
    if ((k in dflt) && !(k in at)) continue
    if (mvstage && k == "stage" && at[k] == i) continue
    if (k !~ /^\001/) extras = extras k "\n"
    emit(L[i]); for (j = 1; j <= NC[i]; j++) emit(C[i, j])
  }
  emit("---")
  if (t !~ /^(brief|architecture|decision|feature|spec|plan|glossary)$/) warn("set type")
  if (("description" in at) && trim(substr(L[at["description"]], index(L[at["description"]], ":") + 1)) ~ /^[>|]/) warn("description is not one line")
  else if (ulen(val("description")) > 80) warn("description over 80 chars")
  s = val("status"); if (s != "" && s !~ /^(draft|active|done|superseded)$/) warn("status " s)
  ne = split(extras, ex, "\n"); for (i = 1; i < ne; i++) warn("extra front matter field " ex[i])
  if (start == 1) emit("")
  fence = 0
  for (i = start; i <= NR; i++) {
    l = X[i]
    if (l ~ /^[ \t]*(```|~~~)/) fence = !fence
    else if (!fence) l = body(l)
    printf "%s%s\n", l, cr[i] ? "\r" : ""
  }
  if (mvstage) { emit(""); emit("## Progress"); emit("Stage: " val("stage")) }
}
