# lib-json.sh — json_str and json_fields, the hook JSON readers (no jq), for lib.sh (source lib.sh, not this file).
# The awk program is inline on purpose: the guards judge file tools through json_fields, and their documented contract is
# that a missing scripts/*.awk (the Bash tokenizer) fails open only on the Bash path. A separate awk file here would make
# a missing awk file let every tool pass.

# _JSON_AWK — the program both readers run: json_str is json_fields of one key, printed as it is (no NUL, no newline
# dropped).
# shellcheck disable=SC2016  # an awk program, not shell text
_JSON_AWK='
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
    # put(s): prints s. With NUL set (json_fields), trailing newlines are held back until more text follows, so the
    # newlines that end a value are dropped, as $(...) drops them.
    function put(s,   l) {
      if (s == "") return
      if (!NUL) { printf "%s", s; return }
      if (match(s, /\n+$/)) { l = RLENGTH; s = substr(s, 1, length(s) - l) } else l = 0
      if (s != "") { while (held > 0) { printf "\n"; held-- }; printf "%s", s }
      held += l
    }
    # print the decoded text t (pieces joined with escaped quotes already appended)
    function emit(t,   m, S, j, c, r, cp, lo) {
      m = split(t, S, "\\")
      for (j = 1; j <= m; j++) gsub(/\002/, "\n", S[j])   # after split: split() also cuts at newlines
      put(S[1])
      for (j = 2; j <= m; j++) {
        r = S[j]
        if (r == "") {                      # "\\" : one backslash; the next piece is plain text
          if (j == m) break
          put("\\"); j++; put(S[j]); continue
        }
        c = substr(r, 1, 1); r = substr(r, 2)
        if (c == "n") put("\n")
        else if (c == "t") put("\t")
        else if (c == "r") put("\r")
        else if (c == "b") put(chr[8])
        else if (c == "f") put(chr[12])
        else if (c == "u") {
          if (length(r) < 4) continue       # short escape: dropped with what is left
          cp = hexval(substr(r, 1, 4)); r = substr(r, 5)
          if (cp < 0) { put(r); continue }
          if (cp >= 55296 && cp <= 56319) {
            lo = -1
            if (r == "" && j < m && length(S[j + 1]) >= 5 && substr(S[j + 1], 1, 1) == "u") lo = hexval(substr(S[j + 1], 2, 4))
            if (lo >= 56320 && lo <= 57343) { cp = 65536 + (cp - 55296) * 1024 + (lo - 56320); j++; r = substr(S[j], 6) }
            else cp = 65533
          } else if (cp >= 56320 && cp <= 57343) cp = 65533
          if (cp > 0) put(utf8(cp))
        }
        else put(c)                         # \" \/ and unknown escapes: the character itself
        put(r)
      }
    }
    BEGIN { RS = "\001" }
    { buf = (NR == 1 ? "" : buf "\001") $0 }
    # JSON_KEYS: the keys, one per line. Per key, the first occurrence whose value is a string (a key followed by a
    # number, null, an array or an object is passed over, and the search goes on).
    END {
      nk = split(ENVIRON["JSON_KEYS"], K, "\n"); left = 0
      if (nk > 0 && K[nk] == "") nk--         # the list ends with a newline
      for (k = 1; k <= nk; k++) if (K[k] != "" && !(K[k] in WANT)) { WANT[K[k]] = k; left++ }
      if (left > 0) {
        for (c = 1; c < 256; c++) chr[c] = sprintf("%c", c)
        chr[0] = ""
        gsub(/\n/, "\002", buf)               # BWK awk split() also splits at newlines
        n = split(buf, P, "\"")               # P[1] is outside a string, P[2] inside, and so on
        i = 2
        while (i < n && left > 0) {
          e = i
          while (e < n && oddbs(P[e])) e++
          if (e >= n) break                    # unterminated string
          if (e == i && ((P[i] "") in WANT) && e + 2 <= n && P[e + 1] ~ /^[ \t\r\002]*:[ \t\r\002]*$/) {
            v = e + 2; w = v                   # a string value starts at piece v
            while (w < n && oddbs(P[w])) w++
            if (w >= n) break
            k = WANT[P[i] ""]
            if (!(k in V)) { V[k] = v; E[k] = w; left-- }
            i = w + 2; continue
          }
          i = e + 2
        }
      }
      for (k = 1; k <= nk; k++) {
        if ((K[k] in WANT) && WANT[K[k]] < k) k2 = WANT[K[k]]; else k2 = k   # a key named twice: its first place
        if (k2 in V) {
          held = 0
          for (j = V[k2]; j < E[k2]; j++) emit(P[j] "\"")
          emit(P[E[k2]])
        }
        if (NUL) printf "%c", 0
      }
    }
'

# json_str <json> <key> — prints the first string value of "<key>" anywhere in the JSON text.
# Unescapes \" \\ \/ \b \f \n \r \t and decodes \uXXXX to UTF-8 (surrogate pairs too; a lone
# surrogate becomes U+FFFD; \u0000 is dropped). Whitespace and newlines around ':' are fine.
# A missing key, a value that is not a string, or malformed input prints nothing; the exit
# status is always 0. A key name that only appears inside a string value is not a key.
# Linear time: the text is split at the quote characters once, so a string is a run of pieces
# (a piece that ends in an odd number of backslashes ends at an escaped quote), and a value is
# decoded by splitting each piece at its backslashes. No loop walks single characters.
json_str() {
  [ -n "${2:-}" ] || return 0
  printf '%s' "${1:-}" 2>/dev/null | JSON_KEYS="$2" LC_ALL=C awk -v NUL=0 "$_JSON_AWK" 2>/dev/null || true
  return 0
}

# json_fields <json> <key>... — the value json_str gives for each key, in the order of the keys, each followed by a NUL
# byte (an empty value for a key that is missing or not a string), with its trailing newlines dropped as $(...) drops
# them: one awk pass for all the keys. Read the values with `IFS= read -r -d '' <var>`, one read per key. The exit
# status is always 0.
json_fields() {
  local j="${1:-}" keys="" k
  shift
  for k in "$@"; do keys="$keys$k
"; done
  printf '%s' "$j" 2>/dev/null | JSON_KEYS="$keys" LC_ALL=C awk -v NUL=1 "$_JSON_AWK" 2>/dev/null || true
  return 0
}
