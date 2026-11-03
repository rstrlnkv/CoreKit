---
name: commit-messages
description: How commit messages are written; read before any commit.
applies-to: [engineer, release]
updated: 2026-11-03
---
# Commit messages

## Rule
1. Start the subject with a verb in the imperative mood.
2. Keep the subject under 72 characters.
3. Never put a ticket number in the subject.

## Why
1. A log of imperative subjects reads as a list of changes.
2. Long subjects are cut off in git log and in review tools.
3. Ticket numbers go stale when the tracker changes.

## How to check
1. `git log -1 --format=%s | grep -E '^[A-Z][a-z]+ '` → one line printed
3. nothing to say

## Exceptions
none

## Sources
- The owner's own habit.
