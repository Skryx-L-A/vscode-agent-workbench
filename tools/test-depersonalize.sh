#!/usr/bin/env bash
# test-depersonalize.sh — the promises depersonalize.py makes, checked.
#
# The table this runs against is a FIXTURE of invented names, written to a temp
# directory and pointed at with WB_DEPERSONALIZE_RULES. The real table is
# personal data and never takes part in a test.
#
# What is checked:
#   1. every spelling of a table entry is replaced, not only the one written down
#      (the abort scan searches case-insensitively; the translator used to not)
#   2. a spelling the table names explicitly keeps ITS replacement — the table
#      holds the same name twice on purpose, and one blind insensitive pass would
#      let the first entry swallow both
#   3. a second run changes nothing (idempotent)
#   4. a word that is not in the table is left alone (never invents)
#   5. a text without a single hit stays byte for byte the same
#
# Usage: tools/test-depersonalize.sh
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/depersonalize.py"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/depersonalize-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

FAIL=0
ok()   { printf '   ok    %s\n' "$*"; }
bad()  { printf '   FAIL  %s\n' "$*" >&2; FAIL=1; }
check() { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"; else
    bad "$1"; printf '         erwartet: %s\n         bekommen: %s\n' "$2" "$3" >&2
  fi
}

# ---------------------------------------------------------------- the fixture
RULES="$WORK/fixture.rules"
printf '%s\n' \
  '# FIXTURE — invented names only.' \
  '[rules]' \
  "$(printf 'ZAPHOD_\tPEER_')" \
  "$(printf '\\bzaphod\\b\tpeer')" \
  '# Pfade VOR den Personen, sonst frisst der bare Name den Pfad auf.' \
  "$(printf '/Users/trillian\t$HOME')" \
  "$(printf '\\bTrillian Beeblebrox\\b\tthe user')" \
  "$(printf 'Trillians\\s+([A-Za-z][A-Za-z-]*)\t\\1 des Nutzers')" \
  "$(printf '\\bTrillian\\b\tder Nutzer')" \
  "$(printf '\\btrillian\\b\tperson-1')" \
  '[source_rules]' \
  "$(printf '\\bTrillian\\b\ttrillian')" \
  "$(printf 'ZAPHOD_\tPEER_')" \
  > "$RULES"
export WB_DEPERSONALIZE_RULES="$RULES"

run() { PYTHONDONTWRITEBYTECODE=1 /usr/bin/env python3 "$TOOL" "$1" >/dev/null; }
body() { tr -d '\n' < "$1"; }

# --------------------------------------------- 1. every spelling gets replaced
T="$WORK/spellings"; mkdir -p "$T"
printf 'ZAPHOD_HOST zaphod_host Zaphod_host' > "$T/mixed.txt"
run "$T"
check "gemischte Schreibweisen werden alle ersetzt" \
      "PEER_HOST peer_host Peer_host" "$(body "$T/mixed.txt")"

# ------------------------------- 2. an explicitly named spelling keeps its own
# Trillian -> der Nutzer, trillian -> person-1: two entries, two replacements.
# A blind case-insensitive run would give both the first one.
T="$WORK/siblings"; mkdir -p "$T"
printf 'Trillian und trillian und TRILLIAN' > "$T/two.txt"
run "$T"
check "case-Geschwister behalten ihren eigenen Ersatz" \
      "der Nutzer und person-1 und DER NUTZER" "$(body "$T/two.txt")"

# ------------------------------------------------ 3. a second run changes nothing
T="$WORK/idempotent"; mkdir -p "$T"
printf 'ZAPHOD_X zaphod Trillian trillian TRILLIAN Trillians Handtuch /Users/trillian/x' \
  > "$T/a.txt"
run "$T"; cp "$T/a.txt" "$WORK/after-first"
run "$T"
check "zweiter Lauf aendert nichts" \
      "$(body "$WORK/after-first")" "$(body "$T/a.txt")"

# ---------------------------------------------------- 4. unknown words untouched
T="$WORK/unknown"; mkdir -p "$T"
printf 'Marvin und marvin und MARVIN und Fenchurch und zaphodian' > "$T/other.txt"
run "$T"
check "Wort ohne Tabelleneintrag bleibt unangetastet" \
      "Marvin und marvin und MARVIN und Fenchurch und zaphodian" "$(body "$T/other.txt")"

# ------------------------------------------------- 5. no hit means no byte moved
T="$WORK/untouched"; mkdir -p "$T"
printf 'Ein Text ohne einen einzigen Treffer.\nZweite Zeile.\n' > "$T/clean.txt"
BEFORE="$(shasum "$T/clean.txt" | cut -d' ' -f1)"
run "$T"
check "Text ohne Treffer bleibt Byte fuer Byte gleich" \
      "$BEFORE" "$(shasum "$T/clean.txt" | cut -d' ' -f1)"

# ------------------- 6. under bundle/workbench/source the source table applies
T="$WORK/source/bundle/workbench/source"; mkdir -p "$T"
printf 'Trillian TRILLIAN ZAPHOD_X' > "$T/code.ts"
run "$WORK/source"
check "[source_rules] gelten unter bundle/workbench/source" \
      "trillian TRILLIAN PEER_X" "$(body "$T/code.ts")"

# ----- 7. a replacement with a backreference keeps the captured text unchanged
T="$WORK/backref"; mkdir -p "$T"
printf 'Trillians Handtuch' > "$T/gen.txt"
run "$T"
check "Rueckverweis traegt den erfassten Text unveraendert durch" \
      "Handtuch des Nutzers" "$(body "$T/gen.txt")"

# ------------- 8. a replacement that is not a plain word keeps its own spelling
T="$WORK/placeholder"; mkdir -p "$T"
printf '/Users/trillian/x /USERS/TRILLIAN/y' > "$T/paths.txt"
run "$T"
check "Platzhalter-Ersatz behaelt seine Schreibweise" \
      '$HOME/x $HOME/y' "$(body "$T/paths.txt")"

echo
if [ "$FAIL" = 0 ]; then echo "depersonalize: alle Zusagen gehalten."; else
  echo "depersonalize: Zusagen VERLETZT." >&2; fi
exit "$FAIL"
