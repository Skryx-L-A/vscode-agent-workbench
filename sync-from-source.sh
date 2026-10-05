#!/usr/bin/env bash
# sync-from-source.sh — bring this repository up to date from a working machine.
#
#   ./sync-from-source.sh            copy, translate, report
#   ./sync-from-source.sh --dry-run  show what would change
#
# WHY THIS EXISTS
# ---------------
# This repository is an EXTRACT of a setup that is used daily somewhere else. Two
# things drift the moment someone stops paying attention:
#
#   1. the tools and configs under ~/.claude, ~/.local/bin and ~/.pi, and
#   2. the VS Code extension's source, which lives in its own development repo.
#
# Copying them by hand means the repository is wrong within days — and worse, it
# means one careless copy can carry a name, a hostname or a key into a public
# place. So the copy is a script, and the script ends with a scan that REFUSES to
# finish if it finds either.
#
# WHAT IT DOES NOT COPY
# ---------------------
# Sessions, history, caches, telemetry, the knowledge vault's CONTENT, anything
# under 90-secrets, `auth.json`, and node_modules. The vault SKELETON (structure,
# templates, tooling) is copied; notes never are.
set -uo pipefail

DRY=""
[ "${1:-}" = "--dry-run" ] && DRY="--dry-run"

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
B="$HERE/bundle"
[ -d "$B" ] || { echo "sync: $B fehlt — falsches Verzeichnis?" >&2; exit 1; }

# Where the VS Code extension is developed. Override if it lives elsewhere.
EXT_REPO="${AGENT_WB_EXT_REPO:-$HOME/AI/claude-workbench}"

RS=(rsync -a --delete $DRY --itemize-changes)
say() { printf '\n== %s\n' "$*"; }

say "~/.claude -> bundle/dot-claude"
mkdir -p "$B/dot-claude"
for item in hooks skills roles commands agents plugins settings.json statusline-command.sh; do
  [ -e "$HOME/.claude/$item" ] || continue
  if [ -d "$HOME/.claude/$item" ]; then
    # marketplaces/ sind FREMDE git-Repos, cache/ und data/ sind Laufzeitdaten.
    # Mitkopiert landen sie als leere Verzeichnisse in jedem Klon (git meldet das
    # als "embedded git repository") und tragen fremden Code unter diese Lizenz.
    "${RS[@]}" --exclude 'logs/' --exclude '*.log' --exclude '__pycache__/' \
               --exclude '.DS_Store' --exclude '.pytest_cache/' \
               --exclude 'marketplaces/' --exclude 'cache/' --exclude 'data/' \
               --exclude 'README.md' \
               "$HOME/.claude/$item/" "$B/dot-claude/$item/"
  else
    rsync -a $DRY --itemize-changes "$HOME/.claude/$item" "$B/dot-claude/$item"
  fi
done

say "Plugin-Zeitstempel neutralisieren"
# installedAt/lastUpdated aendern sich bei jedem Plugin-Update und erzeugen einen
# Diff ohne Aussage. Sie sagen ausserdem, wann diese Maschine benutzt wurde -
# das gehoert nicht in ein oeffentliches Repo.
if [ -z "$DRY" ]; then
  /usr/bin/env python3 - "$B/dot-claude/plugins" <<'PY'
import json, pathlib, sys
EPOCH = "1970-01-01T00:00:00.000Z"
KEYS = {"installedAt", "lastUpdated"}

def scrub(node):
    if isinstance(node, dict):
        return {k: (EPOCH if k in KEYS and isinstance(v, str) else scrub(v))
                for k, v in node.items()}
    if isinstance(node, list):
        return [scrub(v) for v in node]
    return node

root = pathlib.Path(sys.argv[1])
for p in sorted(root.rglob("*.json")):
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError):
        continue
    cleaned = scrub(data)
    if cleaned != data:
        p.write_text(json.dumps(cleaned, indent=2) + "\n", encoding="utf-8")
        print(f"   {p.name}")
PY
fi

say "~/.claude/CLAUDE.md -> bundle/dot-claude/CLAUDE.md.template"
# Das Regelwerk ist der Kern des Setups. Die Identitaetszeile wird zum Platzhalter,
# den bootstrap.sh beim Installieren fuellt; alles andere bleibt Wort fuer Wort.
if [ -f "$HOME/.claude/CLAUDE.md" ] && [ -z "$DRY" ]; then
  /usr/bin/env python3 - "$HOME/.claude/CLAUDE.md" "$B/dot-claude/CLAUDE.md.template" <<'PY'
import re, sys
src, dst = sys.argv[1:3]
t = open(src, encoding="utf-8").read()
t = re.sub(
    r"^User: \*\*.*?\n(?:.*?\n)*?(?=\n## )",
    "User: **{{USER_NAME}}** \u2014 GitHub **{{GITHUB_HANDLE}}**, email {{USER_EMAIL}}.\n"
    "Machine: {{MACHINE_DESCRIPTION}}, user `{{OS_USERNAME}}`; projects in `{{PROJECTS_DIR}}`.\n"
    "Adjust anything below that does not match how you want to work \u2014 this file IS the\n"
    "contract every agent reads, so it is meant to be edited.\n",
    t, count=1, flags=re.M)
open(dst, "w", encoding="utf-8").write(t)
print("   CLAUDE.md.template erneuert (%d Zeilen)" % len(t.splitlines()))
PY
elif [ -n "$DRY" ]; then
  echo "   [dry-run] CLAUDE.md -> CLAUDE.md.template"
fi

say "~/.local/bin -> bundle/bin (only this setup's tools)"
mkdir -p "$B/bin"
for f in wb-* claude-worker pi-worker context-guard mcp-shared check-resources run-on \
         limit-survivor brain bm ai-scout framer-inspo claude-md-lint status-freshness \
         vault-sync medien-ui bild video tts stt offline rerank workbench; do
  for path in "$HOME/.local/bin/"$f; do
    [ -f "$path" ] || continue
    rsync -a $DRY --itemize-changes "$path" "$B/bin/$(basename "$path")"
  done
done

say "~/.pi/agent -> bundle/dot-pi/agent (never auth.json)"
if [ -d "$HOME/.pi/agent" ]; then
  mkdir -p "$B/dot-pi/agent"
  # NUR die Konfigurationsdateien, nie das Verzeichnis als Ganzes: unter ~/.pi/agent
  # liegen auch sessions/ (vollstaendige Gespraechsmitschriften) und auth.json.
  for f in ORCHESTRATOR.md WORKER.md RULES.md models.json settings.json; do
    [ -f "$HOME/.pi/agent/$f" ] && rsync -a $DRY --itemize-changes \
      "$HOME/.pi/agent/$f" "$B/dot-pi/agent/$f"
  done
fi

say "vault skeleton -> bundle/knowledge (structure and tooling, no notes)"
if [ -d "$HOME/Knowledge/_meta" ]; then
  mkdir -p "$B/knowledge/tools" "$B/knowledge/templates"
  # logs/ sind Laufzeitspuren eines echten Vaults, keine Werkzeuge - sie haben den
  # Abbruch-Scan beim ersten scharfen Lauf ausgeloest und gehoeren nie ins Repo.
  "${RS[@]}" --exclude '__pycache__/' --exclude '.venv/' --exclude '*.pyc' \
             --exclude '.pytest_cache/' --exclude 'results/' --exclude 'state/' \
             --exclude 'logs/' --exclude '*.log' --exclude 'review-queue/' \
             --exclude 'eval/' --exclude 'state/' --exclude '*.db' \
             --exclude '__pycache__/' --exclude '*.pyc' \
             "$HOME/Knowledge/_meta/tools/" "$B/knowledge/tools/"
  "${RS[@]}" "$HOME/Knowledge/_meta/templates/" "$B/knowledge/templates/"
fi

say "extension source -> bundle/workbench/source"
if [ -d "$EXT_REPO/extension" ]; then
  mkdir -p "$B/workbench/source/extension" "$B/workbench/source/shell-tests"
  "${RS[@]}" --exclude 'node_modules/' --exclude 'dist/' --exclude '*.vsix' \
             --exclude '.DS_Store' \
             "$EXT_REPO/extension/src" "$EXT_REPO/extension/test" \
             "$EXT_REPO/extension/media" "$EXT_REPO/extension/scripts" \
             "$B/workbench/source/extension/"
  for f in package.json package-lock.json tsconfig.json esbuild.mjs; do
    [ -f "$EXT_REPO/extension/$f" ] && rsync -a $DRY --itemize-changes \
      "$EXT_REPO/extension/$f" "$B/workbench/source/extension/$f"
  done
  # The extension source in claude-workbench still says MIT; this repo ships it
  # under PolyForm Noncommercial (2026-10-04).
  [ -z "$DRY" ] && python3 - "$B/workbench/source/extension/package.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
d["license"] = "PolyForm-Noncommercial-1.0.0"
open(p, "w", encoding="utf-8").write(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
PY
  [ -d "$EXT_REPO/shell/tests" ] && "${RS[@]}" "$EXT_REPO/shell/tests/" "$B/workbench/source/shell-tests/"
  [ -f "$EXT_REPO/shell/models.default.json" ] && rsync -a $DRY --itemize-changes \
    "$EXT_REPO/shell/models.default.json" "$B/workbench/models.default.json"
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
            --exclude-dir=.git --exclude=LICENSE --exclude=ADDITIONAL-PERMISSIONS.md --exclude=COMMERCIAL-LICENSE.md --exclude=CONTRIBUTING.md --exclude=pull_request_template.md 2>/dev/null)"; then
  [ -n "$hits" ] && { echo "ABBRUCH: persönliche Spuren:" >&2; echo "$hits" >&2; FAIL=1; }
fi
if hits="$(/usr/bin/grep -rIl -E 'sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{30,}|AKIA[A-Z0-9]{16}|BEGIN [A-Z ]*PRIVATE KEY|xox[bpa]-' \
            "$HERE" --exclude-dir=.git 2>/dev/null)"; then
  # wb-state and the vault pre-push hook CONTAIN these prefixes as detection patterns.
  # Drei Dateien ENTHALTEN diese Praefixe als Erkennungsmuster bzw. als bewusst
  # gefaelschten Testschluessel - das ist ihr Zweck, kein Fund.
  real="$(printf '%s\n' "$hits" | grep -v -e 'bundle/bin/wb-state' -e 'git-hooks/pre-push' \
            -e 'shell-tests/test-registry.sh' -e 'hooks/bash-guard-secrets.sh' || true)"
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
