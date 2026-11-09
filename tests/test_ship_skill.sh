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

# The global git config check was a lesson from CoreKit's own tests; it does not ship to every project.
assert_not_contains "$SK" 'git config --global'

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

# The branch to ship into is resolved, never assumed: no command names `main` itself.
st="$(md_section "$SK" Start)"
case "$st" in *'git symbolic-ref --short refs/remotes/origin/HEAD'*'init.defaultBranch'*'ask the user'*) pass ;; *) fail "Start resolves <main>: origin/HEAD, then init.defaultBranch, else ask" ;; esac
hard="$(grep -nE '(^|[ `"])main\.\.|\.\.\.?main\b|origin main\b|merge main\b|refs/heads/main\b|:main\b|ff-only main\b|On `main`' "$SK")"
assert_eq "$hard" "" "no command or step hard-codes the branch main"
grep -q '^description:.*into main' "$SK" && fail "the description still promises main" || pass
# Tag and GitHub release: after the push, on the user's own yes, never moved or forced.
steps="$(md_section "$SK" Steps)"
np="$(printf '%s\n' "$steps" | grep -n 'git push origin <main>' | head -1 | cut -d: -f1)"
nt="$(printf '%s\n' "$steps" | grep -n 'git tag -a' | head -1 | cut -d: -f1)"
nr="$(printf '%s\n' "$steps" | grep -n 'gh release create' | head -1 | cut -d: -f1)"
[ -n "$np" ] && [ -n "$nt" ] && [ -n "$nr" ] && [ "$np" -lt "$nt" ] && [ "$nt" -lt "$nr" ] && pass || fail "push, then git tag -a, then gh release create (lines $np $nt $nr)"
printf '%s\n' "$steps" | grep -F 'gh release create' | grep -qF -- '--verify-tag' && pass || fail "gh release create uses --verify-tag (the tag pushed before)"
tg="$(printf '%s\n' "$steps" | awk '/\*\*Tag and release\.\*\*/{f=1} f')"
case "$tg" in *'yes'*) pass ;; *) fail "the tag step waits for the user's yes" ;; esac
case "$st$steps" in *'refs/tags/'*) pass ;; *) fail "an existing tag is found before anything changes (refs/tags/)" ;; esac
for w in 'git tag -f' 'tag -d' 'push --delete' '--force'; do assert_not_contains "$SK" "$w"; done
for l in 'Merged:' 'Pushed:' 'Version:' 'Tag:' 'Release:' 'Open:'; do
  printf '%s\n' "$steps" | grep -qF -- "$l" && pass || fail "the report has $l"
done

# Step order (REV-11): the version and changelog edit first, then check: on that tree, then the go-ahead,
# merge, push, tag. A red check: stop with the edit left uncommitted, no repair.
names="$(printf '%s\n' "$steps" | sed -nE 's/^[0-9]+\. \*\*([^*]+)\.\*\*.*/\1/p' | tr '\n' '|')"
assert_eq "$names" 'Version and tag names|Release|Go-ahead|Branch push and CI|Merge|Push|Tag and release|Report|' "the ship steps, in order"
ne="$(printf '%s\n' "$steps" | grep -n 'engineer writes the version' | head -1 | cut -d: -f1)"
nc="$(printf '%s\n' "$steps" | grep -n 'check:' | head -1 | cut -d: -f1)"
[ -n "$ne" ] && [ -n "$nc" ] && [ "$ne" -lt "$nc" ] && pass || fail "the version edit comes before the check: run (lines $ne $nc)"
for w in 'do not run the suite again' 'postcondition 1 is the run of step 1'; do
  case "$steps" in *"$w"*) fail "Steps still says: $w" ;; *) pass ;; esac
done
case "$steps" in *'postconditions 1–7'*) pass ;; *) fail "Release runs release.md postconditions 1–7 on the tree with the new version" ;; esac
case "$steps" in *'no repair'*) pass ;; *) fail "a red check: stops ship with no repair" ;; esac
case "$steps" in *'git status --short'*) pass ;; *) fail "a red check: names the uncommitted files (git status --short)" ;; esac
# The version question has one owner: ship step 1 asks it; release.md defers to ship.
REL="$PLUGIN/skills/task/references/release.md"; PATHS="$PLUGIN/skills/task/references/paths.md"
assert_eq "$(cat "$SK" "$REL" "$PATHS" | grep -c 'where the version lives')" "1" "the version question is asked in one place"
rp="$(awk '/^\*\*Release path/{f=1} f && /^$/{exit} f' "$REL")"
case "$rp" in *ship*) pass ;; *) fail "release.md Release path defers the version question to ship" ;; esac

# Protected default branch (B1): after the go-ahead ship pushes the branch itself and waits for the CI
# checks on that commit; only green goes on to the fast-forward merge and the push of <main>, then the tag.
# A red or cancelled run stops ship with the failed jobs and merges nothing; without gh, or not on GitHub,
# ship asks the user to confirm the merge. The remote branch is never deleted by ship.
line_of() { printf '%s\n' "$steps" | grep -n -- "$1" | head -1 | cut -d: -f1; }
ng="$(line_of 'Wait for the user')"; nb="$(line_of 'git push origin <branch>')"; nw="$(line_of 'gh run ')"
nm="$(line_of 'ff-only')"; np="$(line_of 'git push origin <main>')"; nt="$(line_of 'git tag -a')"
[ -n "$ng" ] && [ -n "$nb" ] && [ -n "$nw" ] && [ -n "$nm" ] && [ -n "$np" ] && [ -n "$nt" ] &&
  [ "$ne" -lt "$ng" ] && [ "$ng" -lt "$nb" ] && [ "$nb" -lt "$nw" ] && [ "$nw" -lt "$nm" ] && [ "$nm" -lt "$np" ] && [ "$np" -lt "$nt" ] && pass ||
  fail "release commit, go-ahead, git push origin <branch>, gh run wait, ff-only merge, git push origin <main>, tag (lines $ne $ng $nb $nw $nm $np $nt)"
ci="$(printf '%s\n' "$steps" | awk '/\*\*Branch push and CI\.\*\*/{f=1} /\*\*Merge\.\*\*/{f=0} f')"
case "$ci" in *'gh run list'*'--commit'*) pass ;; *) fail "the CI step finds the run of the pushed commit (gh run list --commit)" ;; esac
case "$ci" in *'gh run watch'*'--exit-status'*) pass ;; *) fail "the CI step waits with gh run watch --exit-status" ;; esac
case "$ci" in *'gh run view'*'--json jobs'*) pass ;; *) fail "a red run: the failed jobs are shown (gh run view --json jobs)" ;; esac
case "$ci" in *cancelled*) pass ;; *) fail "a cancelled run stops ship like a red one" ;; esac
case "$ci" in *'merge nothing'*|*'merges nothing'*|*'nothing is merged'*) pass ;; *) fail "a red run: nothing is merged" ;; esac
case "$ci" in *'90'*) pass ;; *) fail "no run within a limited wait: ship asks (a limit in seconds, not a tight loop)" ;; esac
case "$ci" in *'Without `gh`'*'ask'*|*'without `gh`'*'ask'*) pass ;; *) fail "without gh, or not on GitHub, the user confirms the merge" ;; esac
case "$ci" in *'rejected'*) pass ;; *) fail "a rejected branch push stops ship" ;; esac
case "$steps" in *'Pushed: origin/<branch>'*) pass ;; *) fail "the report names the pushed branch" ;; esac
# ship never deletes the remote branch: the delete command appears once, in the Report, for the user to run later.
rep="$(printf '%s\n' "$steps" | awk '/\*\*Report\.\*\*/{f=1} f')"
case "$rep" in *'git push origin --delete <branch>'*) pass ;; *) fail "the report gives the command to delete the remote branch later" ;; esac
assert_eq "$(grep -c -- '--delete' "$SK")" "1" "the delete command is only in the Report"

# The release commit subject is short and valid in both worlds: chore(<part>): release <version>, or chore: release <version>.
case "$steps" in *'chore(<part>): release <version>'*'chore: release <version>'*) pass ;; *) fail "the Release step gives the release commit subject" ;; esac

# The README lists the command.
assert_contains "$ROOT/README.md" '/corecrew:ship'
finish
