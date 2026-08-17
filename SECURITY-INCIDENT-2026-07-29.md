# Personendaten in einem oeffentlichen Repo (29.07.2026)

Dieser Bericht nennt bewusst **keine** der betroffenen Werte. Wer einen Vorfall dokumentiert,
indem er die geleakten Daten noch einmal hinschreibt, hat ihn wiederholt statt aufgearbeitet.
Genau das ist beim ersten Entwurf dieses Textes passiert und musste korrigiert werden.

## Was passiert ist

Dieses Repo wurde am 29.07.2026 oeffentlich gemacht, mit der Zusicherung, es enthalte keine
Personendaten - geprueft an einem frischen Klon. Ein unabhaengiger Scan aus einer anderen
Sitzung fand drei Stunden spaeter mehrere Klartext-Vorkommen in zwei Dateien
(`tools/depersonalize.py`, `sync-from-source.sh`):

- den Nachnamen des Betreibers, mehrfach
- einen Kommentar mit seinem Vornamen
- sein GitHub-Handle
- den Vornamen einer **zweiten Person**, deren Daten nicht die des Betreibers sind
- eine private Adresse aus seinem Rechnerverbund

Aus zwei getrennten Zeilen liess sich zudem seine vollstaendige private Mailadresse in einem
Schritt zusammensetzen.

## Ursache

Die Ersetzungstabelle stand IM Repo. Eine Tabelle, die echte Namen auf neutrale abbildet, **ist
selbst Personendaten**. Weil sie inline stand, musste sich das Werkzeug von der eigenen
Pruefung ausnehmen:

    --exclude=depersonalize.py --exclude=sync-from-source.sh

Damit war das Abbruch-Tor blind fuer genau die zwei Dateien, die als einzige lecken konnten.

Der Autor hatte die Gefahr erkannt und die gesuchten Zeichenketten im Quelltext aus Fragmenten
zusammengesetzt, damit sie nicht als ganze Woerter dastehen - an mehreren Stellen aber nicht
angewendet. Diese Technik verhindert ohnehin nur den naiven Volltextgriff; sie ist keine
Absicherung, sondern eine Bequemlichkeit.

## Behoben

- Die Tabelle liegt **ausserhalb** des Repos: `~/.config/agent-workbench/depersonalize.rules`,
  ueberschreibbar per `WB_DEPERSONALIZE_RULES`. Fehlt sie, ist das Werkzeug ein No-op - es raet
  nie.
- `tools/depersonalize.rules.example` zeigt das Format mit neutralen Platzhaltern. Nebeneffekt:
  das Werkzeug wird dadurch **ueberhaupt erst fuer Fremde brauchbar**. Vorher waren die Muster
  fest auf eine Person verdrahtet und fuer jeden anderen wertlos.
- `SKIP_FILES` ist leer, die `--exclude`-Ausnahmen sind entfernt. Das Tor prueft jede Datei.
- `sync-from-source.sh` bricht ab, wenn keine Tabelle vorhanden ist, statt stillschweigend
  ungeprueft durchzulaufen.
- Die History wurde neu geschrieben. Weil ein Force-Push die alten Objekte auf der Plattform
  nicht entfernt - sie bleiben ueber ihre Pruefsumme abrufbar -, wurde das Repo geloescht und
  neu angelegt. Danach gegengeprueft: die alten Pruefsummen sind nicht mehr aufloesbar, ein
  frischer Klon enthaelt keinen der Werte mehr.

## Lehren

1. **Ein Werkzeug, das Daten filtert, darf sich nicht selbst von seiner Pruefung ausnehmen.**
   Scheint eine Ausnahme noetig, ist die Konstruktion falsch, nicht die Pruefung.
2. **Konfiguration, die Personendaten enthaelt, ist Konfiguration und kein Code.** Sie gehoert
   neben die Zugangsdaten, nicht neben das Programm.
3. **Ein Force-Push loescht nichts.** Er haengt einen Zeiger um. Sollen Daten wirklich weg,
   muss das Repo entfernt oder die Plattform um Aufraeumen gebeten werden.
4. **Eine fremde Sauberkeitsmeldung ist kein Nachweis.** Der Fund entstand, weil eine zweite
   Instanz die Zusicherung nicht geglaubt, sondern selbst geklont und gesucht hat.
5. **Auch der Vorfallsbericht faellt unter Regel 1.** Der erste Entwurf dieses Textes zitierte
   die betroffenen Werte als Beleg - und haette sie damit erneut veroeffentlicht.

## Nachtrag 2026-08-17: derselbe Vorfall, achtzehn Tage lang unentdeckt

Dieser Bericht endete bis heute mit der Feststellung, das Tor sei repariert. Es war es nicht.

Beim Aufbau eines Nachfolge-Repos wurde das Tor gemessen statt gelesen, und dabei fiel auf, dass
es ueber die Haelfte seiner Suchbegriffe blind war. Die awk-Zeile, die Regex-Sonderzeichen
entschaerft, entfernte nur den Backslash und liess den Buchstaben stehen: aus einer Wortgrenze
`\b` wurde ein literales `b`, das am Suchbegriff klebte. 31 der Tabellenzeilen benutzen
Wortgrenzen; von 39 eindeutigen Begriffen konnten damit 21 in keinem Text mehr vorkommen.
Gemessen an einem unuebersetzten Baum mit nachweislich betroffenen Dateien fand das Tor 189 statt
298 -- es haette 109 Dateien durchgelassen und dabei "nichts gefunden" gemeldet.

Ein zweiter, unabhaengiger Fehler lag daneben: der Abbruch-Scan suchte case-insensitiv, der
Uebersetzer ersetzte case-sensitiv. Der Scan konnte also finden, was der Uebersetzer nicht
bereinigen konnte -- kein Leck, aber ein Abbruch ohne sichtbaren Grund.

Die Folge war messbar. Der reparierte Scan fand in diesem Repository, so wie es seit dem
30.07.2026 veroeffentlicht war, **sieben verfolgte Dateien mit sechzehn betroffenen Zeilen** --
durchgehend derselbe siebenzeichige Bezeichner in einer Schreibweise, die kein Tabelleneintrag
case-sensitiv beansprucht hatte. Vier der sieben waren Testdateien. Namen darueber hinaus,
Adressen, Schluessel oder Zugangsdaten waren nicht betroffen; ein Formsuchlauf nach Heimatpfaden
mit fremdem Benutzernamen, E-Mail-Adressen und Schluesselpraefixen fand nichts.

Behoben: beide Fehler im Tor, die fehlenden Tabelleneintraege ergaenzt, die sieben Dateien
uebersetzt. Das Repository wurde erneut geloescht und neu angelegt, weil ein Commit auch nach
einer Korrektur ueber seine Pruefsumme abrufbar bleibt -- dieselbe Lehre 3 wie oben, zum zweiten
Mal angewandt.

### Was dieser Nachtrag zu den Lehren hinzufuegt

6. **Ein Tor, das nicht trifft, ist schlimmer als keines**, weil es Sicherheit behauptet. Nach
   Lehre 1 pruefte niemand mehr, ob die Pruefung selbst funktioniert -- sie war ja "repariert".
7. **Eine Sicherheitspruefung wird gemessen, nicht gelesen.** Der Beleg ist eine Gegenprobe
   gegen einen Baum, in dem nachweislich etwas zu finden ist. Ohne sie ist "nichts gefunden"
   nicht von "nicht gesucht" zu unterscheiden.
8. **Wer eine Pruefung baut, baut eine zweite, die die erste prueft.** Beide Fehler dieses
   Nachtrags waren in fuenf Minuten messbar -- es hat nur achtzehn Tage niemand gemessen.
