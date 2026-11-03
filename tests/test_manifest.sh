#!/usr/bin/env bash
# Plugin and marketplace manifests: name, version, settings, dependency, rename; docs follow.
source "$(dirname "$0")/lib.sh"
P="$ROOT/.claude-plugin/plugin.json"
M="$ROOT/.claude-plugin/marketplace.json"

# plugin.json
assert_contains "$P" '"name": "coredev"'
assert_contains "$P" '"version": "0.2.0"'
assert_contains "$P" '"userConfig"'
for key in core_dir attribution model_profile; do assert_contains "$P" "\"$key\""; done
assert_contains "$P" '"type": "directory"'
assert_contains "$P" '"default": "~/Projects/Core"'
assert_contains "$P" '"options": ["allow", "forbid"]'
assert_contains "$P" '"default": "allow"'
assert_contains "$P" '"options": ["economy", "balanced", "strong"]'
assert_contains "$P" '"default": "balanced"'
assert_contains "$P" '"dependencies"'
assert_contains "$P" '"name": "feature-dev"'
assert_contains "$P" '"marketplace": "claude-plugins-official"'

# marketplace.json
assert_contains "$M" '"name": "corekit"'
assert_contains "$M" '"name": "coredev"'
assert_contains "$M" '"renames"'
assert_contains "$M" '"corekit": "coredev"'
assert_contains "$M" '"allowCrossMarketplaceDependenciesOn": ["claude-plugins-official"]'

# README and CHANGELOG
assert_contains "$ROOT/README.md" '/plugin install coredev@corekit'
assert_not_contains "$ROOT/README.md" '/corekit:'
assert_not_contains "$ROOT/README.md" 'corekit@corekit'
assert_eq "$(grep -m1 '^## ' "$ROOT/CHANGELOG.md" | cut -c1-9)" '## 0.2.0 ' "CHANGELOG first entry"
assert_contains "$ROOT/CHANGELOG.md" '## 0.2.0 — '

finish
