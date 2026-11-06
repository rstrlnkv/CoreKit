#!/usr/bin/env bash
# The ship skill: release a branch, then merge it into main and push, only after the user's go-ahead.
source "$(dirname "$0")/lib.sh"
SK="$PLUGIN/skills/ship/SKILL.md"
assert_file "$SK"

# Pushes to a remote: only the user starts it.
assert_contains "$SK" 'name: ship'
assert_contains "$SK" 'disable-model-invocation: true'

# The release itself follows task's postconditions; no second copy of them.
assert_contains "$SK" '<plugin>/skills/task/references/release.md'
assert_contains "$SK" 'still reads literally `${user_config.`'

# The global git config is the same before and after the tests.
assert_contains "$SK" 'git config --global --list'

# Version: patch unless the user named another part or a version.
assert_contains "$SK" 'patch'

# Stops for the user's go-ahead before merging; merge is fast-forward only, push is never forced.
assert_contains "$SK" 'Wait for the user'
assert_contains "$SK" '--ff-only'
assert_contains "$SK" 'git fetch . '
assert_not_contains "$SK" '--force'
assert_not_contains "$SK" 'push -f'

# The report names the merge commit, the new version and what is left open.
assert_contains "$SK" 'Merged:'
assert_contains "$SK" 'Version:'
assert_contains "$SK" 'Open:'

# The README lists the command.
assert_contains "$ROOT/README.md" '/corecrew:ship'
finish
