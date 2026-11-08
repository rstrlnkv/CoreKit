# CoreKit

Three independent plugins for Claude Code and the Codex CLI. Install one, two or all three.

| Plugin | What you get | Hosts |
|---|---|---|
| [**corecrew**](plugins/corecrew/README.md) | Run every project the same way: start from an interview, work with a crew of agents, keep the docs in a private repo. | Claude Code, Codex |
| [**coremodel**](plugins/coremodel/README.md) | Each prompt runs on the model and effort level it needs; you are asked before the costly ones. | Claude Code; a hint in Codex |
| [**coreopinion**](plugins/coreopinion/README.md) | A second opinion from GPT on your code or plan; Claude stays the only one that edits. | Claude Code |

![corecrew](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Frstrlnkv%2FCoreKit%2Fmain%2Fplugins%2Fcorecrew%2F.claude-plugin%2Fplugin.json&query=%24.version&label=corecrew) ![coremodel](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Frstrlnkv%2FCoreKit%2Fmain%2Fplugins%2Fcoremodel%2F.claude-plugin%2Fplugin.json&query=%24.version&label=coremodel) ![coreopinion](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Frstrlnkv%2FCoreKit%2Fmain%2Fplugins%2Fcoreopinion%2F.claude-plugin%2Fplugin.json&query=%24.version&label=coreopinion) ![platform](https://img.shields.io/badge/tested%20on-macOS-lightgrey) ![licence](https://img.shields.io/github/license/rstrlnkv/CoreKit)

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

### Codex

corecrew and coremodel also run in the Codex CLI; coreopinion does not.

```bash
codex plugin marketplace add rstrlnkv/CoreKit
codex plugin add corecrew@corekit
codex plugin add coremodel@corekit
```

Then start `codex`, open `/hooks` and trust the plugins' hooks; until you do, they do not run, and
Codex does not tell you so (corecrew's skills remind you).
The plugin READMEs list the remaining steps.

### Update

```bash
claude plugin marketplace update corekit
claude plugin update corecrew@corekit
```

In Codex: `codex plugin marketplace upgrade corekit`, then trust the hooks again in `/hooks`.

## Features

Each plugin's README has the full description, its commands and its settings:

- [corecrew](plugins/corecrew/README.md): `/corecrew:new-project`, `/corecrew:task`, `/corecrew:ship`
  and `/corecrew:new-standard`, hooks that keep secrets and internal files out of your public
  code, and `save` / `undo-step` for one step at a time.
- [coremodel](plugins/coremodel/README.md): picks Haiku, Sonnet, Opus or Fable and the effort level
  before Claude starts on a prompt; `/coremodel` shows and changes what it does.
- [coreopinion](plugins/coreopinion/README.md): `/coreopinion:second-opinion` asks GPT through the
  Codex CLI, with a narrow read-only permission profile, and sends only the files you confirm.

## Requirements

- **Hosts:** Claude Code 2.1.271 or newer (coremodel needs 2.1.309), or the Codex CLI.
- **OS:** macOS is tested. Linux is expected to work (portable bash, no macOS-only tools), but no
  test run covers it yet. Windows needs Git for Windows and is untested.
- **Per plugin:** corecrew needs git and the GitHub CLI (`gh`); coreopinion needs the Codex CLI
  signed in with a ChatGPT plan. Details, network use and the files each plugin writes are in its README.

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
