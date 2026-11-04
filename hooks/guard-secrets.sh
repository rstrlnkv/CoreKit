#!/usr/bin/env bash
# Claude Code PreToolUse hook on Read|Edit|MultiEdit|Write|NotebookEdit|Grep|Glob|Bash: secrets are not
# read. Inside a Core project it blocks .env, .env.* and ~/.ssh/**, with exit 2 and the message
#   corecrew: reading secrets is blocked (<path>)
#   Ask the user to check the value themselves, or use .env.example.
# (spec section 14, item 4). <path> is the path as the tool was given it (a "~" stays a "~", a relative
# path stays relative); nothing is ever printed to stdout.
#
# What is a secret (letter case does not matter, ASCII only):
# - A file named .env, or .env.<anything> except the exact names .env.example, .env.sample and
#   .env.template (so .env.local.example is a secret). The NAME of the last path component counts,
#   wherever the file is: a secret basename is a secret in any folder. A link is followed, so
#   notes.txt -> .env is a secret, and so is a link NAMED .env.x that points elsewhere. Not secrets:
#   .envrc, .environment, .env-backup, foo.env, src/env.ts, a folder named .env (venv/.env/bin/activate).
#   (.envrc: direnv files often hold secrets, but the spec lists only .env and .env.*.)
# - $HOME/.ssh itself and anything under it, after ".." and symlinks are resolved (a folder link into
#   ~/.ssh counts). "~", "$HOME" and "${HOME}" at the start of a path are expanded.
# Tools and keys: Read, Edit, MultiEdit, Write -> file_path; NotebookEdit -> notebook_path; Grep -> path and
#   glob (the pattern is a regex, not a path); Glob -> pattern and path; Bash -> command. Any other tool
#   passes. A glob names a secret when its last component does (**/.env, .env*, .env.*, not **/*), or
#   when its literal part before the first * ? [ { is ~/.ssh or under it (~/.ssh/**). **/* passes. A glob
#   that starts with ! is an exclusion and passes. Path and glob are also judged joined as path/glob (Grep
#   path + glob, Glob path + pattern), so path ~ with glob .ssh/* is blocked; an absolute glob or an
#   exclusion is not joined.
#   Grep and Glob only list or search, but the spec lists them, so they are judged like a read.
# Bash is best effort. The arguments of the file-reading commands cat less more head tail source "." grep
#   egrep fgrep rg ag sed awk cp scp base64 xxd od strings diff open vim nano code (and some more, see
#   scripts/bashlex-guard-secrets.awk) and the word after an input redirect (< .env) are judged. grep/rg/sed/
#   awk skip their pattern or script operand (grep .env README.md is fine). cp and scp judge the sources,
#   not the destination (cp .env.example .env is fine). Quoted text is not a command, heredoc bodies and
#   comments are skipped, wrapper words (sudo, env, time) are skipped, and command substitutions are looked
#   into, also inside double quotes: export $(cat .env), echo "$(cat .env)", x="`cat .env`" (the body is
#   lexed again as a command line). `<> .env` (read and write) counts as a read.
#   grep/rg/rsync options that take a value (-A 2, -m 1, -g '*.ts', -t ts, --exclude .env, ...) are known, so
#   their value is not mistaken for the pattern or a source: `grep -A 2 .env .gitignore`, `rg -g '*.ts' .env
#   src` and `rsync -av --exclude .env src/ host:/` pass; `-e`/`--regexp` values are patterns; `-f FILE`,
#   `-g GLOB`/`--include` and `--exclude-from FILE` values are judged as files. A cluster is read letter by
#   letter: the first value-taking letter takes what follows it (-A2n) or, at the end, the next word (-rnA 2).
#   The tokenizer is the one linear awk pass of guard-code (scripts/bash-lex.awk). After a cd the name
#   rule still applies (cd .. && cat .env is blocked) but a relative ~/.ssh is unknown. Not caught: git
#   (git add .env is not a read; git show HEAD:.env is), output redirects, ls, a recursive grep over a
#   folder, variables other than a leading $HOME, sh -c "...", scripts, a link with an innocent name.
#   When the lexer stops early (more than 200 candidates, or <<"WORD" inside "$(...)") the rest of the command
#   is unknown: if the command text has a secret-looking string (see raw_hit below) the hook fails closed.
#   The tokenizer lives in scripts/bash-lex.awk and scripts/bashlex-guard-secrets.awk: if they are missing
#   the Bash path fails open (silently); the file tools are still judged. If awk is there but fails, the
#   hook fails closed when the command has a secret-looking string.
# - Inert outside a project (docs/specs/2026-11-04-project-layout-design.md section 4: <Core>/<project>/
#   or its code folder beside the Core): cwd missing or not in a project -> exit 0 at once (so ~/.ssh is
#   open when Claude works outside a project, spec D17). No network, no git.
#
# Fail closed (the one hook that does): the input is odd when a path key the tool needs cannot be read
# as a clean string (truncated JSON, a number, an array, an object, null, a key spelled with an escape);
# a Grep/Glob key that is optional counts only when it is present. Then the raw text is scanned, and
# exit 2 follows when it has a secret-looking string: a path component .env or .env.<not
# example|sample|template>, or a /.ssh folder. Shown in the message: that component (".env", ".ssh").
# The same scan covers a path key that occurs twice (the parser reads the first, the tool the last):
# every "<key>": "<value>" in the raw text is judged like the parsed value. Other keys (content,
# old_string, new_string, pattern of a Grep, description) are never looked at, so a Write whose
# content mentions .env or ~/.ssh passes, and so does odd input that has no secret-looking string.
# An odd input with no cwd, or with a cwd outside a project, is inert like any other.
SELF="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || exit 0
in=""; [ -t 0 ] || in="$(cat)"
. "$SELF/scripts/lib.sh" 2>/dev/null || exit 0
. "$SELF/hooks/messages.sh" 2>/dev/null || exit 0   # msg: every text, in the ui_language setting

tool="$(json_str "$in" tool_name)"
case "$tool" in Read|Edit|MultiEdit|Write|NotebookEdit|Grep|Glob|Bash) ;; *) exit 0 ;; esac
cwd="$(json_str "$in" cwd)"
[ -n "$cwd" ] || exit 0
load_settings
project_of "$cwd" >/dev/null || exit 0

die() {
  printf '%s\n%s\n' "$(msg secrets_blocked "$1")" "$(msg secrets_ask)" >&2
  exit 2
}

# is_secret_name <name> — exit 0 for .env, .env.<x> (x not example, sample, template) and a name that
# is .env followed by a glob character. No process is started.
is_secret_name() {
  case "$1" in
    [.][eE][nN][vV]) return 0 ;;
    [.][eE][nN][vV][.][eE][xX][aA][mM][pP][lL][eE]|[.][eE][nN][vV][.][sS][aA][mM][pP][lL][eE]|[.][eE][nN][vV][.][tT][eE][mM][pP][lL][aA][tT][eE]) return 1 ;;
    [.][eE][nN][vV][.]*) return 0 ;;
    [.][eE][nN][vV][*?[{]*) return 0 ;;
  esac
  return 1
}

SSH_LEX=""; SSH_CAN=""; SSH_DONE=""
# under_ssh <lower-case absolute path> — exit 0 when it is ~/.ssh or below (the folder as typed or resolved).
under_ssh() {
  local s
  if [ -z "$SSH_DONE" ]; then
    SSH_DONE=1
    if [ -n "${HOME:-}" ] && [ "$HOME" != "/" ]; then
      SSH_LEX="$(lc "$(norm_path "$HOME/.ssh")")"; SSH_CAN="$(lc "$(canon_dir "$HOME/.ssh")")"
    fi
  fi
  for s in "$SSH_LEX" "$SSH_CAN"; do
    [ -n "$s" ] || continue
    case "$1" in "$s"|"$s"/*) return 0 ;; esac
  done
  return 1
}

# is_secret <path or glob as given> [unknown] — exit 0 when it names a secret. With a second argument
# a relative path has no known folder (after a cd): only its name is judged.
is_secret() {
  local p="$1" unk="${2:-}" h last pre lex globby=0
  case "$p" in "!"*) return 1 ;; esac   # an exclusion glob
  h='$HOME'; case "$p" in "$h"|"$h"/*) p="$HOME${p#"$h"}" ;; esac
  h='${HOME}'; case "$p" in "$h"|"$h"/*) p="$HOME${p#"$h"}" ;; esac
  [ -n "$p" ] || return 1
  while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  last="${p##*/}"
  is_secret_name "$last" && return 0
  if [ -n "$unk" ]; then case "$p" in /*|"~"|"~/"*) ;; *) return 1 ;; esac; fi
  # the literal part before the first glob character (the whole path when there is none)
  pre="$p"
  case "$p" in *[*?[{]*) pre="${p%%[*?[{]*}"; globby=1 ;; esac
  [ -n "$pre" ] || return 1
  resolve_abs "$pre"
  lex="$(expand_home "$pre")"
  case "$lex" in /*) ;; *) lex="$cwd/$lex" ;; esac
  lex="$(norm_path "$lex")"
  under_ssh "$(lc "$lex")" && return 0
  under_ssh "$(lc "$ABS")" && return 0
  if [ "$globby" = 0 ]; then is_secret_name "${ABS##*/}" && return 0; fi
  return 1
}

# raw_hit — stdin: raw input text. Prints what looks like a secret path in it and exits 0, or exits 1.
# The text is cut into components at / \ " whitespace , : ; = ( ) < > | & { } ` ' ; a component is
# .env or .env.<x> (x not example|sample|template) or .env followed by * or ?; "/.ssh" ends a path
# or is followed by a separator.
raw_hit() {
  local t hit
  t="$(cat)"
  hit="$(printf '%s' "$t" | LC_ALL=C tr '\134\057\042[:space:]\054:;=()<>&|\173\175\140\047' '\n' \
    | LC_ALL=C grep -iE '^\.env([*?]|\.|$)' | LC_ALL=C grep -viE '^\.env\.(example|sample|template)$' | head -n 1)"
  if [ -n "$hit" ]; then printf '%s' "$hit"; return 0; fi
  if printf '%s' "$t" | LC_ALL=C grep -qiE '/\.ssh([/"\\]|$)'; then printf '.ssh'; return 0; fi
  return 1
}

# --- Bash: the candidates found by one awk pass, judged here.
if [ "$tool" = Bash ]; then
  cmd="$(json_str "$in" command)"
  if [ -z "$cmd" ]; then
    hit="$(printf '%s' "$in" | raw_hit)" && die "$hit"
    exit 0
  fi
  # Cheap exit: no .env and no .ssh anywhere in the command.
  printf '%s' "$cmd" | LC_ALL=C grep -qiE '\.env|\.ssh' || exit 0
  [ -r "$SELF/scripts/bash-lex.awk" ] && [ -r "$SELF/scripts/bashlex-guard-secrets.awk" ] || exit 0
  targets="$(printf '%s' "$cmd" | LC_ALL=C tr '\n\r' '\002 ' | LC_ALL=C awk -f "$SELF/scripts/bash-lex.awk" -f "$SELF/scripts/bashlex-guard-secrets.awk" 2>/dev/null)"
  # awk itself failed: the command is unknown, so a secret-looking string in it is refused
  if [ "$?" -ne 0 ]; then hit="$(printf '%s' "$cmd" | raw_hit)" && die "$hit"; exit 0; fi
  [ -n "$targets" ] || exit 0
  TAB="$(printf '\t')"
  stopped=""
  while IFS="$TAB" read -r kind a unk; do
    if [ "$kind" = X ]; then stopped=1; continue; fi
    [ "$kind" = P ] || continue
    u=""; [ "$unk" = 1 ] && u=1
    if is_secret "$a" "$u"; then die "$a"; fi
  done <<< "$targets"
  # the lexer stopped early: what is left of the command is unknown
  if [ -n "$stopped" ]; then hit="$(printf '%s' "$cmd" | raw_hit)" && die "$hit"; fi
  exit 0
fi

# --- File tools, Grep, Glob: the path keys of the tool input.
req=""; opt=""
case "$tool" in
  Read|Edit|MultiEdit|Write) req="file_path" ;;
  NotebookEdit) req="notebook_path" ;;
  Grep) opt="path glob" ;;
  Glob) req="pattern"; opt="path" ;;
esac
hint=""
printf '%s' "$in" | LC_ALL=C grep -qiE '\.env|\.ssh' && hint=1
for key in $req $opt; do
  v="$(json_str "$in" "$key")"
  if [ -n "$v" ]; then
    if is_secret "$v"; then die "$v"; fi
  fi
  [ -n "$hint" ] || continue
  # odd shape: no clean string where the tool needs one (an optional key only when it is there at all)
  if [ -z "$v" ]; then
    odd=""
    case " $req " in *" $key "*) odd=1 ;; esac
    if [ -z "$odd" ] && printf '%s' "$in" | LC_ALL=C grep -qE "\"$key\"[[:space:]]*:" \
       && ! printf '%s' "$in" | LC_ALL=C grep -qE "\"$key\"[[:space:]]*:[[:space:]]*\"\""; then odd=1; fi
    if [ -n "$odd" ]; then hit="$(printf '%s' "$in" | raw_hit)" && die "$hit"; fi
  fi
  # every "<key>": "<value>" in the raw text, in case the key occurs more than once
  vals="$(printf '%s' "$in" | LC_ALL=C grep -oE "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"")"
  if [ -n "$vals" ]; then
    while IFS= read -r line; do
      line="${line#*:}"; line="${line#*\"}"; line="${line%\"}"; line="${line//\\/}"
      [ -n "$line" ] || continue
      if is_secret "$line"; then die "$line"; fi
    done <<< "$vals"
  fi
done
# path and glob together: Grep path + glob, Glob path + pattern
jp=""; jg=""
case "$tool" in
  Grep) jp="$(json_str "$in" path)"; jg="$(json_str "$in" glob)" ;;
  Glob) jp="$(json_str "$in" path)"; jg="$(json_str "$in" pattern)" ;;
esac
if [ -n "$jp" ] && [ -n "$jg" ]; then
  case "$jg" in "!"*|/*|"~"*|'$HOME'*|'${HOME}'*) ;; *)
    j="${jp%/}/$jg"
    if is_secret "$j"; then die "$j"; fi ;;
  esac
fi
exit 0
