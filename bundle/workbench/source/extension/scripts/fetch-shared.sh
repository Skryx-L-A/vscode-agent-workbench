#!/usr/bin/env bash
# fetch-shared.sh — copy the modules this extension shares with agent-setup into src/.
#
#   scripts/fetch-shared.sh /path/to/agent-setup
#
# Fifteen modules of the extension are also part of agent-setup (extension/src/) and are not
# licensed under Apache-2.0 there: agent-setup has its own license, see its LICENSE. They are
# therefore not stored in this repository. Fetching them
# copies them into your working tree under the license of agent-setup; do not commit them here.
# The versions in agent-setup may have moved on since this source was written, so `npm run check`
# can report type errors until the extension code is adapted to them.
set -euo pipefail

SRC="${1:-}"
[ -n "$SRC" ] && [ -d "$SRC/extension/src" ] || {
  echo "usage: $0 <path to a checkout of https://github.com/Skryx-L-A/agent-setup>" >&2
  exit 2
}
DEST="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/src"

for m in format hooksInfo machine modelsCli providerSecrets remoteResults settingsLog ssh \
         homeHtml models settings state systemInfo tmux workers; do
  [ -f "$SRC/extension/src/$m.ts" ] || { echo "missing in agent-setup: extension/src/$m.ts" >&2; exit 1; }
  cp "$SRC/extension/src/$m.ts" "$DEST/$m.ts"
  echo "copied $m.ts"
done
