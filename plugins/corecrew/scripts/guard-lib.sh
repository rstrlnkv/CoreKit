# guard-lib.sh — what hooks/guard-code.sh and hooks/guard-secrets.sh share. Both source it after lib.sh, shell-patch.sh
# and hooks/messages.sh, with `2>/dev/null || exit 0`: a missing file lets every call pass, like a missing lib.sh. It is
# not a lib-*.sh, which lib.sh would source as one of its parts; nothing else needs it. The rules and their messages stay
# in the hooks: this file holds the plumbing they share. Needs $SELF (the plugin root).

TAB="$(printf '\t')"

# guard_refuse <line>... — the refusal: each line on stderr, then exit 2. Nothing is ever printed to stdout.
guard_refuse() {
  printf '%s\n' "$@" >&2
  exit 2
}

# guard_shell_patch <hook input> <command> — exit 0 when the command is a Codex patch handed to the shell, which the
# guards refuse (scripts/shell-patch.sh: shell_patch_host, then shell_patch_refused, which sets SHELL_PATCH_HIT).
guard_shell_patch() {
  shell_patch_host "$1" && shell_patch_refused "$2"
}

# guard_lex <reader.awk> <command> — what the shared tokenizer (scripts/bash-lex.awk) and a hook's reader (scripts/<reader.awk>)
# print for the command; the status is awk's. Spaces become \004 when the command has no \004 byte: the tokenizer then reads
# a plain word whole (bash-lex.awk, Speed). tr's stderr is dropped: the reader may stop early (it is missing, it failed, or
# it found too many targets), and with SIGPIPE ignored tr would then print "write error: Broken pipe" to the user.
guard_lex() {
  local sp=' ' lexsp=0 eot
  eot="$(printf '\004')"
  case "$2" in *"$eot"*) ;; *) sp="$eot"; lexsp=1 ;; esac
  { printf '%s' "$2"; } 2>/dev/null | LC_ALL=C tr '\n\r ' "$(printf '\002')$sp$sp" 2>/dev/null \
    | LC_ALL=C awk -v lexsp="$lexsp" -f "$SELF/scripts/bash-lex.awk" -f "$SELF/scripts/$1" 2>/dev/null
}

# guard_components — stdin: raw text; stdout: its components, one per line. The text is cut at / \ " blanks , : ; = ( )
# < > & | { } ` and '. The hooks look for an internal or a secret-looking name among them where no reader can place a path.
guard_components() {
  LC_ALL=C tr '\134\057\042[:space:]\054:;=()<>&|\173\175\140\047' '\n'
}

# patch_paths <text> — the file paths in a Codex apply_patch text, one "<kind>\t<path>" per line: W written, S move
# source, D deleted, X unreadable, C more than 100 paths. See scripts/patch-paths.awk. Status 1 when the reader
# (patch-paths.awk) is missing or awk failed; status 0 when it ran, even if it printed nothing (a patch that names no
# file, e.g. Begin Patch + End Patch).
patch_paths() {
  [ -r "$SELF/scripts/patch-paths.awk" ] || return 1
  printf '%s\n' "$1" | LC_ALL=C awk -f "$SELF/scripts/patch-paths.awk" 2>/dev/null
}

# guard_patch <patch text> <judge function> — reads the paths of a Codex apply_patch text and calls
# <judge function> <kind> <path> for each W, S and D line, in order (the judge exits 2 to refuse). An X line (a text the
# reader cannot place) sets PATCH_X: the hook then checks the raw "***" lines. Status 1: the reader is missing or failed,
# so nothing can be judged, not even raw (a path may be cwd-relative or hide a TAB), and the hook refuses the call.
# Status 2: more than 100 paths (a C line), and the hook refuses the call. Status 0 otherwise; a reader that ran and
# printed nothing (a patch that names no file) has nothing to judge.
# shellcheck disable=SC2034  # PATCH_X is set here for the hooks, which read it after this call
guard_patch() {
  local found kind a
  PATCH_X=""
  found="$(patch_paths "$1")" || return 1
  [ -n "$found" ] || return 0
  while IFS="$TAB" read -r kind a; do
    case "$kind" in
      C) return 2 ;;
      X) PATCH_X=1 ;;
      *) "$2" "$kind" "$a" ;;
    esac
  done <<< "$found"
  return 0
}
