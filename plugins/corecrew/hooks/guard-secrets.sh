#!/usr/bin/env bash
# Claude Code and Codex PreToolUse hook on Read|Grep|Glob|Edit|Write|NotebookEdit|apply_patch|Bash:
# secrets are not read. Inside a Core project it blocks .env, .env.* and ~/.ssh/**, with exit 2 and the message
#   corecrew: reading secrets is blocked (<path>)
#   Ask the user to check the value themselves, or use .env.example.
# <path> is the path as the tool was given it (a "~" stays a "~", a relative
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
# Tools and keys: Read, Edit, Write -> file_path; NotebookEdit -> notebook_path; Grep -> path and
#   glob (the pattern is a regex, not a path); Glob -> pattern and path; Bash -> command. Any other tool
#   passes. A glob names a secret when its last component does (**/.env, .env*, .env.*, not **/*), or
#   when its literal part before the first * ? [ { is ~/.ssh or under it (~/.ssh/**). **/* passes. A glob
#   that starts with ! is an exclusion and passes. Path and glob are also judged joined as path/glob (Grep
#   path + glob, Glob path + pattern), so path ~ with glob .ssh/* is blocked; an absolute glob or an
#   exclusion is not joined.
#   Grep and Glob only list or search, but the spec lists them, so they are judged like a read.
# Codex: its shell is "Bash" and its file edits are "apply_patch" (tool_input.command is the patch text);
#   Read, Grep, Glob and NotebookEdit never fire there, so a read goes through Bash only. apply_patch:
#   the paths of Add File, Update File and Move to (the file written) and the source of a move are judged like
#   a file tool; Delete File passes (like `rm .env`). The patch body is never scanned (it may mention .env).
#   A text this hook cannot read as a patch (an X line, or no path at all) fails closed on a secret-looking string
#   in any line that holds "***"; with no such line it passes. More than 100 paths (a C line) are refused. Header
#   lines and paths are trimmed like Codex does (Unicode spaces too).
#   In Codex only (scripts/shell-patch.sh shell_patch_host), a patch handed to the shell is refused, not judged, with exit 2
#   and a message naming the match. BEST EFFORT, NOT A SECURITY BOUNDARY: the real boundary for secrets in Codex is a
#   sandbox profile: lib.sh codex-profile (SECURITY.md). The rule and its limits are in scripts/shell-patch.sh.
#   This refusal keeps the project gate of the hook (secrets are judged only in a project; guard-code refuses in every folder);
#   load_settings runs before project_of, so a core_dir that lives only in the settings file counts.
#   Limits: view_image (reads an image file) does not run the hook in Codex, so a secret reached through it is not
#   caught; write_stdin (typing into an open exec session): no evidence that it runs the hook (to be checked live).
#   The D kind (a delete) is not consumed.
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
#   The command line handed to bash -c, sh -c, zsh -c and eval is judged like any other (bash -c "cat .env").
#   Not judged: interpreters (python -c, node -e), find -exec, git show REV:.env, dd, curl @file.
#   Quotes and backslashes inside a name are removed by the lexer (.e'n'v is .env). A glob word that starts
#   with a dot and can match .env or .env.<x> (.e*, .en?, .[e]nv, .{e,x}nv), or a component that can match
#   .ssh (~/.s*/id_rsa), is judged as that name; a glob that starts with * ? [ does not match a dot in the shell
#   and passes, and so do .* and .??* (no letter in them). Wrapper options that take a value are skipped
#   (timeout 5, nice -n 5, sudo -u root, env -u X, stdbuf -o0). zip -x/-i patterns are not files.
#   Documented limits, not redesigned: a relative target after cd, xargs, find -exec, bash -c "...", and the
#   guard being inert outside a project cwd.
#   The tokenizer is one linear awk pass (scripts/bash-lex.awk, shared with both readers of guard-code: its write
#   check and the read-only rule). After a cd the name
#   rule still applies (cd .. && cat .env is blocked) but a relative ~/.ssh is unknown. Not caught: git
#   (git add .env is not a read; git show HEAD:.env is), output redirects, ls, a recursive grep over a
#   folder, variables other than a leading $HOME, sh -c "...", scripts, a link with an innocent name.
#   When the lexer stops early (more than 200 candidates, or <<"WORD" inside "$(...)") the rest of the command
#   is unknown: if the command text has a secret-looking string (see raw_hit below) the hook fails closed.
#   The tokenizer lives in scripts/bash-lex.awk and scripts/bashlex-guard-secrets.awk: if they are missing
#   the Bash path fails open (silently); the file tools are still judged. If awk is there but fails, the
#   hook fails closed when the command has a secret-looking string.
# - Inert outside a project (<Core>/<project>/
#   or its code folder beside the Core): cwd missing or not in a project -> exit 0 at once (so ~/.ssh is
#   open when Claude works outside a project). No network, no git.
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
. "$SELF/scripts/shell-patch.sh" 2>/dev/null || exit 0   # shell_patch_host, shell_patch_refused (Codex)
. "$SELF/hooks/messages.sh" 2>/dev/null || exit 0   # msg: every text, in the ui_language setting
. "$SELF/scripts/guard-lib.sh" 2>/dev/null || exit 0   # TAB, guard_refuse, guard_lex, guard_patch, ...: both guards share them

tool="$(json_str "$in" tool_name)"
case "$tool" in Read|Edit|Write|NotebookEdit|Grep|Glob|apply_patch|Bash) ;; *) exit 0 ;; esac
cwd="$(json_str "$in" cwd)"
[ -n "$cwd" ] || exit 0
load_settings
project_of "$cwd" >/dev/null || exit 0

die() {
  guard_refuse "$(msg secrets_blocked "$1")" "$(msg secrets_ask)"
}

# is_secret_name <name> — exit 0 for .env, .env.<x> (x not example, sample, template) and a name that
# is .env followed by a glob character. No process is started.
is_secret_name() {
  # shellcheck disable=SC1083  # the { in [*?[{] is a glob character to match (brace expansion in a name), not syntax
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
  # shellcheck disable=SC2088  # a literal ~ as typed in the tool input is matched here; resolve_abs expands it later
  if [ -n "$unk" ]; then case "$p" in /*|"~"|"~/"*) ;; *) return 1 ;; esac; fi
  # the literal part before the first glob character (the whole path when there is none)
  pre="$p"
  # shellcheck disable=SC1083  # the { in [*?[{] is a glob character to match, not syntax
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
# Readers take all their input and early readers' writers drop their stderr (pipe noise: scripts/shell-patch.sh).
raw_hit() {
  local t hit
  t="$(cat)"
  hit="$({ printf '%s' "$t"; } 2>/dev/null | guard_components \
    | LC_ALL=C grep -iE '^\.env([*?]|\.|$)' | LC_ALL=C grep -viE '^\.env\.(example|sample|template)$' | LC_ALL=C sed -n 1p)"
  if [ -n "$hit" ]; then printf '%s' "$hit"; return 0; fi
  if printf '%s' "$t" 2>/dev/null | LC_ALL=C grep -qiE '/\.ssh([/"\\]|$)'; then printf '.ssh'; return 0; fi
  return 1
}

# judge_patch <kind> <path> — one path of the patch (guard_patch): the file written (W) and the source of a move (S).
# shellcheck disable=SC2329  # called by name through guard_patch
judge_patch() {
  case "$1" in W|S) if is_secret "$2"; then die "$2"; fi ;; esac
}

# --- apply_patch (Codex): the paths written or moved are judged like a file tool's; a delete passes.
if [ "$tool" = apply_patch ]; then
  patch="$(json_str "$in" command)"
  if [ -z "$patch" ]; then
    # no string to read (missing, empty, not a string): only the "***" header lines of the raw text count
    hit="$({ printf '%s' "$in"; } 2>/dev/null | sed 's/\\n/\
/g' | LC_ALL=C grep -F '***' | raw_hit)" && die "$hit"
    exit 0
  fi
  # the reader is missing or failed: nothing can be judged (a name may hide a TAB), refuse; ran with no output: pass
  guard_patch "$patch" judge_patch
  case "$?" in 1) guard_refuse "$(msg patch_no_reader)" ;; 2) guard_refuse "$(msg patch_too_many 100)" ;; esac
  if [ -n "$PATCH_X" ]; then
    hit="$(printf '%s\n' "$patch" | LC_ALL=C grep -F '***' | raw_hit)" && die "$hit"
  fi
  exit 0
fi

# --- Bash: the candidates found by one awk pass, judged here.
if [ "$tool" = Bash ]; then
  cmd="$(json_str "$in" command)"
  if [ -z "$cmd" ]; then
    hit="$({ printf '%s' "$in"; } 2>/dev/null | raw_hit)" && die "$hit"
    exit 0
  fi
  # A Codex patch handed to the shell is refused, in Codex only (see the header).
  if guard_shell_patch "$in" "$cmd"; then guard_refuse "$(msg patch_shell "$SHELL_PATCH_HIT")"; fi
  # Cheap exit: a secret path has a dot in it (.env, .ssh; quotes or a backslash in the name are
  # removed by the lexer, so the raw text is not searched for ".env"). Everything else is lexed.
  case "$cmd" in *.*) ;; *) exit 0 ;; esac
  [ -r "$SELF/scripts/bash-lex.awk" ] && [ -r "$SELF/scripts/bashlex-guard-secrets.awk" ] || exit 0
  targets="$(guard_lex bashlex-guard-secrets.awk "$cmd")"
  # awk itself failed: the command is unknown, so a secret-looking string in it is refused
  if [ "$?" -ne 0 ]; then hit="$({ printf '%s' "$cmd"; } 2>/dev/null | raw_hit)" && die "$hit"; exit 0; fi
  [ -n "$targets" ] || exit 0
  stopped=""
  while IFS="$TAB" read -r kind a unk judged; do
    if [ "$kind" = X ]; then stopped=1; continue; fi
    [ "$kind" = P ] || continue
    u=""; [ "$unk" = 1 ] && u=1
    # $judged is the word with a glob component that can match .ssh or .env made literal
    if is_secret "${judged:-$a}" "$u"; then die "$a"; fi
  done <<< "$targets"
  # the lexer stopped early: what is left of the command is unknown
  if [ -n "$stopped" ]; then hit="$({ printf '%s' "$cmd"; } 2>/dev/null | raw_hit)" && die "$hit"; fi
  exit 0
fi

# --- File tools, Grep, Glob: the path keys of the tool input.
req=""; opt=""
case "$tool" in
  Read|Edit|Write) req="file_path" ;;
  NotebookEdit) req="notebook_path" ;;
  Grep) opt="path glob" ;;
  Glob) req="pattern"; opt="path" ;;
esac
hint=""
printf '%s' "$in" 2>/dev/null | LC_ALL=C grep -qiE '\.env|\.ssh' && hint=1
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
    if [ -z "$odd" ] && printf '%s' "$in" 2>/dev/null | LC_ALL=C grep -qE "\"$key\"[[:space:]]*:" \
       && ! printf '%s' "$in" 2>/dev/null | LC_ALL=C grep -qE "\"$key\"[[:space:]]*:[[:space:]]*\"\""; then odd=1; fi
    if [ -n "$odd" ]; then hit="$({ printf '%s' "$in"; } 2>/dev/null | raw_hit)" && die "$hit"; fi
  fi
  # every "<key>": "<value>" in the raw text, in case the key occurs more than once
  vals="$({ printf '%s' "$in"; } 2>/dev/null | LC_ALL=C grep -oE "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"")"
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
