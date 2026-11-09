# CoreKit

Three plugins for Claude Code and Codex: a project workflow (corecrew), a model and effort picker (coremodel) and a second opinion from GPT (coreopinion).

![corecrew](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Frstrlnkv%2FCoreKit%2Fmain%2Fplugins%2Fcorecrew%2F.claude-plugin%2Fplugin.json&query=%24.version&label=corecrew) ![coremodel](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Frstrlnkv%2FCoreKit%2Fmain%2Fplugins%2Fcoremodel%2F.claude-plugin%2Fplugin.json&query=%24.version&label=coremodel) ![coreopinion](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Frstrlnkv%2FCoreKit%2Fmain%2Fplugins%2Fcoreopinion%2F.claude-plugin%2Fplugin.json&query=%24.version&label=coreopinion) ![platform](https://img.shields.io/badge/tested%20on-macOS%20%7C%20Linux-lightgrey) ![licence](https://img.shields.io/github/license/rstrlnkv/CoreKit)

## Install

### Claude Code

Add the marketplace once, then install the plugins you want:

```bash
claude plugin marketplace add rstrlnkv/CoreKit
claude plugin install corecrew@corekit
claude plugin install coremodel@corekit
claude plugin install coreopinion@corekit
```

Inside a running session the same steps are `/plugin marketplace add rstrlnkv/CoreKit`, then
`/plugin install corecrew@corekit`, `/plugin install coremodel@corekit` or
`/plugin install coreopinion@corekit`. Optional: `feature-dev` gives `/corecrew:task` deeper
architect and explorer agents: `/plugin install feature-dev@claude-plugins-official`. Restart
Claude Code after an install.

Recommended: add the deny rules from [SECURITY.md](SECURITY.md#recommended-host-settings) to your
Claude Code settings. They keep `.env` files and `~/.ssh` away from Claude's file tools. That is
the boundary; the plugins' hooks only back it up.

### Codex

corecrew and coremodel also run in the Codex CLI; coreopinion does not.

```bash
codex plugin marketplace add rstrlnkv/CoreKit
codex plugin add corecrew@corekit
codex plugin add coremodel@corekit
```

Then start `codex`, open `/hooks` and trust the plugins' hooks; until you do, they do not run, and
Codex does not tell you so (corecrew's `new-project`, `task` and `ship` remind you when they run).
The plugin READMEs list the remaining steps.

### Update

```bash
claude plugin marketplace update corekit
claude plugin update corecrew@corekit
```

In Codex: `codex plugin marketplace upgrade corekit`, then trust the hooks again in `/hooks`.

## Features

Each plugin's README has the full description, its commands and its settings.

| Feature | What it does |
|---|---|
| [**corecrew**](plugins/corecrew/README.md) | Runs every project the same way: it starts from an interview, works with a crew of agents and keeps the docs in a private repo. Commands: `/corecrew:new-project`, `/corecrew:task`, `/corecrew:ship` and `/corecrew:new-standard`; hooks keep secrets and internal files out of your public code; `save` and `undo-step` go one step at a time. Hosts: Claude Code, Codex. |
| [**coremodel**](plugins/coremodel/README.md) | Picks Haiku, Sonnet, Opus or Fable and the effort level before Claude starts on a prompt, and asks before the costly ones. Command: `/coremodel` shows and changes what it does. Hosts: Claude Code; in Codex, a hint you turn on. |
| [**coreopinion**](plugins/coreopinion/README.md) | Gets a second opinion from GPT on your code or plan through the Codex CLI, with a narrow read-only permission profile, and sends only the files you confirm; Claude stays the only one that edits. Command: `/coreopinion:second-opinion`. Host: Claude Code. |

## Requirements

- **Hosts:** Claude Code 2.1.271 or newer (coremodel needs 2.1.309), or the Codex CLI.
- **OS:** macOS and Linux: CI runs the full suite on both, on macOS with its system bash 3.2.
  Windows needs Git for Windows and is untested.
- **CPU architecture:** any; the plugins are bash scripts and a TypeScript module with no native
  code ([corecrew](plugins/corecrew/README.md#requirements), [coremodel](plugins/coremodel/README.md#requirements),
  [coreopinion](plugins/coreopinion/README.md#requirements)).
- **Per plugin:** corecrew needs git and the GitHub CLI (`gh`); coreopinion needs the Codex CLI
  signed in with a ChatGPT plan.
- **Network:** corecrew reaches GitHub through `gh` and `git`, coremodel has no host of its own
  (its Codex hint, once on, sends each prompt to OpenAI), and coreopinion sends the files you
  confirm to OpenAI through the Codex CLI
  ([corecrew](plugins/corecrew/README.md#what-it-runs-and-sends), [coremodel](plugins/coremodel/README.md#requirements),
  [coreopinion](plugins/coreopinion/README.md#requirements)).
- **Permissions:** corecrew's hooks refuse some reads and writes, and its project settings let
  Claude reach the project's Core folder from the code folder; coremodel asks for nothing beyond its
  hooks; coreopinion runs Codex with a narrow read-only profile ([corecrew](plugins/corecrew/README.md#requirements),
  [coremodel](plugins/coremodel/README.md#requirements),
  [coreopinion](plugins/coreopinion/README.md#what-is-sent-and-what-gpt-can-read)).
- **Changes outside its own folders:** corecrew keeps a tools copy in its data folder, writes your
  Core and puts git hooks into your code repos; coremodel and coreopinion leave nothing behind
  ([corecrew](plugins/corecrew/README.md#changes-outside-the-repo), [coremodel](plugins/coremodel/README.md#requirements),
  [coreopinion](plugins/coreopinion/README.md#requirements)).

## Uninstall

`claude plugin uninstall <name>@corekit`, or `codex plugin remove <name>@corekit` in Codex.
Remove corecrew's git hooks first, or commits in your repos stop working: see
[corecrew's Uninstall section](plugins/corecrew/README.md#uninstall). The other plugins'
READMEs say what they leave behind.

## Development

- [CONTRIBUTING.md](CONTRIBUTING.md): rules, tests and releases.
- [ARCHITECTURE.md](ARCHITECTURE.md): how the repo is laid out.
- [SECURITY.md](SECURITY.md): the threat model, and how to report a vulnerability.
- Changes: [CHANGELOG.md](CHANGELOG.md) (corecrew), [coremodel](plugins/coremodel/CHANGELOG.md),
  [coreopinion](plugins/coreopinion/CHANGELOG.md).

## Licence

MIT — see [LICENSE](LICENSE).
