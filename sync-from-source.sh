#!/usr/bin/env bash
# sync-from-source.sh — bring this repository up to date from a working machine.
#
#   ./sync-from-source.sh            copy, translate, report
#   ./sync-from-source.sh --dry-run  show what would change
#
# WHY THIS EXISTS
# ---------------
# This repository is an EXTRACT of the VS Code extension's source, which lives in its own
# development repo. Copying it by hand means the repository is wrong within days — and worse,
# it means one careless copy can carry a name, a hostname or a key into a public place. So the
# copy is a script, and the script ends with a scan that REFUSES to finish if it finds either.
#
# WHAT IT DOES NOT COPY
# ---------------------
# Node modules, build output, and the fifteen modules that agent-setup also contains
# (SHARED_MODULES below): those are not Apache-2.0, so they must never land in this repository.
# scripts/fetch-shared.sh brings them into a working tree for building. Everything else the
# old bundle held (rules, skills, hooks, tools, knowledge-base skeleton) lives in agent-setup.
set -uo pipefail

DRY=""
[ "${1:-}" = "--dry-run" ] && DRY="--dry-run"

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
B="$HERE/bundle"
[ -d "$B" ] || { echo "sync: $B fehlt — falsches Verzeichnis?" >&2; exit 1; }

# Where the VS Code extension is developed. Override if it lives elsewhere.
EXT_REPO="${AGENT_WB_EXT_REPO:-$HOME/AI/claude-workbench}"

# Extension modules that are also part of agent-setup (not Apache-2.0 there). Keep this
# list identical to the one in bundle/workbench/source/extension/scripts/fetch-shared.sh.
SHARED_MODULES=(format hooksInfo machine modelsCli providerSecrets remoteResults settingsLog ssh
                homeHtml models settings state systemInfo tmux workers)
SHARED_EXCLUDES=()
for m in "${SHARED_MODULES[@]}"; do SHARED_EXCLUDES+=(--exclude "$m.ts"); done

RS=(rsync -a --delete $DRY --itemize-changes)
say() { printf '\n== %s\n' "$*"; }

say "extension source -> bundle/workbench/source"
if [ -d "$EXT_REPO/extension" ]; then
  mkdir -p "$B/workbench/source/extension"
  # --exclude also protects the receiving side: shared modules and fetch-shared.sh are never
  # deleted or copied by --delete/--exclude interplay.
  "${RS[@]}" --exclude 'node_modules/' --exclude 'dist/' --exclude '*.vsix' \
             --exclude '.DS_Store' --exclude 'fetch-shared.sh' "${SHARED_EXCLUDES[@]}" \
             "$EXT_REPO/extension/src" "$EXT_REPO/extension/test" \
             "$EXT_REPO/extension/media" "$EXT_REPO/extension/scripts" \
             "$B/workbench/source/extension/"
  for f in package.json package-lock.json tsconfig.json esbuild.mjs; do
    [ -f "$EXT_REPO/extension/$f" ] && rsync -a $DRY --itemize-changes \
      "$EXT_REPO/extension/$f" "$B/workbench/source/extension/$f"
  done
  # The extension source in claude-workbench still says MIT; this repo ships it
  # under Apache-2.0 (2026-10-14).
  [ -z "$DRY" ] && python3 - "$B/workbench/source/extension/package.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
d["license"] = "Apache-2.0"
open(p, "w", encoding="utf-8").write(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
PY
fi

if [ -n "$DRY" ]; then
  echo
  echo "(Trockenlauf — nichts geschrieben, keine Übersetzung, kein Scan.)"
  exit 0
fi

say "translate: remove one machine's vocabulary"
PYTHONDONTWRITEBYTECODE=1 /usr/bin/env python3 "$HERE/tools/depersonalize.py" "$HERE" || {
  echo "ABBRUCH: Übersetzung fehlgeschlagen." >&2; exit 1; }

say "refuse to finish if anything personal or secret survived"
FAIL=0
# Die gesuchten Namen stehen NICHT in dieser Datei. Sie kommen aus derselben
# externen Regeltabelle, die auch depersonalize.py liest - dort steht links das
# Muster, und genau danach wird hier gesucht.
#
# Frueher stand die Tabelle in den beiden Skripten selbst. Das erzwang zwei
# Ausnahmen von dieser Pruefung (--exclude), und diese Ausnahmen sind der Grund,
# warum persoenliche Daten einmal bis in ein oeffentliches Repo durchgerutscht
# sind: das Tor war fuer genau die zwei Dateien blind, die lecken konnten.
# Ohne eingebaute Tabelle braucht es keine Ausnahme mehr - hier wird alles geprueft.
RULES_FILE="${WB_DEPERSONALIZE_RULES:-${XDG_CONFIG_HOME:-$HOME/.config}/agent-workbench/depersonalize.rules}"
if [ ! -f "$RULES_FILE" ]; then
  echo "ABBRUCH: keine Regeltabelle unter $RULES_FILE — ohne sie kann nicht geprueft werden," >&2
  echo "         ob persoenliche Spuren uebrig sind. Vorlage: tools/depersonalize.rules.example" >&2
  exit 1
fi
# Linke Spalte der Tabelle, Regex-Sonderzeichen entschaerft, zu einer Alternative verbunden.
#
# WORTGRENZEN ZUERST WEG, DANN DIE ESCAPES (Korrektur 17.08.2026). Die vorige
# Fassung loeschte nur den Backslash und liess den Buchstaben dahinter stehen:
# aus der Wortgrenze `\b` wurde ein literales `b`, das am Suchbegriff klebte.
# 31 der Tabellenzeilen benutzen Wortgrenzen, und von 39 eindeutigen Begriffen
# konnten damit 21 in keinem Text mehr vorkommen. Gemessen an einem
# unuebersetzten Baum mit nachweislich 39 betroffenen Dateien meldete dieses Tor
# 13 -- es haette den Lauf in 26 Faellen durchgelassen. Genau derselbe
# Fehlertyp wie am 29.07.2026, als Personendaten in ein oeffentliches Repo
# gelangten: das Tor meldet "nichts gefunden", weil es an der falschen Stelle
# sucht. Ein Tor, das nicht trifft, ist schlimmer als keines, weil es Sicherheit
# behauptet.
#
# `-i` sucht ohnehin Teilzeichenketten, eine Wortgrenze braucht diese Suche
# also nicht -- sie ganz zu entfernen ist die konservative Richtung: der Scan
# findet dadurch mehr, nie weniger.
NEEDLE="$(awk -F'\t' '/^[^#[]/ && NF>1 {gsub(/\\[bB]/,"",$1); gsub(/\\/,"",$1); gsub(/[][(){}?*+^$|]/,"",$1); if (length($1)>3) print $1}' \
          "$RULES_FILE" | sort -u | paste -sd'|' -)"
if [ -z "$NEEDLE" ]; then echo "ABBRUCH: Regeltabelle ergab kein Suchmuster." >&2; exit 1; fi
if hits="$(/usr/bin/grep -rIl -iE "$NEEDLE" "$HERE" \
            --exclude-dir=.git --exclude=LICENSE --exclude=CONTRIBUTING.md --exclude=pull_request_template.md 2>/dev/null)"; then
  [ -n "$hits" ] && { echo "ABBRUCH: persönliche Spuren:" >&2; echo "$hits" >&2; FAIL=1; }
fi
if hits="$(/usr/bin/grep -rIl -E 'sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{30,}|AKIA[A-Z0-9]{16}|BEGIN [A-Z ]*PRIVATE KEY|xox[bpa]-' \
            "$HERE" --exclude-dir=.git 2>/dev/null)"; then
  real="$hits"
  [ -n "$real" ] && { echo "ABBRUCH: mögliche Geheimnisse:" >&2; echo "$real" >&2; FAIL=1; }
fi
# Dateiarten, die hier grundsaetzlich nichts verloren haben - unabhaengig vom Inhalt.
if stray="$(find "$HERE" -path "$HERE/.git" -prune -o \
        \( -name "*.jsonl" -o -name "auth.json" -o -name "*.pem" -o -name "id_*" \) -print 2>/dev/null)"; then
  [ -n "$stray" ] && { echo "ABBRUCH: Sitzungs-/Schluesseldateien im Repo:" >&2; echo "$stray" >&2; FAIL=1; }
fi
[ "$FAIL" = 1 ] && exit 1
echo "   nichts gefunden."

echo
echo "Fertig. Änderungen prüfen mit: git -C $HERE status --short"
echo "Vor dem Push: cd bundle/workbench/source/extension && npm install && npm run check"
