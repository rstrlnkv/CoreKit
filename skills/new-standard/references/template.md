---
name: <kebab-case>
description: <one line: what it rules and when an agent needs it>
applies-to: [<roles that must read it>]
updated: YYYY-MM-DD
---
# <Title>

## Rule
<!-- One imperative sentence per line, numbered "1. ", "2. ", ... Delete every comment line. -->
1. <imperative rule>
2. <imperative rule>

## Why
<!-- One line per rule, same numbers: the failure the rule prevents. -->
1. <the failure rule 1 prevents>
2. <the failure rule 2 prevents>

## How to check
<!-- One entry per rule number, in exactly one of two forms:
     "1. <command> → <expected output>"   a command anyone can run, and what it must print
     "2. no guard — <risk>"               nothing checks this rule; state the risk that stays -->
1. <command> → <expected output>
2. no guard — <the risk that stays>

## Exceptions
none

## Sources
- <what the rules rest on: a link, a document, or "the owner's own experience">

<!--
Fill-in notes (delete this whole comment block):
- File: <Core>/standards/<name>.md, English, under 120 lines. <name> is the file name without .md.
- applies-to: any of engineer, tester, security, verifier, localizer, designer, release
  (release = the release procedure). Comma-separated inside [ ].
- The five "## " headings stay in this order. scripts/check-standard.sh checks the shape.
-->
