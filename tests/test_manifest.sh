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

# hooks.json: plugin Stop hook; no install.sh any more
assert_file "$ROOT/hooks/hooks.json"
assert_contains "$ROOT/hooks/hooks.json" '"Stop"'
assert_contains "$ROOT/hooks/hooks.json" '"timeout"'
assert_no_file "$ROOT/install.sh"; assert_no_file "$ROOT/tests/test_install.sh"
assert_not_contains "$ROOT/README.md" 'install.sh'
assert_contains "$ROOT/README.md" '2.1.271'
T="$ROOT/skills/new-project/templates"
assert_not_contains "$T/code/settings.local.json.tmpl" '"hooks"'
assert_contains "$T/code/settings.local.json.tmpl" '"additionalDirectories"'
assert_not_contains "$T/CLAUDE.md.tmpl" '/bin/'
assert_contains "$T/CLAUDE.md.tmpl" 'undo-step'
assert_contains "$T/CLAUDE.md.tmpl" 'printed at session start'

# migration note: the seven steps of spec section 6
MG="$ROOT/docs/migration-0.2.md"
assert_file "$MG"
assert_contains "$MG" '/plugin install coredev@corekit'
assert_contains "$MG" 'claude.ai-synced install: see below'
assert_contains "$MG" 'install-hooks.sh'
assert_contains "$MG" 'session-rules.md'
for n in 1 2 3 4 5 6 7; do assert_contains "$MG" "### Step $n"; done

finish
