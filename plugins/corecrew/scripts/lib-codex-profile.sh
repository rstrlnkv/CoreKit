# lib-codex-profile.sh — `bash lib.sh codex-profile` (lib.sh sources this file for that subcommand only).

# codex_profile — prints a TOML fragment for ~/.codex/config.toml (never written by corecrew): a workspace-write permission
# profile that keeps secret files unreadable. Patterns as in coreopinion's ask-gpt.sh review profile. Checked with
# `codex sandbox`, codex 0.166 (tests/test_codex_profile.sh).
codex_profile() {
  local g
  printf '%s\n' '# corecrew: a Codex permission profile for coding.' \
    '# Put the line default_permissions = "corecrew" at the very top of config.toml (before any line that starts with [)' \
    '# and the rest at the end of the file. It then applies to every Codex session, in every project.' \
    '# Keep the tables and the key together: tables without the key make every plain Codex run fail. To try it first,' \
    '# put the whole fragment into a separate CODEX_HOME folder (CODEX_HOME=<folder> codex).' \
    '# What it does: reads and writes the project folder and temp folders, reads minimal system paths, and blocks the' \
    '# secret files named below inside the project. ~/.ssh and the rest of the home folder are not listed, so they stay closed.' \
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
    '":minimal" = "read"' '":tmpdir" = "write"' '' '[permissions.corecrew.filesystem.":workspace_roots"]' '"." = "write"'
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
