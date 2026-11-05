---
type: feature
status: active
description: How a user logs in. Read before changing the login flow.
files:
  - src/login.sh
related:
  - "[[architecture]]"
updated: 2026-11-03
---

# Login

## Flow

The user passes a token; `src/login.sh` checks it. Back to [components](../architecture.md#components) or [top](#flow).

## Errors

A wrong token exits with 1.
