# vscode-agent-workbench

> **Archived. Successors: [agent-workbench](https://github.com/Skryx-L-A/agent-workbench) and
> [agent-setup](https://github.com/Skryx-L-A/agent-setup).** This repository is no longer
> developed.

This was the VS Code generation of a workbench for orchestrating coding agents: one lead session
that plans and verifies, several worker panes that do the work in parallel, and the machinery
around it. What remains here is the source of the VS Code extension itself: a start page with
session resume, a worker sidebar and "send to orchestrator" context menus.

The desktop program that grew out of it, with the Agents tab, is
**[agent-workbench](https://github.com/Skryx-L-A/agent-workbench)**. The complete setup it runs
in, with the agent rules, skills, hooks, command-line tools and the knowledge-base skeleton, is
**[agent-setup](https://github.com/Skryx-L-A/agent-setup)**. Earlier versions of this repository
also carried copies of those files; they now live only in agent-setup, under the license of that
repository (not Apache-2.0): read its `LICENSE` and the license files next to it before you use it.

## Installing the setup

Install [agent-setup](https://github.com/Skryx-L-A/agent-setup) and follow its `INSTALL.md`. The
scripts `bootstrap.sh` and `bootstrap.ps1` in this repository only print that pointer.

## What is in here

```
bundle/workbench/
  README.md         how the extension, the tmux state files and the tools fit together
  make-launcher-linux.sh   Linux desktop launcher for the "Claude Workbench" VS Code profile
  source/extension/        the extension: TypeScript, no framework, no bundled runtime dependencies
tools/              depersonalize.py and its test: strips one machine's vocabulary from a copy
sync-from-source.sh brings the extension source up to date from a working machine
AGENT-SETUP.md      pointer to the installation instructions in agent-setup
```

## Building the extension

Fifteen modules of the extension are the same code as `extension/src/` in agent-setup, which is
not Apache-2.0. They are not part of this repository. To build, fetch them from a checkout of
agent-setup:

```bash
git clone https://github.com/Skryx-L-A/agent-setup.git
cd vscode-agent-workbench/bundle/workbench/source/extension
scripts/fetch-shared.sh /path/to/agent-setup
npm install
npm run check      # typecheck + tests + build
npm run package    # produces the .vsix
```

The versions in agent-setup may have moved on since this source was written, so the type check can
report errors until the extension code is adapted. No prebuilt `.vsix` is shipped.

The extension calls the `wb-code` and `wb-state` tools, which agent-setup installs into
`~/.local/bin`; without them its start page shows nothing to resume.

## License

Licensed under the Apache License, Version 2.0, see [LICENSE](LICENSE).

Versions up to the commit tagged `last-agpl` were published under AGPL-3.0-only, and up to the
commit tagged `last-polyform` under the PolyForm Noncommercial License 1.0.0. Those versions
remain available under those licenses.

Third-party parts keep their own licenses, see [NOTICE.md](NOTICE.md).

Contributions: see [CONTRIBUTING.md](CONTRIBUTING.md).
