# Analysis: platforms, stack, architecture

Run this yourself. Do not invoke `superpowers:brainstorming` here — its hard gate ends in
`writing-plans` and would skip recording decisions and scaffolding.

## Order (each part approved by the user before the next)
1. **Constraints** — list what the chosen platforms require (see table). Flag blockers.
2. **Stack options** — 2–3 options from `stacks.md`, scored (below), one recommendation.
3. **Verification** — one research subagent checks the options (prompt below). Update scores.
4. **Architecture** — components, data storage and sync, external services, risks.
5. **Record** — write `docs/architecture.md` and `docs/decisions/001-stack-and-architecture.md`
   (English), update `stage: decided` in `docs/brief.md`, show a short summary in the user's
   language, run `save "Decide stack and architecture"`.

## Platform constraints
| Platform | Needs |
|----------|-------|
| iOS / iPadOS | Mac with Xcode; Apple Developer Program for App Store/TestFlight (paid, yearly) |
| macOS | Mac with Xcode; notarization needs a Developer ID (same program) to ship outside the App Store |
| Android | Android Studio / SDK; Google Play developer account (one-time fee) to publish |
| Windows | Building native Windows apps needs Windows (or CI); code signing optional but avoids SmartScreen warnings |
| Web | Hosting; HTTPS; nothing platform-specific |
Prices and programs change — say "check current price" instead of quoting numbers.

## Scoring criteria (1–5, explain each in one line)
- Platform coverage for the chosen platforms
- Offline and local data support
- Native look and feel
- How well AI coding agents write this stack (popularity, docs, stable APIs)
- Community and libraries for the v1 features
- Cost (accounts, licenses, services)
- Build complexity on the user's machines (Mac/Windows)

## Option card (show in the user's language)
**<Stack>** — one-line pitch
- Covers: … | Doesn't cover: …
- Strengths: … | Risks: …
- Score: coverage x/5, offline x/5, native x/5, AI-friendly x/5, community x/5, cost x/5, build x/5
End with: "Recommend: <stack>, because <one sentence tied to the brief>."

## Research subagent prompt
"Verify these stack options for an app with: <platforms>, <type>, <key features>, <data>.
For each option check against official documentation: current stable version, support for each
platform, the non-interactive project generator command, known issues relevant to the features.
Return a compact table with links. Mark anything you could not verify."

## Architecture checklist
- Components (UI, logic, storage, integrations) and what each owns
- Data: where stored, format, sync/backup, migration
- Sign-in and secrets handling (never in the repo)
- External services and their failure behavior
- Risks with a mitigation each
