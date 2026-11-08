# Stacks

Starting options for the analysis step. Versions and flags change: the research subagent re-checks
each recipe against the official docs for every new project. Install steps differ by system; each
stack links its official install page, which covers macOS, Windows and Linux.

## Contents
- How to generate into the code folder (all stacks)
- Choosing a stack
- Flutter · SwiftUI (XcodeGen) · Tauri v2 · Web (Vite) · Telegram bot (Python) · Python CLI

## How to generate into the code folder (all stacks)
The code folder (`<Projects>/<name>`) already holds `.git`, `.gitignore`, `.claude/`, `.worktreeinclude`. Generators either
refuse a non-empty folder or their overwrite flags delete everything except `.git`.
**Never run a generator with `--force`/`--overwrite` in the code folder.** Always:
```bash
TMP=$(mktemp -d) && cd "$TMP" && <generator command>
bash <skill>/scripts/merge-generated.sh "$TMP/<generated-folder>" "<Projects>/<name>"
```
`merge-generated.sh` never overwrites files and appends missing `.gitignore` lines.
Names: `<name>` = project name (`my-notes-app`), `<snake>` = `my_notes_app`,
`<Camel>` = `MyNotesApp`, `<org>` = the app id prefix (`app-id-prefix` in `<Core>/.coredev`, e.g. `com.yourname`).

## Choosing a stack
| Need | First choice | Also consider |
|------|--------------|---------------|
| iOS + Android (+ desktop) from one codebase | Flutter | — |
| Apple only, most native feel | SwiftUI | Flutter if Android may come later |
| Desktop Mac + Windows, web-tech UI, small binaries | Tauri v2 | Flutter |
| Runs in a browser | Vite (React + TS) | — |
| Telegram bot | Python + aiogram 3 | — |
| Command-line tool | Python CLI (uv) | — |
| Anything else | The research step proposes a stack and its non-interactive generator from the official docs, and verifies it before it is used | — |

## Flutter — iOS, Android, macOS, Windows, web
- **Install:** the Flutter SDK for your system (https://docs.flutter.dev/get-started/install), Android
  Studio for Android; iOS and macOS builds need a Mac with Xcode (`sudo xcodebuild -runFirstLaunch`) and
  CocoaPods. Check: `flutter doctor`.
- **Generate:** `flutter create --org <org> --project-name <snake> --platforms ios,android,macos,windows,web --empty <snake>`
- **Check:** `flutter pub get && flutter analyze && flutter test && flutter build macos --debug`
  (`flutter build web` also works headless; Windows builds need Windows).
- **Pitfalls:** `--project-name` must be snake_case (no hyphens, no Dart keywords, not `flutter`/`test`);
  bundle id = `<org>.<snake>` and is hard to change later; non-ASCII paths break Android builds.
- **Docs:** https://docs.flutter.dev/reference/flutter-cli

## SwiftUI — Apple platforms, via XcodeGen
- **Install (macOS only):** Xcode, then XcodeGen (https://github.com/yonaskolb/XcodeGen#installing); iOS may
  need `xcodebuild -downloadPlatform iOS`.
- **Generate:** write `project.yml` and `Sources/App.swift` (a `@main` SwiftUI `App`), then `xcodegen generate`:
  ```yaml
  name: <Camel>
  options: { bundleIdPrefix: <org>, deploymentTarget: { macOS: "14.0" } }
  targets:
    <Camel>:
      type: application
      platform: macOS          # iOS: platform iOS, deploymentTarget iOS "17.0",
      sources: [Sources]       #      info.properties: { UILaunchScreen: {} }
      info: { path: Sources/Info.plist, properties: {} }
      scheme: {}
  ```
  Add `*.xcodeproj` to `.gitignore` (regenerated from `project.yml`).
- **Check:** `xcodebuild -project <Camel>.xcodeproj -scheme <Camel> -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`
  (iOS: `-destination 'generic/platform=iOS Simulator'`).
- **Pitfalls:** target names CamelCase without hyphens; App Store / TestFlight need the paid Apple program.
- **Docs:** https://github.com/yonaskolb/XcodeGen (Docs/ProjectSpec.md)

## Tauri v2 — desktop macOS + Windows
- **Install:** the prerequisites for your system (https://v2.tauri.app/start/prerequisites): Rust via rustup,
  Node LTS, and the system part (macOS: Xcode Command Line Tools; Windows: MSVC Build Tools and WebView2; Linux:
  the WebKitGTK packages listed there).
- **Generate (in TMP):** `npm create tauri-app@latest <name> -- --template react-ts --manager npm --identifier <org>.<snake-without-underscores> --tauri-version 2 --yes`
- **Check:** `npm install && npm run tauri build -- --debug --no-bundle`
- **Pitfalls:** always pass `--identifier` (unique reverse-DNS); `--yes` in a non-empty folder exits 1;
  `--force` deletes everything but `.git`; npm 7+ needs the `--` before flags.
- **Docs:** https://v2.tauri.app/start/create-project/ · https://v2.tauri.app/reference/cli/

## Web — Vite (React + TypeScript)
- **Install:** Node.js LTS (https://nodejs.org/en/download; Vite needs Node 20.19+ or 22.12+).
- **Generate (in TMP):** `npm create vite@latest <name> -- --template react-ts --no-interactive`
- **Check:** `npm install && npm run build`
- **Pitfalls:** in a non-empty folder it prints "Operation cancelled" and **exits 0 creating nothing** —
  always generate in TMP and check the folder exists; a wrong `--template` silently falls back to
  `vanilla-ts`; never use `--immediate` (starts a dev server that never exits).
- **Docs:** https://vite.dev/guide/

## Telegram bot — Python + aiogram 3
- **Install:** uv (https://docs.astral.sh/uv/getting-started/installation/).
- **Generate (in TMP):** `uv init --app --name <name> --vcs none --python 3.12 <name> && cd <name> && uv add "aiogram>=3,<4"`
  (apps are packaged by default: `src/<snake>/`).
- **Check:** `uv run python -m compileall -q src && uv run python -c "import aiogram, <snake>"`
- **Pitfalls:** bot token only in `.env` (git-ignored), never in code; aiogram 3 is async (`asyncio.run(main())`);
  pytest exits 5 when there are no tests yet.
- **Docs:** https://docs.astral.sh/uv/concepts/projects/init/ · https://docs.aiogram.dev/

## Python CLI — uv
- **Install:** uv (https://docs.astral.sh/uv/getting-started/installation/).
- **Generate (in TMP):** `uv init --package --name <name> --vcs none --python 3.12 <name>`
- **Check:** `uv run <name>` prints the template greeting; `uv run python -m compileall -q src`
- **Pitfalls:** distribution name keeps hyphens, module is `<snake>`; add `uv add --dev pytest ruff`.
- **Docs:** https://docs.astral.sh/uv/reference/cli/

## Check at use
The value lists of some flags (Flutter `--platforms`, Tauri `--template` and `--manager`) change
between releases: the research step checks them before a generator runs. Generation always happens
in a temp folder with `--vcs none` (uv), so a generator never meets the code folder's git repo.
