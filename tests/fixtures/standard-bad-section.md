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

## How to check
1. `git log -1 --format=%s | grep -E '^[A-Z][a-z]+ '` → one line printed
2. `git log -1 --format=%s | awk '{ print length($0) <= 72 }'` → 1
3. no guard — a ticket number in a subject is only caught in review

## Exceptions
none

## Sources
- The owner's own habit.
