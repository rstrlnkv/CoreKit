# lib-role-model.sh — `bash lib.sh role-model` (lib.sh sources this file for that subcommand only).

# role_model <claude|codex> <economy|balanced|strong> <role> — the model for a crew role: claude prints the model alone
# (empty line for architect and explorer, which are feature-dev agents in Claude), codex prints "<model> <reasoning effort>".
# Same table as the task SKILL.md. Exit 2 with a usage line on bad arguments.
role_model() {
  local usage="Usage: lib.sh role-model <claude|codex> <economy|balanced|strong> <role>" e c out k v
  [ $# -eq 3 ] || { echo "$usage" >&2; return 2; }
  case "$1:$2" in
    claude:economy) e=haiku; c=sonnet ;; claude:balanced) e=sonnet; c=sonnet ;; claude:strong) e=sonnet; c=opus ;;
    codex:economy) e="gpt-6-luna medium"; c="gpt-6.1-sol low" ;;
    codex:balanced) e="gpt-6.1-sol medium"; c="gpt-6.1-sol medium" ;;
    codex:strong) e="gpt-6.1-sol high"; c="gpt-6-astra high" ;;
    *) echo "$usage" >&2; return 2 ;;
  esac
  case "$3" in
    engineer|tester) out="$e" ;;
    security|verifier|localizer|designer) out="$c" ;;
    architect|explorer) if [ "$1" = claude ]; then out=""; else out="$c"; fi ;;
    *) echo "$usage" >&2; return 2 ;;
  esac
  # Codex: the user's own models win over the table (the table can name a model their plan lacks). Settings file
  # keys codex_model_<role>, then codex_model: "<model>", "<model> <effort>" or "inherit" (an empty line: spawn
  # without model and effort, so Codex's own default applies). An invalid value is named and skipped.
  if [ "$1" = codex ]; then
    _sf_load
    for k in "codex_model_$3" codex_model; do
      v="$(_sf_get "$k" | tr -s '[:space:]' ' ')"; v="${v% }"
      [ -n "$v" ] || continue
      if [ "$v" = inherit ]; then out=""; break; fi
      if printf '%s\n' "$v" | grep -qE '^[A-Za-z0-9][A-Za-z0-9._:/-]*( [a-z]+)?$'; then out="$v"; break; fi
      printf 'corecrew: %s "%s" in %s is not valid: use <model>, <model> <effort> or inherit. Skipped.\n' \
        "$k" "$v" "$(settings_file_path)" >&2
    done
  fi
  printf '%s\n' "$out"
}
