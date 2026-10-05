#!/usr/bin/env python3
"""Strip one machine's vocabulary out of the extracted setup.

This exists because the repository is copied FROM a machine where a real person
works. Their name, their hostname, their project names and their example paths
are all over the comments — not as secrets, but as noise that makes the setup
look like someone's private thing rather than something you can adopt.

Three rules make this safe to run repeatedly:

  * It is idempotent. Running it twice changes nothing the second time.
  * It never invents. Every replacement maps a specific known token to a neutral
    one; nothing is guessed from context.
  * The replacement table is NOT in this file. It maps real names to neutral
    ones, so the table itself is personal data. It is read from
    ~/.config/agent-workbench/depersonalize.rules (override with
    WB_DEPERSONALIZE_RULES); ``depersonalize.rules.example`` shows the format.
    An earlier version kept the table inline, which forced this file to exempt
    itself from every check - and that exemption is precisely how personal data
    reached a public repository. Without a table there is nothing to exempt.

The German role prompts are the tricky part: replacing a name with "der Nutzer"
produces the wrong grammatical case, so the case is repaired explicitly
afterwards. The English files get "the user" instead.

Upper and lower case is the second tricky part. The abort scan in
``sync-from-source.sh`` searches case-INsensitively, so it finds spellings this
tool used to walk past: it reported a file nobody could explain, because the
translator had reported success. The table cannot simply be applied
case-insensitively, though — it deliberately holds the same name twice in
different spellings with DIFFERENT replacements, and one insensitive pass would
let the first of the two swallow both. So the table is applied twice: once
exactly as written, then a second time case-insensitively over whatever spelling
no entry claimed. The second pass carries the spelling of the found text over to
the replacement, because the source compares and normalises machine names as
strings and flattening a spelling there changes what a comparison decides.

Usage:  depersonalize.py <repo-root>
"""
import os
import re
import sys

RULES_ENV = "WB_DEPERSONALIZE_RULES"
RULES_DEFAULT = os.path.join(
    os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")),
    "agent-workbench", "depersonalize.rules",
)


def _rules_path():
    """Where the personal replacement table lives. Never inside this repo."""
    return os.environ.get(RULES_ENV) or RULES_DEFAULT


def load_rules(path=None):
    """Read the replacement table from an external file.

    The table maps one person's real tokens to neutral ones, so it IS personal
    data and must not ship with the tool. Format: one ``<regex>\t<replacement>``
    per line, ``#`` comments, sections ``[rules]`` and ``[source_rules]``.
    See ``depersonalize.rules.example``.
    """
    path = path or _rules_path()
    out = {"rules": [], "source_rules": []}
    if not os.path.exists(path):
        return out
    section = "rules"
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            marker = line.strip()
            if marker.startswith("[") and marker.endswith("]"):
                section = marker[1:-1]
                out.setdefault(section, [])
                continue
            if "\t" not in line:
                continue
            pattern, replacement = line.split("\t", 1)
            out[section].append((pattern, replacement))
    return out


_LOADED = load_rules()
RULES = _LOADED["rules"]

# A blind name->"der Nutzer" swap leaves the nominative everywhere. These put the
# right case back where the surrounding word decides it.
CASE = [
    (r'\b(an|für|fuer|ohne|um|gegen|durch|über|ueber|auf)\s+der\s+Nutzer\b', r'\1 den Nutzer'),
    (r'\b(mit|bei|nach|aus|seit|unter|neben|vor)\s+der\s+Nutzer\b', r'\1 dem Nutzer'),
    (r'\bvon\s+der\s+Nutzer\b', 'vom Nutzer'),
    (r'\bzu\s+der\s+Nutzer\b', 'zum Nutzer'),
    (r'\bder\s+Nutzer\s+(sagen|melden|zeigen|erklären|erklaeren|mitteilen|antworten|berichten)\b',
     r'dem Nutzer \1'),
    (r'\b(es|das|dies)\s+der\s+Nutzer\b', r'\1 dem Nutzer'),
    # English sentences that caught the German replacement
    (r'\b(to|ask|unless|when|whenever|if|or|of|and|for|with|from|by|tells|told|asks|asked)\s+der\s+Nutzer\b',
     r'\1 the user'),
    (r'\bder\s+Nutzer\s+(signals|directly|wants|says|asks|himself|first|explicitly|before)\b',
     r'the user \1'),
]

# Regeln NUR fuer bundle/workbench/source/** - siehe Kommentar unten bei SOURCE_SUBPATH.
SOURCE_RULES = _LOADED["source_rules"]
COMPILED_SOURCE = [(re.compile(a), b) for a, b in SOURCE_RULES]
SOURCE_SUBPATH = os.path.join('bundle', 'workbench', 'source')

SKIP_DIRS = {'.git', 'node_modules', '__pycache__', '.venv', '.pytest_cache', 'dist'}
SKIP_SUFFIX = ('.vsix', '.png', '.jpg', '.jpeg', '.gif', '.ico', '.ttf', '.woff',
               '.woff2', '.zip', '.gz', '.bundle')
# Nothing is exempt any more. The replacement table used to live in this file,
# which forced an exemption - and that exemption is exactly why personal data
# once survived the check. The table is external now, so the guard can cover
# every file without exception.
# License files carry the handle and the licensing address on purpose.
SKIP_FILES = {"LICENSE", "ADDITIONAL-PERMISSIONS.md", "COMMERCIAL-LICENSE.md",
              "CONTRIBUTING.md", "pull_request_template.md"}

COMPILED = [(re.compile(a), b) for a, b in RULES]
COMPILED_CASE = [(re.compile(a), b) for a, b in CASE]

# Dieselbe Tabelle, case-insensitiv - fuer den zweiten Durchgang.
COMPILED_I = [(re.compile(a, re.IGNORECASE), b) for a, b in RULES]
COMPILED_SOURCE_I = [(re.compile(a, re.IGNORECASE), b) for a, b in SOURCE_RULES]

_PLAIN_WORD = re.compile(r'[A-Za-z][A-Za-z0-9 _-]*\Z')


def transfer_case(found, replacement):
    """Give the replacement the spelling of the text it replaces.

    ``Foo`` -> ``Bar``, ``foo`` -> ``bar``, ``FOO`` -> ``BAR``. Only plain words
    are re-spelled; a replacement that carries a path, a shell variable or a
    placeholder (``$HOME``, ``<peer-ip>``) keeps its own spelling, because
    changing the case there would break the thing it names. Mixed spellings that
    are neither lower, upper nor capitalised are left to the table as well -
    there is no single right answer for them and guessing one would invent.
    """
    if not _PLAIN_WORD.match(replacement):
        return replacement
    letters = [c for c in found if c.isalpha()]
    if not letters:
        return replacement
    if all(c.isupper() for c in letters) and len(letters) > 1:
        return replacement.upper()
    if all(c.islower() for c in letters):
        return replacement.lower()
    if letters[0].isupper() and all(c.islower() for c in letters[1:]):
        # Only single words: a replacement of several words is prose, and
        # "Der nutzer" would be worse German than leaving the table's spelling.
        if ' ' in replacement:
            return replacement
        return replacement[0].upper() + replacement[1:].lower()
    return replacement


def apply_rules(text, compiled, compiled_insensitive):
    """Apply the table as written, then once more over the other spellings.

    The order is what makes this safe: the exact pass runs to completion first,
    so every spelling an entry of the table owns is already gone when the
    insensitive pass starts. It can only reach what no entry claimed - which is
    exactly what the abort scan used to find and this tool used to leave behind.
    """
    for rx, rep in compiled:
        text = rx.sub(rep, text)
    for rx, rep in compiled_insensitive:
        if '\\' in rep:
            # Backreferences: the group carries the surrounding text through
            # unchanged, so the spelling is already right and must not be touched.
            text = rx.sub(rep, text)
        else:
            text = rx.sub(lambda m, rep=rep: transfer_case(m.group(0), rep), text)
    return text


def main(root):
    changed = 0
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if fn in SKIP_FILES or fn.endswith(SKIP_SUFFIX):
                continue
            path = os.path.join(dirpath, fn)
            try:
                text = open(path, encoding='utf-8').read()
            except (UnicodeDecodeError, OSError):
                continue
            original = text
            if SOURCE_SUBPATH in path:
                text = apply_rules(text, COMPILED_SOURCE, COMPILED_SOURCE_I)
            else:
                text = apply_rules(text, COMPILED, COMPILED_I)
                for rx, rep in COMPILED_CASE:
                    text = rx.sub(rep, text)
            if text != original:
                open(path, 'w', encoding='utf-8').write(text)
                changed += 1
    print('   %d Dateien übersetzt' % changed)
    return 0


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit('usage: depersonalize.py <repo-root>')
    sys.exit(main(sys.argv[1]))
