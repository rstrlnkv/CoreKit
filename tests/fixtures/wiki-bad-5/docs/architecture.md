---
title: Architecture
description: Components and storage. Read before structural changes.
status: active
files: [src/app.sh, src/lib/]
related: [features/login.md]
updated: 2026-11-03
---

# Demo — architecture

## Components

The entry point is `src/app.sh`. Login is described in
[the login page](features/login.md#flow). The reasoning is in
[decision 001](decisions/001-stack.md). Official docs: [bash](https://www.gnu.org/software/bash/).

## Storage

Files only. See the login page for the one write path.
