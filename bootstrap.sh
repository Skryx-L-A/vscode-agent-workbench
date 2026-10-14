#!/usr/bin/env bash
# bootstrap.sh — the installer moved to agent-setup; this script only says where.
set -euo pipefail

cat <<'MSG'
This repository no longer installs anything.

The setup it used to install (agent rules, skills, hooks, command-line tools, knowledge-base
skeleton) is now part of agent-setup:

  git clone https://github.com/Skryx-L-A/agent-setup.git
  # then follow INSTALL.md in that checkout

agent-setup has its own license, which is not Apache-2.0; read its LICENSE and the license files
next to it first.

What remains here is the source of the VS Code extension, see README.md.
MSG
