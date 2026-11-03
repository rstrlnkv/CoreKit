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
2. `git log -1 --format=%s | awk '{ print length($0) <= 72 }'` → 1
3. no guard — a ticket number in a subject is only caught in review

## Exceptions
none

## Sources
- The owner's own habit.
- filler line 0
- filler line 1
- filler line 2
- filler line 3
- filler line 4
- filler line 5
- filler line 6
- filler line 7
- filler line 8
- filler line 9
- filler line 10
- filler line 11
- filler line 12
- filler line 13
- filler line 14
- filler line 15
- filler line 16
- filler line 17
- filler line 18
- filler line 19
- filler line 20
- filler line 21
- filler line 22
- filler line 23
- filler line 24
- filler line 25
- filler line 26
- filler line 27
- filler line 28
- filler line 29
- filler line 30
- filler line 31
- filler line 32
- filler line 33
- filler line 34
- filler line 35
- filler line 36
- filler line 37
- filler line 38
- filler line 39
- filler line 40
- filler line 41
- filler line 42
- filler line 43
- filler line 44
- filler line 45
- filler line 46
- filler line 47
- filler line 48
- filler line 49
- filler line 50
- filler line 51
- filler line 52
- filler line 53
- filler line 54
- filler line 55
- filler line 56
- filler line 57
- filler line 58
- filler line 59
- filler line 60
- filler line 61
- filler line 62
- filler line 63
- filler line 64
- filler line 65
- filler line 66
- filler line 67
- filler line 68
- filler line 69
- filler line 70
- filler line 71
- filler line 72
- filler line 73
- filler line 74
- filler line 75
- filler line 76
- filler line 77
- filler line 78
- filler line 79
- filler line 80
- filler line 81
- filler line 82
- filler line 83
- filler line 84
- filler line 85
- filler line 86
- filler line 87
- filler line 88
- filler line 89
- filler line 90
- filler line 91
- filler line 92
- filler line 93
- filler line 94
- filler line 95
- filler line 96
- filler line 97
- filler line 98
- filler line 99
