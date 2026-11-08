#!/usr/bin/env bash
# Guards this public repo against personal data and private references in tracked files:
# - absolute home paths (/Users/, /home/, C:\Users\);
# - email addresses (example.com, example.org, noreply addresses and git@ SSH remotes are fine);
# - the owner's handle (read from marketplace.json) outside the files that must carry it;
# - references to the private design spec ("spec section", "spec §", "spec D<n>") outside docs/;
# - owner-specific terms from a local list that never enters the repo (see PERSONAL TERMS below);
# - any project name listed in the owner's private PROJECTS.md (the list never enters the repo).
# Scans tracked files only (git ls-files -z); binary files are skipped. The output names the file,
# the line and the kind of hit, never the matched text.
#
# PERSONAL TERMS: $PERSONAL_TERMS, else tests/personal-terms.local in this checkout, else the same
# file in the main checkout (for a git worktree). It is gitignored. One "<kind> <term>" per line,
# "#" starts a comment; the term is matched as a whole word, ignoring case:
#   name <term>       anywhere (full-name variants, user names)
#   standard <term>   in plugins/*/skills, agents and reference (the owner's own standard files)
#   archive <term>    outside docs/specs and docs/plans (names of old projects)
# Without the file these checks are skipped with a note.
source "$(dirname "$0")/lib.sh"
# The real Core must be found before new_sandbox swaps HOME and CORE_DIR. It is only read.
REAL_CORE="${CORE_DIR:-$HOME/Projects/Core}"
TERMS="${PERSONAL_TERMS:-$ROOT/tests/personal-terms.local}"
if [ -z "${PERSONAL_TERMS:-}" ] && [ ! -f "$TERMS" ]; then
  common="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  [ -n "$common" ] && [ -f "$(dirname "$common")/tests/personal-terms.local" ] && TERMS="$(dirname "$common")/tests/personal-terms.local"
fi
new_sandbox

SELF="tests/test_no_personal.sh"
# Words that are also part of this repo's own vocabulary: never a "personal" project name.
GENERIC='core corekit corecrew coremodel coreopinion test-coredev demo test tests example examples sample project projects code docs todo hello world'
# Files that still cite the private spec; their streams remove the references (refactor plan, PUB-9).
# Listed here they are skipped with a note; delete an entry once its file is clean.
SPEC_PENDING='plugins/corecrew/hooks/guard-code.sh plugins/corecrew/hooks/guard-secrets.sh plugins/corecrew/scripts/check-standard.sh plugins/corecrew/skills/new-project/scripts/preflight.sh plugins/coremodel/hooks/models.ts plugins/coremodel/hooks/policy.ts plugins/coremodel/hooks/register.tsx plugins/coremodel/tests/flow.test.ts plugins/coremodel/tests/ui.test.tsx tests/fixtures/make-test-coredev.sh tests/test_agents.sh tests/test_fixture.sh tests/test_task_skill.sh'

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
    case "$rel" in
      docs/specs/*|docs/plans/*|CHANGELOG.md|plugins/*/CHANGELOG.md) ;;
      *) lines 'absolute home path (/Users/, /home/ or C:\Users\)' "$rel" -iE '/Users/|/home/|[a-z]:[\\/]Users[\\/]' "$f" ;;
    esac
    emails "$rel" "$f"
    case "$rel" in
      .claude-plugin/*.json|LICENSE|CHANGELOG.md|SECURITY.md|ARCHITECTURE.md|CONTRIBUTING.md|README.md|README.*.md|docs/*) ;;
      plugins/*/.claude-plugin/*.json|plugins/*/.codex-plugin/*.json|plugins/*/README.md|plugins/*/README.*.md|plugins/*/CHANGELOG.md) ;;
      *) [ -n "$handle" ] && lines "owner handle outside manifests, READMEs, LICENSE, CHANGELOGs, SECURITY, ARCHITECTURE, CONTRIBUTING, docs" "$rel" -iwF -- "$handle" "$f" ;;
    esac
    case "$rel" in
      docs/*) ;;
      *) case " $SPEC_PENDING " in
           *" $rel "*) ;;
           *) lines "reference to the private spec" "$rel" -E 'spec section|spec §|spec D[0-9]' "$f" ;;
         esac ;;
    esac
    [ -s "$kind_file.name" ] && lines "a personal name from the local terms list" "$rel" -iwF -f "$kind_file.name" "$f"
    case "$rel" in
      plugins/*/skills/*|plugins/*/agents/*|plugins/*/reference/*)
        [ -s "$kind_file.standard" ] && lines "owner standard file name" "$rel" -iwF -f "$kind_file.standard" "$f" ;;
    esac
    case "$rel" in
      docs/specs/*|docs/plans/*) ;;
      *) [ -s "$kind_file.archive" ] && lines "archive project name" "$rel" -iwF -f "$kind_file.archive" "$f" ;;
    esac
    case "$rel" in
      docs/*) ;;
      *) [ -s "$names" ] && lines "a project name from PROJECTS.md" "$rel" -iwF -f "$names" "$f" ;;
    esac
  done
  rm -f "$kind_file".*
}

# --- Self-check: plant every kind of leak in a throwaway repo; each must be caught once. -------
# The handle and the terms are made up here; the real ones never appear in this file.
R="$SANDBOX/repo"
SK="$R/plugins/p/skills/s"
mkdir -p "$R/docs/specs" "$R/docs/plans" "$SK" "$R/tests" "$R/.claude-plugin" "$R/skills/s"
git -C "$R" init -q
FT="$SANDBOX/fake-terms"
printf '# fake terms\nname Quentin Zarbo\nname Zarbo\nstandard house-style.md\narchive Grimlock\n\n' > "$FT"
H=/Users; U="$H/someone/x"; V="/ho""me/someone"; W='C:\Users\someone'    # built here so this file stays clean
printf 'path %s\n' "$U" > "$R/tests/leak-path.sh"          # hit: home path
printf 'path %s\n' "$V" > "$SK/leak-home.md"               # hit: home path
printf 'path %s\n' "$W" > "$SK/leak-win.md"                # hit: Windows home path
printf 'path %s\n' "$U" > "$R/docs/specs/ok.md"            # allowed: specs
printf 'path %s\n' "$U" > "$R/docs/plans/ok.md"            # allowed: plans
printf 'path %s\n' "$U" > "$R/CHANGELOG.md"                # allowed: changelog
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
printf 'owner zhandle\n' > "$R/plugins/p/CHANGELOG.md"     # allowed: a plugin's CHANGELOG
printf 'owner zhandle\n' > "$R/plugins/p/hooks/h.ts"       # hit: a plugin's code
printf 'see spec section 4\n' > "$R/plugins/p/hooks/s.sh"  # hit: private spec
printf 'see spec §4.2 and spec D17\n' > "$R/tests/spec.sh" # hit once: private spec
printf 'see spec section 4\n' > "$R/docs/design.md"        # allowed: docs/
printf 'by Quentin Zarbo\n' > "$R/plugins/p/hooks/n.sh"    # hit: a personal name
printf 'zarbo was here\n' > "$R/docs/n.md"                 # hit: names are flagged in docs/ too
printf 'see house-style.md\n' > "$SK/std.md"               # hit: owner standard
printf 'see house-style.md\n' > "$R/skills/s/std.md"       # fine: not the plugins/*/skills layout
printf 'see house-style.md\n' > "$R/docs/ok2.md"           # allowed: outside skills/agents/reference
printf 'a Grimlock chart\n' > "$SK/old.md"                 # hit: archive name
printf 'a grimlocked door\n' > "$SK/fine.md"               # fine: not a whole word
printf 'Grimlock notes\n' > "$R/docs/plans/old.md"         # allowed: plans
printf 'Grimlock game\n' > "$R/docs/ok3.md"                # hit: docs/ is not specs/plans
printf 'x\000%s\n' "$U" > "$SK/blob.bin"                   # skipped: binary
printf 'path %s\n' "$U" > "$R/tests/a b.sh"                # hit: name with a space
git -C "$R" add -A >/dev/null
printf 'path %s\n' "$U" > "$R/untracked.sh"                # not tracked: not scanned
hits="$(scan_repo "$R" "" zhandle "$FT" | LC_ALL=C sort)"
want='docs/n.md:1: a personal name from the local terms list
docs/ok3.md:1: archive project name
plugins/p/hooks/h.ts:1: owner handle outside manifests, READMEs, LICENSE, CHANGELOGs, SECURITY, ARCHITECTURE, CONTRIBUTING, docs
plugins/p/hooks/n.sh:1: a personal name from the local terms list
plugins/p/hooks/s.sh:1: reference to the private spec
plugins/p/skills/s/handle.md:1: owner handle outside manifests, READMEs, LICENSE, CHANGELOGs, SECURITY, ARCHITECTURE, CONTRIBUTING, docs
plugins/p/skills/s/leak-home.md:1: absolute home path (/Users/, /home/ or C:\Users\)
plugins/p/skills/s/leak-win.md:1: absolute home path (/Users/, /home/ or C:\Users\)
plugins/p/skills/s/mail.md:1: email address
plugins/p/skills/s/old.md:1: archive project name
plugins/p/skills/s/std.md:1: owner standard file name
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
printf 'Frumbly lives here\n' > "$P/docs/ok.md"                      # fine: docs/
git -C "$P" add -A >/dev/null
out="$(scan_repo "$P" "$SANDBOX/names" "" "" | LC_ALL=C sort)"
assert_eq "$(echo "$out" | tr '\n' ';')" "skills/leak.md:1: a project name from PROJECTS.md;skills/word.md:1: a project name from PROJECTS.md;" "fake project names"
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
  echo "  note: no PROJECTS.md in the Core; project-name check skipped"
fi
if [ -f "$TERMS" ]; then
  [ -n "$(terms_of "$TERMS" name)$(terms_of "$TERMS" standard)$(terms_of "$TERMS" archive)" ] \
    && pass || fail "the personal terms list has no usable line: $TERMS"
else
  echo "  note: no tests/personal-terms.local; personal-terms check skipped"
fi
for f in $SPEC_PENDING; do
  if [ -f "$ROOT/$f" ] && grep -qE 'spec section|spec §|spec D[0-9]' "$ROOT/$f"; then
    echo "  note: $f still cites the private spec (pending, PUB-9)"
  fi
done
scan_repo "$ROOT" "$SANDBOX/real-names" "$HANDLE" "$TERMS" > "$SANDBOX/real-hits"
[ -s "$SANDBOX/real-hits" ] && fail "personal data in tracked files: $(tr '\n' ' ' < "$SANDBOX/real-hits")" || pass
finish
