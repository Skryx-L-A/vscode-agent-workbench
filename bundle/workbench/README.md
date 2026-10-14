# Claude Workbench — the VSCode environment

The workbench turns VSCode into a front end for the tmux orchestrator setup: a start page
with session resume, a worker sidebar, and "send to orchestrator" context menus. The
orchestrator and its workers still run as Claude Code CLI sessions in tmux panes inside
VSCode's integrated terminal — the extension only drives and observes them.

This folder holds the extension source and a Linux launcher. The shell side (`wb-code`,
`wb-state`, the worker spawners) and the VS Code profile setup belong to
[agent-setup](https://github.com/Skryx-L-A/agent-setup), which installs them into `~/.local/bin`.

| Path | What it is |
|---|---|
| `source/extension/` | the extension source, see `source/README.md` for the build |
| `make-launcher-linux.sh` | Linux only: writes a `.desktop` entry that opens VS Code with the "Claude Workbench" profile |

## How the pieces talk

- `wb-code <dir> [--resume <session-id>]` creates the tmux session
  `wb-<basename>-<md5-6-of-path>` with one orchestrator pane and attaches to it. It is
  idempotent: an existing session is only attached.
- `wb-state` maintains `~/.claude/workbench/sessions/<slug>.json` (`dir`, `tmuxSession`,
  `lastActive`, `workers[]`). Writes are atomic and lock-protected.
- `pi-worker` / `claude-worker` register every spawned worker in that state file, so the
  sidebar can show it.
- The extension reads the state files for its start page, checks liveness against
  `tmux list-panes`, and starts `wb-code` in the integrated terminal. It resolves `wb-code`
  from `PATH`, so `~/.local/bin` must be on the PATH of your login shell.

## Start it

`code --profile "Claude Workbench" --new-window` (on Linux `make-launcher-linux.sh` makes a launcher
for exactly that command). The start page opens automatically in an empty window of that profile.
Pick a project, and the extension opens the folder and runs `wb-code` in the terminal panel.

## OS matrix — what works where

| Piece | macOS | Linux | WSL2 | Native Windows (no WSL) |
|---|---|---|---|---|
| Extension | works | works | works (install into the WSL remote) | works, but the tmux features are dead |
| `wb-code`, `wb-state`, workers | works | works | works (inside the distro) | not supported (needs tmux) |

Verification status: the macOS path is the one that has actually been run. Linux and WSL are
untested. Report breakage instead of assuming it works.
