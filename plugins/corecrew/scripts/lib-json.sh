# lib-json.sh — json_str, the hook JSON reader (no jq), for lib.sh (source lib.sh, not this file).
# The awk program is inline on purpose: the guards judge file tools through json_str, and their documented contract is
# that a missing scripts/*.awk (the Bash tokenizer) fails open only on the Bash path. A separate awk file here would make
# a missing awk file let every tool pass.

# json_str <json> <key> — prints the first string value of "<key>" anywhere in the JSON text.
# Unescapes \" \\ \/ \b \f \n \r \t and decodes \uXXXX to UTF-8 (surrogate pairs too; a lone
# surrogate becomes U+FFFD; \u0000 is dropped). Whitespace and newlines around ':' are fine.
# A missing key, a value that is not a string, or malformed input prints nothing; the exit
# status is always 0. A key name that only appears inside a string value is not a key.
# Linear time: the text is split at the quote characters once, so a string is a run of pieces
# (a piece that ends in an odd number of backslashes ends at an escaped quote), and a value is
# decoded by splitting each piece at its backslashes. No loop walks single characters.
json_str() {
  printf '%s' "${1:-}" | JSON_KEY="${2:-}" LC_ALL=C awk '
    function hexval(h,   i, d, v) {
      v = 0
      for (i = 1; i <= length(h); i++) {
        d = index("0123456789abcdef", tolower(substr(h, i, 1)))
        if (d == 0) return -1
        v = v * 16 + d - 1
      }
      return v
    }
    function utf8(cp) {
      if (cp < 128) return chr[cp]
      if (cp < 2048) return chr[192 + int(cp / 64)] chr[128 + cp % 64]
      if (cp < 65536) return chr[224 + int(cp / 4096)] chr[128 + int(cp / 64) % 64] chr[128 + cp % 64]
      return chr[240 + int(cp / 262144)] chr[128 + int(cp / 4096) % 64] chr[128 + int(cp / 64) % 64] chr[128 + cp % 64]
    }
    # 1 when the piece ends in an odd number of backslashes (the quote after it is escaped)
    function oddbs(s,   l) {
      l = length(s)
      if (l == 0 || substr(s, l, 1) != "\\") return 0
      if (match(s, /[^\\]\\+$/)) return (RLENGTH - 1) % 2   # anchored on a non-backslash: linear
      return l % 2
    }
    # print the decoded text t (pieces joined with escaped quotes already appended)
    function emit(t,   m, S, j, c, r, cp, lo) {
      m = split(t, S, "\\")
      for (j = 1; j <= m; j++) gsub(/\002/, "\n", S[j])   # after split: split() also cuts at newlines
      printf "%s", S[1]
      for (j = 2; j <= m; j++) {
        r = S[j]
        if (r == "") {                      # "\\" : one backslash; the next piece is plain text
          if (j == m) break
          printf "%s", "\\"; j++; printf "%s", S[j]; continue
        }
        c = substr(r, 1, 1); r = substr(r, 2)
        if (c == "n") printf "%s", "\n"
        else if (c == "t") printf "%s", "\t"
        else if (c == "r") printf "%s", "\r"
        else if (c == "b") printf "%s", chr[8]
        else if (c == "f") printf "%s", chr[12]
        else if (c == "u") {
          if (length(r) < 4) continue       # short escape: dropped with what is left
          cp = hexval(substr(r, 1, 4)); r = substr(r, 5)
          if (cp < 0) { printf "%s", r; continue }
          if (cp >= 55296 && cp <= 56319) {
            lo = -1
            if (r == "" && j < m && length(S[j + 1]) >= 5 && substr(S[j + 1], 1, 1) == "u") lo = hexval(substr(S[j + 1], 2, 4))
            if (lo >= 56320 && lo <= 57343) { cp = 65536 + (cp - 55296) * 1024 + (lo - 56320); j++; r = substr(S[j], 6) }
            else cp = 65533
          } else if (cp >= 56320 && cp <= 57343) cp = 65533
          if (cp > 0) printf "%s", utf8(cp)
        }
        else printf "%s", c                 # \" \/ and unknown escapes: the character itself
        printf "%s", r
      }
    }
    BEGIN { RS = "\001" }
    { buf = (NR == 1 ? "" : buf "\001") $0 }
    END {
      key = ENVIRON["JSON_KEY"] ""
      if (key == "") exit 0
      for (n = 1; n < 256; n++) chr[n] = sprintf("%c", n)
      chr[0] = ""
      gsub(/\n/, "\002", buf)               # BWK awk split() also splits at newlines
      n = split(buf, P, "\"")               # P[1] is outside a string, P[2] inside, and so on
      i = 2
      while (i < n) {
        e = i
        while (e < n && oddbs(P[e])) e++
        if (e >= n) exit 0                  # unterminated string
        if (e == i && (P[i] "") == key && e + 2 <= n && P[e + 1] ~ /^[ \t\r\002]*:[ \t\r\002]*$/) {
          v = e + 2; w = v                  # a string value starts at piece v
          while (w < n && oddbs(P[w])) w++
          if (w >= n) exit 0
          for (k = v; k < w; k++) emit(P[k] "\"")
          emit(P[w])
          exit 0
        }
        i = e + 2
      }
    }
  ' 2>/dev/null || true
  return 0
}
