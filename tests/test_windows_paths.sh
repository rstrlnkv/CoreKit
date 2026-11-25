#!/usr/bin/env bash
# Exercise Git for Windows drive paths at the CLI, Git worktree and hook boundaries.
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/lib-hook.sh"
new_sandbox
base="$SANDBOX/Windows Projects"
mkdir -p "$base/Core/demo" "$base/Demo" "$base/Linked" "$base/Demo/.git/worktrees/linked"
: > "$base/Core/demo/CLAUDE.md"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) native="$(cygpath -w "$base")" ;;
  *) # Model the cygpath conversion only; use real directories and the shipped scripts.
    [ "${RUNNER_OS:-}" != Windows ] || { fail "Windows CI needs real Git Bash and cygpath"; finish; }
    native='C:\Windows Projects'
    export WIN_ROOT="$SANDBOX" OSTYPE=cygwin MSYSTEM=MINGW64
    mkdir "$SANDBOX/path-tools"
    cat > "$SANDBOX/path-tools/cygpath" <<'STUB'
#!/usr/bin/env bash
[ "$1" = -u ] || exit 2
p="${2//\\//}"
case "$p" in [Cc]:/*) printf '%s/%s\n' "$WIN_ROOT" "${p#?:/}" ;; *) exit 1 ;; esac
STUB
    chmod +x "$SANDBOX/path-tools/cygpath"
    export PATH="$SANDBOX/path-tools:$PATH" ;;
esac
export CORE_DIR="$native\Core" CORECREW_CONFIG="$native\settings"
lib="$SCRIPTS/lib.sh"
printf 'model_profile: strong\r\n' > "$base/settings"
assert_eq "$(bash "$lib" core-dir 2>/dev/null)" "$(cd "$base/Core" && pwd -P)" "native Core"
assert_eq "$(bash "$lib" settings model_profile 2>/dev/null)" 'model_profile: strong' "native config path"
assert_eq "$(bash "$lib" project-of "${native//\\//}/Demo")" demo "native cwd"
printf 'gitdir: %s\\Demo\\.git\\worktrees\\linked\r\n' "$native" > "$base/Linked/.git"
printf '%s\\Linked\\.git\r\n' "$native" > "$base/Demo/.git/worktrees/linked/gitdir"
assert_eq "$(bash "$lib" project-of "$native\Linked")" demo "native worktree metadata"
assert_eq "$(CODEX_HOME="$native\Codex" bash -c '. "$1"; codex_home' _ "$lib")" "$base/Codex" "native Codex home"
for file in 'docs\plan.md' 'src\main.c'; do
  result="$(bash -c '. "$1"; cwd="$2"; resolve_abs "$3"; printf %s "$ABS"' _ "$lib" "$native\Demo" "$file")"
  assert_eq "$result" "$(cd "$base" && pwd -P)/Demo/${file//\\//}" "relative Windows path $file"
  rc=0
  printf '{"tool_name":"Write","cwd":"%s","file_path":"%s"}' \
    "$(json_esc "$native\Demo")" "$(json_esc "$native\Demo\\$file")" |
    bash "$HOOKS/guard-code.sh" >/dev/null 2>&1 || rc=$?
  case "$file" in docs*) want=2 ;; *) want=0 ;; esac
  assert_eq "$rc" "$want" "native file guard: $file"
done
# Source an entry with the exact $0 native launchers supply, even on POSIX test hosts.
mkdir -p "$base/Plugin Root"
cp -R "$PLUGIN/." "$base/Plugin Root/"
hook_event codex SessionStart "$native\Demo" source=startup |
  COREKIT_HOST=codex CLAUDE_PLUGIN_DATA="$SANDBOX/data" bash -c '. "$1"' \
    "$native\Plugin Root\hooks\session-start.sh" "$base/Plugin Root/hooks/session-start.sh" > "$SANDBOX/start"
assert_contains "$SANDBOX/start" "demo"
finish
