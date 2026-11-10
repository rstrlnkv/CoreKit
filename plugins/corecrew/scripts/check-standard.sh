#!/usr/bin/env bash
# check-standard.sh — deterministic checks of one standard file.
#
# Usage: check-standard.sh <file>
#
# A standard is <Core>/standards/<name>.md, English, at most 120 lines:
#   ---
#   name: <kebab-case>
#   description: <one line>
#   applies-to: [<role>, <role>]     engineer tester security verifier localizer designer release
#   updated: YYYY-MM-DD
#   ---
#   # <Title>
#   ## Rule             "1. <imperative rule>", one numbered line per rule
#   ## Why              one line per rule
#   ## How to check     one entry per rule number, in one of two line forms:
#                         1. <command> → <expected output>
#                         2. no guard — <the risk that stays>
#   ## Exceptions       "none" or a list
#   ## Sources          what the rules rest on
# The five "## " headings appear in that order. Headings and numbered lines inside code
# fences are ignored. In "## How to check" a line that does not start with "<n>. " (a
# comment, a continuation) is ignored.
#
# Output: one line per problem, "check-standard: <problem>", exit 1; silent and 0 when green.
#   missing front matter field <f>       name, description, applies-to or updated absent or empty
#   unclosed front matter                opening --- without a closing ---
#   unknown role <r> in applies-to       <r> is not one of the seven roles above
#   missing section <s>                  one of the five headings is absent
#   sections out of order                all present, but not in the order above
#   no rules in ## Rule                  the section has no "<n>. <text>" line
#   rule <n> has no check                no "<n>. ..." entry in ## How to check
#   check <n> is malformed (...)         entry is neither of the two line forms
#   placeholder left: <text>             a template placeholder (the exact <...> texts of
#                                        references/template.md) is still in the file
#   comment left                         an unfenced "<!--" (template guidance not removed)
#   over 120 lines
# Exit 2: usage error or unreadable file. Portable bash 3.2 + BSD awk.

set -u

if [ $# -ne 1 ]; then
  echo "usage: check-standard.sh <file>" >&2
  exit 2
fi
FILE="$1"
if [ ! -f "$FILE" ] || [ ! -r "$FILE" ]; then
  echo "check-standard: $FILE: not a readable file" >&2
  exit 2
fi

ROLES="engineer tester security verifier localizer designer release"

OUT="$(LC_ALL=C awk -v roles="$ROLES" '
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function problem(msg) { print "check-standard: " msg }
function scan(l,   t) {
  if (index(l, "<!--") > 0 && !commented) { commented = 1 }
  for (t = 1; t <= nph; t++) if (index(l, PH[t]) > 0 && !(PH[t] in PHSEEN)) { PHSEEN[PH[t]] = 1; PHORD[++nphseen] = PH[t] }
}
BEGIN {
  nph = split("<kebab-case>|<one line: what it rules and when an agent needs it>|<roles that must read it>|<Title>|<imperative rule>|<the failure this rule prevents>|<command>|<expected output>|<the risk that stays>|<what the rules rest on: a link, a document, or your own experience>", PH, "|")

  nsec = split("Rule|Why|How to check|Exceptions|Sources", SEC, "|")
  nfld = split("name description applies-to updated", FLD, " ")
  nrole = split(roles, ROLE, " ")
  state = 2; unclosed = 0; fence = 0; cur = ""
}
{
  sub(/\r$/, "")
  if (NR == 1) {
    if ($0 == "---") { state = 1; next }
  }
  if (state == 1) {
    if ($0 == "---") { state = 2; closed = 1; next }
    scan($0)
    i = index($0, ":")
    if (i > 1) {
      key = substr($0, 1, i - 1); val = trim(substr($0, i + 1))
      FV[key] = val
    }
    next
  }
  # body
  line = $0
  if (line ~ /^[ \t]*(```|~~~)/) { fence = !fence; next }
  if (fence) next
  scan(line)
  if (line ~ /^## /) {
    h = trim(substr(line, 4)); cur = ""
    for (k = 1; k <= nsec; k++) if (h == SEC[k]) {
      cur = h
      if (!(h in POS)) { POS[h] = ++npos; IDX[npos] = k }
    }
    next
  }
  if (cur == "Rule" && line ~ /^[0-9]+\.[ \t]+[^ \t]/) {
    n = line; sub(/\..*/, "", n); n = n + 0
    if (!(n in ISRULE)) { ISRULE[n] = 1; RULES[++nrules] = n }
  } else if (cur == "How to check" && line ~ /^[0-9]+\.[ \t]+/) {
    n = line; sub(/\..*/, "", n); n = n + 0
    body = line; sub(/^[0-9]+\.[ \t]+/, "", body); body = trim(body)
    SEEN[n] = 1
    ok = 0
    if (index(body, "no guard — ") == 1) {
      if (trim(substr(body, length("no guard — ") + 1)) != "") ok = 1
    } else {
      j = index(body, " → ")
      if (j > 1 && trim(substr(body, 1, j - 1)) != "" && trim(substr(body, j + 5)) != "") ok = 1
    }
    if (ok) OKCHK[n] = 1
  }
}
END {
  # front matter
  if (state == 1) {
    problem("unclosed front matter")
  } else {
    for (f = 1; f <= nfld; f++) {
      k = FLD[f]
      v = (k in FV) ? FV[k] : ""
      if (k == "applies-to") { gsub(/[\[\]]/, "", v); v = trim(v) }
      if (v == "") problem("missing front matter field " k)
      else if (k == "applies-to") {
        m = split(v, R, ",")
        for (r = 1; r <= m; r++) {
          role = trim(R[r]); if (role == "") continue
          known = 0
          for (q = 1; q <= nrole; q++) if (ROLE[q] == role) known = 1
          if (!known) problem("unknown role " role " in applies-to")
        }
      }
    }
  }
  if (state == 1) { if (NR > 120) problem("over 120 lines"); exit }
  # sections
  missing = 0
  for (k = 1; k <= nsec; k++) if (!(SEC[k] in POS)) { problem("missing section " SEC[k]); missing = 1 }
  if (!missing) {
    for (p = 2; p <= npos; p++) if (IDX[p] < IDX[p - 1]) { problem("sections out of order"); break }
  }
  # rules and checks
  if (("Rule" in POS) && nrules == 0) problem("no rules in ## Rule")
  if ("How to check" in POS) {
    for (r = 1; r <= nrules; r++) {
      n = RULES[r]
      if (!(n in SEEN)) problem("rule " n " has no check")
      else if (!(n in OKCHK)) problem("check " n " is malformed (want \"<command> → <expected>\" or \"no guard — <risk>\")")
    }
  }
  for (t = 1; t <= nphseen; t++) problem("placeholder left: " PHORD[t])
  if (commented) problem("comment left")
  if (NR > 120) problem("over 120 lines")
}
' "$FILE")" || { echo "check-standard: internal error (awk failed)" >&2; exit 2; }

if [ -n "$OUT" ]; then
  printf '%s\n' "$OUT"
  exit 1
fi
exit 0
