# lib-codex-profile.sh — `bash lib.sh codex-profile` (lib.sh sources this file for that subcommand only).

# _toml_read_line <path> <what> — prints `"<path>" = "read"` with the path as a TOML basic string (backslash and double
# quote escaped). An empty path, or one with a control character (a one-line string cannot hold it), gives a comment
# line that names what is left out instead.
_toml_read_line() {
  local s="$1" bs='\' q='"'
  case "$s" in ""|*[[:cntrl:]]*) printf '# (left out: no usable path for %s; sandboxed commands cannot read it)\n' "$2"; return 0 ;; esac
  s="${s//"$bs"/$bs$bs}"; s="${s//"$q"/$bs$q}"
  printf '"%s" = "read"\n' "$s"
}

# codex_profile — prints a TOML fragment for ~/.codex/config.toml (never written by corecrew): a workspace-write permission
# profile that keeps secret files unreadable. Patterns as in coreopinion's ask-gpt.sh review profile. Checked with
# `codex sandbox`, codex 0.166 (tests/test_codex_profile.sh).
# It opens these places of this machine for reading, or corecrew's own commands fail in the sandbox: the folder Codex
# keeps this marketplace's plugins in (codex_home and marketplace_name; scripts, skills, role files; coremodel and
# coreopinion lie there too), the tools copy (<Codex home>/plugins/data/corecrew-<marketplace>/tools; save, undo-step;
# not the rest of the data folder), the settings file (settings_file_path), the hooks marker (hooks_marker_path for
# Codex; a version string), the two global git config files (~/.gitconfig, $XDG_CONFIG_HOME/git/config; git fails
# when one exists and cannot be read) and git's default global ignore file ($XDG_CONFIG_HOME/git/ignore; patterns only,
# else git warns and counts ignored files as changes; a core.excludesFile elsewhere is not opened). Each is the file alone, not its folder: a CORECREW_CONFIG in a wide folder opens
# nothing else, and ~/.config/git may hold a credentials file. Codex accepts a line for a missing file and resolves
# links itself. The Core is not listed: it is added per session (--add-dir). <Projects> is not listed either (it holds
# other projects' secrets): code_dir_of falls back to the cwd when it cannot list it.
codex_profile() {
  local g ch="" td="" sf="" mk="" gc="" xi="" xg="${XDG_CONFIG_HOME:-}"
  ch="$(codex_home)" && td="$ch/plugins/data/corecrew-$(marketplace_name)/tools" && ch="$ch/plugins/cache/$(marketplace_name)" || ch=""
  sf="$(settings_file_path)" || sf=""
  mk="$(COREKIT_HOST=codex hooks_marker_path)" || mk=""
  case "${HOME:-}" in /*) gc="$HOME/.gitconfig"; case "$xg" in /*) ;; *) xg="$HOME/.config" ;; esac ;; esac
  case "$xg" in /*) xi="$xg/git/ignore"; xg="$xg/git/config" ;; *) xg="" ;; esac
  printf '%s\n' '# corecrew: a Codex permission profile for coding.' \
    '# Put the line default_permissions = "corecrew" at the very top of config.toml (before any line that starts with [)' \
    '# and the rest at the end of the file. It then applies to every Codex session, in every project.' \
    '# Keep the tables and the key together: tables without the key make every plain Codex run fail. To try it first,' \
    '# put the whole fragment into a separate CODEX_HOME folder (CODEX_HOME=<folder> codex).' \
    '# What it does: reads and writes the project folder and temp folders, reads minimal system paths, and blocks the' \
    '# secret files named below inside the project. It also reads three places of corecrew and three files of git, written' \
    '# below as paths of this machine: the folder Codex keeps the plugins of this marketplace in, the corecrew tools copy,' \
    '# the corecrew settings file and its hooks marker, the global git config files (git stops when it cannot read' \
    '# one) and the global git ignore file (a core.excludesFile elsewhere is not read: git warns). Print the fragment' \
    '# again when the Codex home folder or the settings file moves. ~/.ssh and the rest of the home folder (the rest of' \
    '# the Codex home folder too) are not listed, so they stay closed.' \
    '# Codex keeps .git read-only, so commits ask for approval.' \
    '# What it is NOT: a default, not a hard boundary.' \
    '#  - It is switched off by --sandbox, --dangerously-bypass-approvals-and-sandbox or -c sandbox_mode=... on the command' \
    '#    line, by sandbox_mode in any config layer (a profile, the system config), and by the' \
    '#    .codex/config.toml of a trusted project (a cloned repository can bring one).' \
    '#  - It protects files in the working tree, not git history (git show HEAD:.env, git log -p), and not a hard link' \
    '#    made outside the sandbox.' \
    '#  - /tmp and /var/tmp stay readable and writable (the git helper needs them). Environment variables are not filtered.' \
    '# Names are matched by pattern. Still over-blocked: source files named credentials*, secrets* or secret.*' \
    '# (credentials_form.ts, secrets_helper.py). Still open: .envrc (project config), other names not listed.' \
    'default_permissions = "corecrew"' '' '[permissions.corecrew.filesystem]' \
    '":minimal" = "read"' '":tmpdir" = "write"'
  _toml_read_line "$ch" "the plugin folder in the Codex home folder"
  _toml_read_line "$td" "the corecrew tools copy"
  _toml_read_line "$sf" "the corecrew settings file"
  _toml_read_line "$mk" "the hooks marker"
  _toml_read_line "$gc" "the global git config"
  _toml_read_line "$xg" "the global git config (XDG)"
  _toml_read_line "$xi" "the global git ignore file"
  printf '%s\n' '' '[permissions.corecrew.filesystem.":workspace_roots"]' '"." = "write"'
  for g in '.env' '.env.*' '*.env' '*.env.*' '*.pem' '*.key' '*.p12' '*.pfx' 'id_rsa*' 'id_ed25519*' 'id_ecdsa*' 'id_dsa*' \
    '*[cC]redentials*' '*CREDENTIALS*' '.npmrc' '.netrc' '.pypirc' '.git-credentials' '.htpasswd' '.pgpass' '*.tfvars' '*.tfstate*' \
    '*.jks' '*.keystore' '*.p8' '*.ppk' '*.keytab' '.s3cfg' '.gnupg/**' '[sS]ecrets*' 'SECRETS*' '[sS]ecret.*' '*.secret' '*.secrets' \
    '[tT]oken' '[tT]oken.txt' '[tT]oken.json' '*.token' '*_[tT]oken.json' '*-[tT]oken.json' \
    '*_[tT]oken' '*-[tT]oken' '*_[tT]oken.*' '.*[tT]oken' '.secrets*' '*client_secret*.json' '.dockercfg' '*-secret.*' '*_secret.*' \
    '*[kK]ube[cC]onfig*' '*KUBECONFIG*' '*.kdbx' '.aws/**' '.kube/**' '.ssh/**' '.docker/config.json' \
    '*[sS]ervice?[aA]ccount*.json' '*[sS]ervice[aA]ccount*.json' '*SERVICE?ACCOUNT*.json'; do
    printf '"**/%s" = "deny"\n' "$g"
  done
}
