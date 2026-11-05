# Interview

Ask 2–3 questions per AskUserQuestion call, in the user's language, plain words. Offer options
with a recommended default where possible; the user can always answer freely. Keep the answers
in the conversation until step 2 creates `docs/brief.md`, then write them there **in English**.

| # | Topic | Ask | Options to offer (examples) |
|---|-------|-----|-----------------------------|
| 1 | Purpose | What does the app do, for whom, which problem does it solve? | free text |
| 2 | Platforms | Where must it run? (multi-select) | macOS, Windows, iOS, Android, web |
| 3 | Type | What kind of thing is it? | app with UI, menu-bar/utility, bot, website, command-line tool |
| 4 | v1 features | 3–7 features for the first version; the rest goes to "Later" | free text; push back above 7 |
| 5 | Data | Where is data stored? Sign-in? Must it work offline? | on device / cloud sync; no sign-in / sign-in; offline yes/no |
| 6 | External services | APIs, payments, notifications, AI models? | none / list |
| 7 | Design | Style, dark theme, interface languages | minimal / playful / native; dark: yes/no/system; languages |
| 8 | Visibility | Will the code be public on GitHub? | private (recommended) / public |
| 9 | Done | How will you know v1 is finished? Plain-language checks | free text |

Suggested grouping: (1, 3) → (2, 8) → (4) → (5, 6) → (7, 9).

## Rules
- Do not ask about the stack — the analysis step recommends it.
- If an answer creates a hard constraint (e.g. iOS without a Mac), say so immediately.
- Unclear answer → one follow-up question, not a lecture.
- After the interview, propose the project name (Latin, lowercase, hyphens, 3–40 chars)
  and a one-sentence purpose; get approval.
