#!/usr/bin/env bash
# allowed-files.sh <path>... — of the files and folders the user named, prints the files the skill may
# send (tracked or untracked, not git-ignored, and not a secret), one per line, relative to the current
# folder. A named path it does not print is a secret, missing or git-ignored.
#
# Why a script and not `git ls-files -- <named> <excludes>`: when every named path lies in one folder
# (a single file is enough), git drops the exclude pathspecs' meaning — `:(exclude)*.env` then lists
# nothing at all, and `:(exclude,glob)**/*.env` lets the secret through (seen with git 2.54, macOS).
# Listed from `.` the excludes work, so the whole allowed list is taken once and the named paths are
# picked from it. Keep the patterns in step with the <EXCLUDE> pathspec in SKILL.md.
[ $# -gt 0 ] || { echo "usage: allowed-files.sh <path>..." >&2; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "allowed-files.sh: not a git repository" >&2; exit 3; }
list="$(git ls-files --cached --others --exclude-standard -- . ':(exclude)*.env' ':(exclude)*.env.*' ':(exclude)*.pem' ':(exclude)*.key' ':(exclude)*.p12' ':(exclude)*.pfx' ':(exclude)*id_rsa*' ':(exclude)*id_ed25519*' ':(exclude,icase)*credentials*' ':(exclude)*.npmrc' ':(exclude)*.netrc' ':(exclude)*.pypirc' ':(exclude)*.git-credentials' ':(exclude)*.tfvars' ':(exclude)*.tfstate' ':(exclude)*.tfstate.*' ':(exclude)*.jks' ':(exclude)*.keystore' ':(exclude)*.p8' ':(exclude,icase)*secret*' ':(exclude,icase)*token*' ':(exclude,icase)*kubeconfig*' ':(exclude)*.kdbx' ':(exclude)*.aws/*' ':(exclude,icase)*service?account*.json' ':(exclude,icase)*serviceaccount*.json')" || exit 1
for p in "$@"; do
  while [ "${p#./}" != "$p" ]; do p="${p#./}"; done
  while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  # a file is matched whole, a folder by its prefix; "." is everything
  printf '%s\n' "$list" | P="$p" LC_ALL=C awk 'BEGIN { p = ENVIRON["P"] } $0 != "" && (p == "." || $0 == p || index($0, p "/") == 1)'
done | LC_ALL=C sort -u
