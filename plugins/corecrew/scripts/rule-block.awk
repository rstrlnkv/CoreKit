# scripts/rule-block.awk — a .claude/rules/<f>.md file as a CLAUDE.md subsection, for adopt.sh:
#   awk -v L=<label> -v FM=0|1 -f rule-block.awk <rule file>
# Prints "### <L>", then "Applies to: <paths, comma-separated>" when the front matter has paths: (a
# block list, an inline [..] list or one value), then the body without the front matter, its headings
# three levels down (at most ######), leading and trailing blank lines dropped. FM is 1 when the file
# has a front matter (the caller checks that the closing --- exists). Portable awk (BSD awk).
function trim(s) { gsub(/^[ \t]+|[ \t\r]+$/, "", s); return s }
function unq(s,   a) { s = trim(s); a = substr(s, 1, 1)
  if (length(s) >= 2 && (a == "\"" || a == "'") && substr(s, length(s), 1) == a) s = substr(s, 2, length(s) - 2)
  return s }
function add(s) { s = unq(s); if (s != "") PS = (PS == "" ? s : PS ", " s) }
function inline(s,   i, c, q, d, cur) {
  s = trim(s); sub(/^\[/, "", s); sub(/\][ \t]*$/, "", s); q = ""; d = 0; cur = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (q != "") { if (c == q) q = ""; cur = cur c; continue }
    if (c == "\"" || c == "'") { q = c; cur = cur c; continue }
    if (c == "{") d++
    if (c == "}") d--
    if (c == "," && d <= 0) { add(cur); cur = ""; continue }
    cur = cur c
  }
  add(cur)
}
{ sub(/\r$/, "") }
FM && NR == 1 { infm = 1; next }
infm && /^---[ \t]*$/ { infm = 0; next }
infm {
  if (inlist) { if ($0 ~ /^[ \t]*-/) { v = $0; sub(/^[ \t]*-[ \t]*/, "", v); add(v); next } else inlist = 0 }
  if ($0 ~ /^paths[ \t]*:/) { v = $0; sub(/^paths[ \t]*:/, "", v); v = trim(v)
    if (v == "") inlist = 1; else if (v ~ /^\[/) inline(v); else add(v) }
  next
}
{
  if (!started && $0 ~ /^[ \t]*$/) next
  started = 1
  if ($0 ~ /^(```|~~~)/) fence = !fence
  if (!fence && match($0, /^#+ /)) {
    n = RLENGTH - 1
    if (n <= 6) { m = n + 3; if (m > 6) m = 6; h = ""; for (i = 0; i < m; i++) h = h "#"; $0 = h substr($0, RLENGTH) }
  }
  B[++nb] = $0
}
END {
  while (nb > 0 && B[nb] ~ /^[ \t]*$/) nb--
  print ""; print "### " L; print ""
  if (PS != "") { print "Applies to: " PS; print "" }
  for (i = 1; i <= nb; i++) print B[i]
}
