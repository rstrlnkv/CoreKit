#!/usr/bin/env bash
# Guards this public repo against personal data and private references in tracked files:
# - absolute home paths (/Users/, /home/, C:\Users\);
# - email addresses (example.com, example.org, noreply addresses and git@ SSH remotes are fine);
# - the owner's handle (read from marketplace.json) outside the files that must carry it;
# - references to the private design spec ("spec section", "spec §", "spec D<n>") anywhere (docs/ is published
#   too), and to a private ADR ("ADR 009") in a shipped plugin file (a template's "ADR 001" heading is allowed), and to a
#   private plan or task ("plan 3c", "task 4") in a shipped plugin file;
# - owner-specific terms from a local list that never enters the repo (see PERSONAL TERMS below);
# - any project name listed in the owner's private PROJECTS.md (the list never enters the repo).
# Scans tracked files only (git ls-files -z); binary files are skipped. The output names the file,
# the line and the kind of hit, never the matched text.
#
# PERSONAL TERMS: $PERSONAL_TERMS, else tests/personal-terms.local in this checkout, else the same
# file in the main checkout (for a git worktree). It is gitignored. One "<kind> <term>" per line,
# "#" starts a comment; the term is matched as a whole word, ignoring case:
#   name <term>       anywhere (full-name variants, user names)
#   standard <term>   in plugins/*/skills, agents, reference and templates (the owner's own standard files)
#   archive <term>    anywhere (names of old projects)
# Without the file these checks are skipped (a SKIP line).
source "$(dirname "$0")/lib.sh"
# The real Core must be found before new_sandbox swaps HOME and CORE_DIR. It is only read. Under run.sh, HOME is
# already a throwaway one: run.sh passes the real place as REAL_CORE_DIR, to this file alone.
REAL_CORE="${REAL_CORE_DIR:-${CORE_DIR:-$HOME/Projects/Core}}"
TERMS="${PERSONAL_TERMS:-$ROOT/tests/personal-terms.local}"
if [ -z "${PERSONAL_TERMS:-}" ] && [ ! -f "$TERMS" ]; then
  common="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  [ -n "$common" ] && [ -f "$(dirname "$common")/tests/personal-terms.local" ] && TERMS="$(dirname "$common")/tests/personal-terms.local"
fi
new_sandbox

SELF="tests/test_no_personal.sh"
# Words that are also part of this repo's own vocabulary: never a "personal" project name.
GENERIC='core corekit corecrew coremodel coreopinion test-coredev demo test tests example examples sample project projects code docs todo hello world'

# project_names <PROJECTS.md> — one name per line, from list items "- <name> — <purpose> — <path>".
# Drops names under 4 characters and generic words. Names are only ever written to a file.
project_names() {
  [ -f "$1" ] || return 0
  sed -n 's/^[-*][[:space:]][[:space:]]*//p' "$1" | sed 's/[[:space:]]*—.*$//; s/[[:space:]]*$//' |
    while IFS= read -r n; do
      [ "${#n}" -ge 4 ] || continue
      low="$(printf '%s' "$n" | tr '[:upper:]' '[:lower:]')"
      case " $GENERIC " in *" $low "*) continue ;; esac
      printf '%s\n' "$n"
    done
}

# terms_of <terms-file> <kind> — the terms of one kind, one per line
terms_of() {
  [ -f "$1" ] || return 0
  sed -n "s/^[[:space:]]*$2[[:space:]][[:space:]]*//p" "$1" | sed 's/[[:space:]]*$//' | grep -v '^$'
}

# is_binary <file> — true when the file holds a NUL byte
is_binary() { [ "$(LC_ALL=C tr -d '\000' < "$1" | wc -c)" != "$(wc -c < "$1")" ]; }

# lines <label> <rel> <grep args...> — "<rel>:<line>: <label>" per matching line (never the text)
lines() {
  local label="$1" rel="$2"; shift 2
  grep -n "$@" 2>/dev/null | sed "s|:.*||" | while IFS= read -r ln; do
    echo "$rel:$ln: $label"
  done
}

# emails <rel> <file> — lines with an email address other than the allowed kinds
emails() {
  LC_ALL=C grep -noE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$2" 2>/dev/null \
    | LC_ALL=C grep -viE ':(git@|[^@]*noreply[^@]*@|[^@]*@([a-z0-9-]+\.)*noreply\.)|@example\.(com|org)$' \
    | sed 's|:.*||' | LC_ALL=C sort -un | while IFS= read -r ln; do echo "$1:$ln: email address"; done
}

# scan_repo <root> <names-file> <handle> <terms-file> — checks every tracked text file at <root>.
# <names-file> and <terms-file> may be empty or missing: then those checks are skipped.
scan_repo() {
  local root="$1" names="$2" handle="$3" terms="$4" kind_file
  kind_file="$SANDBOX/kinds.$$"
  for k in name standard archive; do terms_of "$terms" "$k" > "$kind_file.$k"; done
  git -C "$root" ls-files -z | while IFS= read -r -d '' rel; do
    local f="$root/$rel"
    [ "$rel" = "$SELF" ] && continue
    [ -f "$f" ] || continue
    is_binary "$f" && continue
    lines 'absolute home path (/Users/, /home/ or C:\Users\)' "$rel" -iE '/Users/|/home/|[a-z]:[\\/]Users[\\/]' "$f"
    emails "$rel" "$f"
    case "$rel" in
      .claude-plugin/*.json|LICENSE|CHANGELOG.md|SECURITY.md|ARCHITECTURE.md|CONTRIBUTING.md|README.md|README.*.md|docs/*) ;;
      plugins/*/.claude-plugin/*.json|plugins/*/.codex-plugin/*.json|plugins/*/README.md|plugins/*/README.*.md|plugins/*/CHANGELOG.md) ;;
      *) [ -n "$handle" ] && lines "owner handle outside manifests, READMEs, LICENSE, CHANGELOGs, SECURITY, ARCHITECTURE, CONTRIBUTING, docs" "$rel" -iwF -- "$handle" "$f" ;;
    esac
    lines "reference to the private spec" "$rel" -E 'spec section|spec §|spec D[0-9]' "$f"
    # a shipped file may not cite a private ADR ("ADR 009"); a template's "ADR 001" heading is the user's own record
    case "$rel" in
      plugins/*/templates/*) ;;
      plugins/*) lines "reference to a private ADR" "$rel" -E 'ADR [0-9]' "$f" ;;
    esac
    # nor a private plan or its steps ("see the plan 3c", "task 4 adds"): the reader of a shipped file has neither
    case "$rel" in
      plugins/*) lines "reference to a private plan or task" "$rel" -E '[Pp]lan [0-9]|[Tt]ask [0-9]' "$f" ;;
    esac
    [ -s "$kind_file.name" ] && lines "a personal name from the local terms list" "$rel" -iwF -f "$kind_file.name" "$f"
    case "$rel" in
      plugins/*/skills/*|plugins/*/agents/*|plugins/*/reference/*|plugins/*/templates/*)
        [ -s "$kind_file.standard" ] && lines "owner standard file name" "$rel" -iwF -f "$kind_file.standard" "$f" ;;
    esac
    [ -s "$kind_file.archive" ] && lines "archive project name" "$rel" -iwF -f "$kind_file.archive" "$f"
    [ -s "$names" ] && lines "a project name from PROJECTS.md" "$rel" -iwF -f "$names" "$f"
  done
  rm -f "$kind_file".*
}

# --- Self-check: plant every kind of leak in a throwaway repo; each must be caught once. -------
# The handle and the terms are made up here; the real ones never appear in this file.
R="$SANDBOX/repo"
SK="$R/plugins/p/skills/s"
mkdir -p "$R/docs" "$SK" "$R/tests" "$R/.claude-plugin" "$R/skills/s"
git -C "$R" init -q
FT="$SANDBOX/fake-terms"
printf '# fake terms\nname Quentin Zarbo\nname Zarbo\nstandard house-style.md\narchive Grimlock\n\n' > "$FT"
H=/Users; U="$H/someone/x"; V="/ho""me/someone"; W='C:\Users\someone'    # built here so this file stays clean
printf 'path %s\n' "$U" > "$R/tests/leak-path.sh"          # hit: home path
printf 'path %s\n' "$V" > "$SK/leak-home.md"               # hit: home path
printf 'path %s\n' "$W" > "$SK/leak-win.md"                # hit: Windows home path
printf 'path %s\n' "$U" > "$R/CHANGELOG.md"                # hit: a CHANGELOG is scanned too
printf 'mail me@mail.test\n' > "$SK/mail.md"               # hit: email
printf 'a@example.com git@github.com:x/y n@users.noreply.github.com noreply@vendor.test\n' > "$SK/mail-ok.md"   # allowed emails
printf 'owner zhandle\n' > "$SK/handle.md"                 # hit: handle
printf 'owner zhandle\n' > "$R/README.md"                  # allowed
printf 'owner zhandle\n' > "$R/README.ru.md"               # allowed: a translation
printf '{"owner":"zhandle"}\n' > "$R/.claude-plugin/plugin.json"   # allowed
printf 'owner zhandle\n' > "$R/LICENSE"                    # allowed
printf 'owner zhandle\n' > "$R/SECURITY.md"                # allowed: root SECURITY.md
printf 'owner zhandle\n' > "$R/ARCHITECTURE.md"            # allowed: root ARCHITECTURE.md
printf 'owner zhandle\n' > "$R/CONTRIBUTING.md"            # allowed: root CONTRIBUTING.md
printf 'owner zhandle\n' > "$R/tests/SECURITY.md"          # hit: only the root file is allowed
printf 'zhandles\n' > "$R/tests/word.md"                   # fine: not the whole word
mkdir -p "$R/plugins/p/.claude-plugin" "$R/plugins/p/.codex-plugin" "$R/plugins/p/hooks"
printf '{"owner":"zhandle"}\n' > "$R/plugins/p/.claude-plugin/plugin.json"   # allowed: a plugin's manifest
printf '{"owner":"zhandle"}\n' > "$R/plugins/p/.codex-plugin/plugin.json"   # allowed: a plugin's Codex manifest
printf 'owner zhandle\n' > "$R/plugins/p/README.md"        # allowed: a plugin's README
printf 'owner zhandle\npath %s\n' "$U" > "$R/plugins/p/CHANGELOG.md"   # handle allowed; line 2 hit: home path
printf 'owner zhandle\n' > "$R/plugins/p/hooks/h.ts"       # hit: a plugin's code
printf 'see spec section 4\n' > "$R/plugins/p/hooks/s.sh"  # hit: private spec
printf 'see spec §4.2 and spec D17\n' > "$R/tests/spec.sh" # hit once: private spec
printf 'see spec section 4\n' > "$R/docs/design.md"        # hit: docs/ is published too
printf 'see ADR 009\n' > "$R/plugins/p/hooks/adr.sh"       # hit: a private ADR in a shipped file
mkdir -p "$SK/templates"; printf '# ADR 001: stack\n' > "$SK/templates/d.md.tmpl"   # allowed: the user's own ADR
mkdir -p "$R/plugins/p/templates/docs"; printf '# ADR 001: stack\n' > "$R/plugins/p/templates/docs/d.md.tmpl"   # allowed: the same, plugin level
printf 'LIMIT (ADR 009)\n' > "$R/tests/adr.sh"             # allowed: tests are not shipped
printf 'see the plan 3c\n' > "$R/plugins/p/hooks/plan.sh"  # hit: a private plan in a shipped file
printf 'Task 4 adds it\n' > "$R/plugins/p/hooks/task.sh"   # hit: a private task in a shipped file
printf 'plan 3c, task 4\n' > "$R/tests/plan.sh"            # allowed: tests are not shipped
printf 'by Quentin Zarbo\n' > "$R/plugins/p/hooks/n.sh"    # hit: a personal name
printf 'zarbo was here\n' > "$R/docs/n.md"                 # hit: names are flagged in docs/ too
printf 'see house-style.md\n' > "$SK/std.md"               # hit: owner standard
mkdir -p "$R/plugins/p/templates"; printf 'see house-style.md\n' > "$R/plugins/p/templates/t.md"   # hit: owner standard in a plugin-level template
printf 'see house-style.md\n' > "$R/skills/s/std.md"       # fine: not the plugins/*/skills layout
printf 'see house-style.md\n' > "$R/docs/ok2.md"           # allowed: outside skills/agents/reference/templates
printf 'a Grimlock chart\n' > "$SK/old.md"                 # hit: archive name
printf 'a grimlocked door\n' > "$SK/fine.md"               # fine: not a whole word
printf 'Grimlock game\n' > "$R/docs/ok3.md"                # hit: docs/ too
printf 'x\000%s\n' "$U" > "$SK/blob.bin"                   # skipped: binary
printf 'path %s\n' "$U" > "$R/tests/a b.sh"                # hit: name with a space
git -C "$R" add -A >/dev/null
printf 'path %s\n' "$U" > "$R/untracked.sh"                # not tracked: not scanned
hits="$(scan_repo "$R" "" zhandle "$FT" | LC_ALL=C sort)"
want='CHANGELOG.md:1: absolute home path (/Users/, /home/ or C:\Users\)
docs/design.md:1: reference to the private spec
docs/n.md:1: a personal name from the local terms list
docs/ok3.md:1: archive project name
plugins/p/CHANGELOG.md:2: absolute home path (/Users/, /home/ or C:\Users\)
plugins/p/hooks/adr.sh:1: reference to a private ADR
plugins/p/hooks/h.ts:1: owner handle outside manifests, READMEs, LICENSE, CHANGELOGs, SECURITY, ARCHITECTURE, CONTRIBUTING, docs
plugins/p/hooks/n.sh:1: a personal name from the local terms list
plugins/p/hooks/plan.sh:1: reference to a private plan or task
plugins/p/hooks/s.sh:1: reference to the private spec
plugins/p/hooks/task.sh:1: reference to a private plan or task
plugins/p/skills/s/handle.md:1: owner handle outside manifests, READMEs, LICENSE, CHANGELOGs, SECURITY, ARCHITECTURE, CONTRIBUTING, docs
plugins/p/skills/s/leak-home.md:1: absolute home path (/Users/, /home/ or C:\Users\)
plugins/p/skills/s/leak-win.md:1: absolute home path (/Users/, /home/ or C:\Users\)
plugins/p/skills/s/mail.md:1: email address
plugins/p/skills/s/old.md:1: archive project name
plugins/p/skills/s/std.md:1: owner standard file name
plugins/p/templates/t.md:1: owner standard file name
tests/SECURITY.md:1: owner handle outside manifests, READMEs, LICENSE, CHANGELOGs, SECURITY, ARCHITECTURE, CONTRIBUTING, docs
tests/a b.sh:1: absolute home path (/Users/, /home/ or C:\Users\)
tests/leak-path.sh:1: absolute home path (/Users/, /home/ or C:\Users\)
tests/spec.sh:1: reference to the private spec'
assert_eq "$hits" "$want" "planted leaks"
printf '%s' "$hits" | grep -qiE 'zarbo|grimlock|house-style|zhandle|mail\.test' && fail "output leaked a planted term" || pass
assert_eq "$(scan_repo "$R" "" "" "$SANDBOX/missing" | grep -c 'handle\|terms list\|archive\|standard')" "0" "no handle and no terms file: those checks are skipped"

# PROJECTS.md self-check: fake list, fake names; a name never shows up in the output.
FAKE="$SANDBOX/fake-PROJECTS.md"
cat > "$FAKE" <<'EOF'
# Projects

One line per project: name — purpose — path to code.

- Zorblax Quill — fake purpose — Zorblax Quill/code/
- app — too short — app/code/
- Demo — generic word — Demo/code/
- corecrew — generic word — corecrew/code/
- Frumbly — fake purpose — Frumbly/code/
EOF
project_names "$FAKE" > "$SANDBOX/names"
assert_eq "$(tr '\n' ';' < "$SANDBOX/names")" "Zorblax Quill;Frumbly;" "extracted names"
P="$SANDBOX/repo2"; mkdir -p "$P/skills" "$P/docs"; git -C "$P" init -q
printf 'Uses the zorblax quill library\n' > "$P/skills/leak.md"      # hit: case-insensitive phrase
printf 'a frumbly day\nfrumblyish\n' > "$P/skills/word.md"           # hit line 1 only (whole word)
printf 'app demo corecrew test\n' > "$P/skills/generic.md"            # fine: short / generic names
printf 'Frumbly lives here\n' > "$P/docs/ok.md"                      # hit: docs/ is published too
git -C "$P" add -A >/dev/null
out="$(scan_repo "$P" "$SANDBOX/names" "" "" | LC_ALL=C sort)"
assert_eq "$(echo "$out" | tr '\n' ';')" "docs/ok.md:1: a project name from PROJECTS.md;skills/leak.md:1: a project name from PROJECTS.md;skills/word.md:1: a project name from PROJECTS.md;" "fake project names"
printf '%s' "$out" | grep -qiE 'zorblax|frumbly' && fail "output leaked a project name" || pass
assert_eq "$(project_names "$SANDBOX/missing.md")" "" "missing PROJECTS.md gives no names"

# --- The real repo ----------------------------------------------------------------------------
HANDLE="$(sed -n 's/.*"owner": *{ *"name": *"\([^"]*\)".*/\1/p' "$ROOT/.claude-plugin/marketplace.json" | head -1)"
[ -n "$HANDLE" ] && pass || fail "cannot read the owner handle from marketplace.json"
if [ -f "$REAL_CORE/PROJECTS.md" ]; then
  # a real check: the names come from the list items (never more names than items)
  project_names "$REAL_CORE/PROJECTS.md" > "$SANDBOX/real-names" \
    && [ "$(wc -l < "$SANDBOX/real-names")" -le "$(grep -c '^[-*][[:space:]]' "$REAL_CORE/PROJECTS.md")" ] \
    && pass || fail "could not read project names from the Core's PROJECTS.md"
else
  : > "$SANDBOX/real-names"
  skip project-names "no PROJECTS.md in the Core"
fi
if [ -f "$TERMS" ]; then
  [ -n "$(terms_of "$TERMS" name)$(terms_of "$TERMS" standard)$(terms_of "$TERMS" archive)" ] \
    && pass || fail "the personal terms list has no usable line: $TERMS"
else
  skip personal-terms "no tests/personal-terms.local"
fi
scan_repo "$ROOT" "$SANDBOX/real-names" "$HANDLE" "$TERMS" > "$SANDBOX/real-hits"
[ -s "$SANDBOX/real-hits" ] && fail "personal data in tracked files: $(tr '\n' ' ' < "$SANDBOX/real-hits")" || pass
finish
