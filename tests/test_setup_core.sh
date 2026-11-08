#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
SC="$SCRIPTS/setup-core.sh"
ITEMS="./.git .gitignore README.md PROJECTS.md standards/README.md knowledge/README.md .coredev"

# --- fresh run: seven items, one commit
new_sandbox
assert_exit 0 bash "$SC" "$CORE_DIR"
for i in $ITEMS; do
  echo "$OUT" | grep -qxF "created $i" && pass || fail "no 'created $i' in: $OUT"
done
assert_eq "$(echo "$OUT" | grep -c '^created')" "7" "created lines"
for f in .gitignore README.md PROJECTS.md standards/README.md knowledge/README.md .coredev; do
  assert_file "$CORE_DIR/$f"
done
assert_dir "$CORE_DIR/.git"
assert_eq "$(head -1 "$CORE_DIR/.coredev")" "schema: 2" ".coredev first line"
assert_eq "$(git -C "$CORE_DIR" rev-list --count HEAD)" "1" "commit count"
assert_eq "$(git -C "$CORE_DIR" log -1 --format=%s)" "Set up Core" "commit subject"
assert_eq "$(git -C "$CORE_DIR" status --porcelain)" "" "worktree dirty after setup"
assert_eq "$(git -C "$CORE_DIR" symbolic-ref HEAD)" "refs/heads/main" "branch"
assert_not_contains "$CORE_DIR/.gitignore" "*/code/"
# M2: the staging folders of a killed wiki-migrate or adopt are never committed by save
assert_contains "$CORE_DIR/.gitignore" ".wiki-migrate.*/"
assert_contains "$CORE_DIR/.gitignore" ".adopt.*/"
mkdir -p "$CORE_DIR/p/.wiki-migrate.Ab12/docs" "$CORE_DIR/.adopt.Cd34"; touch "$CORE_DIR/p/.wiki-migrate.Ab12/docs/x.md" "$CORE_DIR/.adopt.Cd34/y" "$CORE_DIR/p/keep.md"
assert_eq "$(git -C "$CORE_DIR" status --porcelain --untracked-files=all)" "?? p/keep.md" "staging folders are ignored, other files are not"
rm -rf "$CORE_DIR/p" "$CORE_DIR/.adopt.Cd34"
assert_contains "$CORE_DIR/standards/README.md" "/corecrew:new-standard"
assert_contains "$CORE_DIR/knowledge/README.md" "symptom"
assert_contains "$CORE_DIR/knowledge/README.md" "/corecrew:task"
assert_contains "$CORE_DIR/knowledge/README.md" "→"
assert_not_contains "$CORE_DIR/README.md" "bin/"
assert_contains "$CORE_DIR/README.md" "AGENTS.md"
assert_contains "$CORE_DIR/README.md" "session-rules.md"
assert_contains "$CORE_DIR/README.md" "docs/INDEX.md"
assert_not_contains "$CORE_DIR/README.md" "<project-name>"
for f in standards/README.md knowledge/README.md; do
  [ "$(wc -l < "$CORE_DIR/$f")" -le 15 ] && pass || fail "$f longer than 15 lines"
done
assert_no_file "$CORE_DIR/bin"; assert_no_file "$CORE_DIR/hooks"
core_ready_in() { CORE_DIR="$1" bash -c '. "$1"; core_ready' _ "$SCRIPTS/lib.sh"; }
core_ready_in "$CORE_DIR" && pass || fail "core_ready false after setup"

# --- second run: only skipped, no new commit
before=$(tree_sum "$CORE_DIR")
assert_exit 0 bash "$SC" "$CORE_DIR"
echo "$OUT" | grep -q '^created' && fail "second run created: $OUT" || pass
assert_eq "$(echo "$OUT" | grep -c '^skipped')" "7" "skipped lines"
assert_eq "$(git -C "$CORE_DIR" rev-list --count HEAD)" "1" "second run added a commit"
assert_eq "$before" "$(tree_sum "$CORE_DIR")" "tree changed on re-run"

# --- dry run creates nothing
new_sandbox
assert_exit 0 bash "$SC" "$CORE_DIR" --dry-run
assert_no_file "$CORE_DIR"
assert_eq "$(echo "$OUT" | grep -c '^would create')" "7" "would-create lines"
# dry run on an existing partial Core changes nothing either
mkdir -p "$CORE_DIR"; echo keep > "$CORE_DIR/PROJECTS.md"; before=$(tree_sum "$CORE_DIR")
assert_exit 0 bash "$SC" --dry-run "$CORE_DIR"
assert_eq "$before" "$(tree_sum "$CORE_DIR")" "dry run changed files"
assert_no_file "$CORE_DIR/.git"

# --- a user's README.md is kept byte for byte; the rest is added
new_sandbox
mkdir -p "$CORE_DIR"; printf 'My own notes\n\nno newline at end' > "$CORE_DIR/README.md"
want=$(cksum < "$CORE_DIR/README.md")
assert_exit 0 bash "$SC" "$CORE_DIR"
assert_eq "$(cksum < "$CORE_DIR/README.md")" "$want" "README.md modified"
echo "$OUT" | grep -qxF "skipped README.md" && pass || fail "README.md not skipped"
echo "$OUT" | grep -qxF "created .coredev" && pass || fail ".coredev not created"
# the user's README is not part of our commit (it was never added by us)
git -C "$CORE_DIR" show --name-only --format= HEAD | grep -qx 'README.md' && fail "commit includes user README" || pass

# --- a 0.1.x Core: bin/ and hooks/ stay as they are; .coredev is added
new_sandbox
mkdir -p "$CORE_DIR/bin" "$CORE_DIR/hooks" "$CORE_DIR/app/docs"
echo old-save > "$CORE_DIR/bin/save"; echo old-hook > "$CORE_DIR/hooks/pre-commit-code"
echo "- app" > "$CORE_DIR/PROJECTS.md"; echo x > "$CORE_DIR/app/docs/a.md"
git init -q "$CORE_DIR"
before=$(tree_sum "$CORE_DIR/bin"; tree_sum "$CORE_DIR/hooks"; tree_sum "$CORE_DIR/app")
assert_exit 0 bash "$SC" "$CORE_DIR"
assert_eq "$(tree_sum "$CORE_DIR/bin"; tree_sum "$CORE_DIR/hooks"; tree_sum "$CORE_DIR/app")" "$before" "0.1.x files changed"
assert_eq "$(cat "$CORE_DIR/PROJECTS.md")" "- app" "PROJECTS.md changed"
assert_file "$CORE_DIR/.coredev"; assert_eq "$(head -1 "$CORE_DIR/.coredev")" "schema: 2"
echo "$OUT" | grep -qxF "skipped ./.git" && pass || fail ".git not skipped"
git -C "$CORE_DIR" show --name-only --format= HEAD | grep -q '^bin/' && fail "commit swept in bin/" || pass

# --- .coredev with only a prefix: not ready; setup updates it and keeps the line
new_sandbox
mkdir -p "$CORE_DIR"; printf 'app-id-prefix: com.x\n' > "$CORE_DIR/.coredev"
core_ready_in "$CORE_DIR" && fail "core_ready true without schema" || pass
assert_exit 0 bash "$SC" "$CORE_DIR"
echo "$OUT" | grep -qxF "updated .coredev" && pass || fail "no 'updated .coredev' in: $OUT"
assert_eq "$(head -1 "$CORE_DIR/.coredev")" "schema: 2" "schema first"
assert_eq "$(sed -n 2p "$CORE_DIR/.coredev")" "app-id-prefix: com.x" "prefix kept"
assert_eq "$(wc -l < "$CORE_DIR/.coredev" | tr -d ' ')" "2" ".coredev lines"
assert_eq "$(CORE_DIR="$CORE_DIR" bash "$SCRIPTS/lib.sh" get app-id-prefix)" "com.x" "prefix via lib"
core_ready_in "$CORE_DIR" && pass || fail "core_ready false after update"
# dry run says "would update"
new_sandbox
mkdir -p "$CORE_DIR"; printf 'app-id-prefix: com.x\n' > "$CORE_DIR/.coredev"
assert_exit 0 bash "$SC" "$CORE_DIR" --dry-run
echo "$OUT" | grep -qxF "would update .coredev" && pass || fail "no 'would update .coredev'"
assert_eq "$(cat "$CORE_DIR/.coredev")" "app-id-prefix: com.x" "dry run changed .coredev"

# --- later schema numbers count as ready and are kept
new_sandbox
mkdir -p "$CORE_DIR"; printf 'schema: 3\n' > "$CORE_DIR/.coredev"
assert_exit 0 bash "$SC" "$CORE_DIR"
echo "$OUT" | grep -qxF "skipped .coredev" && pass || fail ".coredev schema 3 not skipped"
assert_eq "$(cat "$CORE_DIR/.coredev")" "schema: 3" "schema 3 rewritten"

# --- schema 1 Core: only the schema line changes; .gitignore stays byte-identical
new_sandbox
assert_exit 0 bash "$SC" "$CORE_DIR"
printf 'schema: 1\napp-id-prefix: com.x\n' > "$CORE_DIR/.coredev"
printf 'my-own-line\n' >> "$CORE_DIR/.gitignore"
gi_before="$(cat "$CORE_DIR/.gitignore")"
assert_exit 0 bash "$SC" "$CORE_DIR"
echo "$OUT" | grep -qxF "updated .coredev" && pass || fail "schema 1 not updated: $OUT"
assert_eq "$(head -1 "$CORE_DIR/.coredev")" "schema: 2" "schema 1 -> 2"
assert_eq "$(sed -n 2p "$CORE_DIR/.coredev")" "app-id-prefix: com.x" "prefix kept on upgrade"
assert_eq "$(cat "$CORE_DIR/.gitignore")" "$gi_before" ".gitignore changed on upgrade"
assert_exit 0 bash "$SC" "$CORE_DIR"
echo "$OUT" | grep -qxF "skipped .coredev" && pass || fail "second run not skipped: $OUT"
# dry run on a schema 1 Core changes nothing
printf 'schema: 1\n' > "$CORE_DIR/.coredev"
assert_exit 0 bash "$SC" "$CORE_DIR" --dry-run
echo "$OUT" | grep -qxF "would update .coredev" && pass || fail "dry run: $OUT"
assert_eq "$(cat "$CORE_DIR/.coredev")" "schema: 1" "dry run changed .coredev"

# --- core_dir with a space and Cyrillic; ~ expands; CORE_DIR env is not needed
new_sandbox
D="$SANDBOX/Мои проекты/Ядро"
assert_exit 0 env -u CORE_DIR bash "$SC" "$D"
assert_file "$D/.coredev"; assert_dir "$D/.git"
assert_eq "$(git -C "$D" rev-list --count HEAD)" "1"
echo "$OUT" | grep -qxF "created ./.git" && pass || fail "relative .git line: $OUT"
assert_exit 0 env -u CORE_DIR HOME="$SANDBOX/h" bash "$SC" '~/Core'
assert_file "$SANDBOX/h/Core/.coredev"

# --- never creates a GitHub repo
new_sandbox; mkdir -p "$SANDBOX/stub"
printf '#!/bin/sh\necho gh-called >> "%s/gh.log"\n' "$SANDBOX" > "$SANDBOX/stub/gh"; chmod +x "$SANDBOX/stub/gh"
PATH="$SANDBOX/stub:$PATH" bash "$SC" "$CORE_DIR" >/dev/null
assert_no_file "$SANDBOX/gh.log"

# --- no git identity: plain message, exit 1, nothing created; with an identity it works
new_sandbox
noid() { env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL \
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null HOME="$SANDBOX/nohome" \
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.useConfigOnly GIT_CONFIG_VALUE_0=true "$@"; }
assert_exit 1 noid bash "$SC" "$CORE_DIR"
echo "$OUT" | grep -q 'user.name' && echo "$OUT" | grep -q 'user.email' && pass || fail "no hint about git identity: $OUT"
assert_no_file "$CORE_DIR"
assert_exit 0 bash "$SC" "$CORE_DIR"
assert_eq "$(git -C "$CORE_DIR" rev-list --count HEAD)" "1" "commit after identity was set"
# nothing to create: no identity needed
assert_exit 0 noid bash "$SC" "$CORE_DIR"

# --- the commit fails (a failing pre-commit hook): files exist, exit 1; the next run commits them
new_sandbox
git init -q "$CORE_DIR"; mkdir -p "$CORE_DIR/.git/hooks"
printf '#!/bin/sh\nexit 1\n' > "$CORE_DIR/.git/hooks/pre-commit"; chmod +x "$CORE_DIR/.git/hooks/pre-commit"
assert_exit 1 bash "$SC" "$CORE_DIR"
assert_file "$CORE_DIR/.coredev"
assert_eq "$(git -C "$CORE_DIR" rev-list --count HEAD 2>/dev/null || echo 0)" "0" "commit should have failed"
rm "$CORE_DIR/.git/hooks/pre-commit"
assert_exit 0 bash "$SC" "$CORE_DIR"
echo "$OUT" | grep -q '^created' && fail "re-run created again: $OUT" || pass
assert_eq "$(git -C "$CORE_DIR" rev-list --count HEAD)" "1" "re-run did not commit the setup files"
assert_eq "$(git -C "$CORE_DIR" status --porcelain)" "" "setup files still uncommitted"
# the retry never sweeps in a user's own README.md or PROJECTS.md
new_sandbox
git init -q "$CORE_DIR"; mkdir -p "$CORE_DIR/.git/hooks"
printf 'mine\n' > "$CORE_DIR/README.md"; printf -- '- app\n' > "$CORE_DIR/PROJECTS.md"
printf '#!/bin/sh\nexit 1\n' > "$CORE_DIR/.git/hooks/pre-commit"; chmod +x "$CORE_DIR/.git/hooks/pre-commit"
assert_exit 1 bash "$SC" "$CORE_DIR"
rm "$CORE_DIR/.git/hooks/pre-commit"
assert_exit 0 bash "$SC" "$CORE_DIR"
files=$(git -C "$CORE_DIR" show --name-only --format= HEAD)
echo "$files" | grep -qx '.coredev' && pass || fail "retry did not commit .coredev: $files"
echo "$files" | grep -qxE 'README.md|PROJECTS.md' && fail "retry swept in user files: $files" || pass

# --- usage errors
assert_exit 2 bash "$SC" --bogus
finish
