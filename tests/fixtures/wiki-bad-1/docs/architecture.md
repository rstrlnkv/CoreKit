---
type: architecture
status: active
description: Components and storage. Read before structural changes.
files: [src/app.sh, src/lib/]
related: ["[[login]]"]
updated: 2026-11-03
---

# Demo — architecture

## Components

The entry point is `src/app.sh`. Login is described in [[login#Flow]]. The reasoning is in
[[001-stack]]. Official docs: [bash](https://www.gnu.org/software/bash/).

## Storage

Files only. See [[features/login#Flow|the write path]] for the one write path.
