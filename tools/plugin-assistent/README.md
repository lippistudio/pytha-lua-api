# Plugin-Assistent

Ein PYTHA-Plugin, das PYTHA-Plugins erstellt, prüft und übersetzt. Die Oberfläche ist deutsch.

- **Neues Plugin erstellen:** `config.xml` mit allen 8 Extension-Typen aus der [Wiki-Doku](https://github.com/pytha-3d-cad/pytha-lua-api/wiki/config.xml), dazu auf Wunsch ein Lua-Gerüst (`main.lua`) und eine Hilfeseite (`help.html`). Das Plugin wird direkt in den `plugins`-Ordner von PYTHA geschrieben.
- **Bestehendes Plugin öffnen und prüfen:** liest `config.xml` und alle Lua-Dateien, meldet Fehler und Warnungen und schreibt die korrigierte `config.xml` zurück. Die alte Datei bleibt als `config.xml.bak` erhalten.
- **Übersetzung bearbeiten:** übersetzt die von PYTHA erzeugte `localization.base.xlf` in eine Zielsprache (`localization.<sprache>.xlf`).

## Voraussetzungen

**PYTHA 26 oder neuer.** Der Assistent braucht die Dateifunktionen der Lua-API (`pyui.select_folder`, `pyio.write_lines`, `pyio.parse_xml`, `pyio.list_folder`), die es erst ab Version 26 gibt. Erzeugte Plugins dürfen PYTHA 25 als Mindestversion haben.

## Installation

Den Ordner [`Plugin-Assistent`](Plugin-Assistent) in den Ordner `plugins` der PYTHA-Einstellungen kopieren, z. B. `C:\Users\NAME\AppData\Roaming\PYTHA26.0\plugins`. Danach erscheint im Menü der Generatoren ein Button „Plugin-Assistent“.

## Bedienung

### Neues Plugin erstellen

1. Name, Version, Mindestversion von PYTHA, Beschreibung und Lizenz eintragen. Ordnername und GUID schlägt der Assistent vor.
2. Unter **Extensions** die Funktionen festlegen: Typ wählen, **Hinzufügen …**. Der Dialog zeigt zu jedem Feld eine Erklärung und die Aufrufsignatur der Einstiegsfunktion.
3. Unter **Zusätzliche Dateien** die Lua-Vorlage wählen:
   - **Einfaches Gerüst:** je Extension eine leere Funktion mit der richtigen Signatur.
   - **Generator mit Dialog und Bearbeiten:** ein vollständiger Generator nach dem Muster von `samples/Block`, mit Dialog, History und Bearbeiten per Rechtsklick. Der Assistent legt dazu automatisch eine Bearbeiten-Extension an, deren ID der Code bei `pytha.set_element_history` verwendet.
4. **Prüfung** zeigt laufend Fehler, Warnungen und Hinweise. Solange Fehler bestehen, ist **Speichern …** gesperrt.
5. **Vorschau …** zeigt alle Dateien vor dem Speichern.
6. **Speichern …** fragt nach dem Ordner `plugins` von PYTHA und legt das Plugin dort als Unterordner an. PYTHA fragt nach der Erlaubnis zum Schreiben.

### Bestehendes Plugin öffnen und prüfen

Den Ordner eines Plugins wählen. Der Assistent meldet unter anderem:

| Prüfung | Beispiel aus den Samples |
|---|---|
| Attribut-IDs mit unzulässigen Zeichen | `Multiple Edge Banding Attributes`: IDs in Anführungszeichen |
| History-ID im Code ohne passende Bearbeiten-Extension | `Waveboards`: `wave_shape_history` |
| fehlende Hilfedatei | 15 Samples verweisen auf eine nicht vorhandene `help.html` |
| Kommentare in `config.xml`, die beim Speichern verloren gehen | `Kitchen Wizard` |
| Einstiegsfunktion in keiner Lua-Datei definiert oder nur `local` | – |
| ungültige GUID, Version, Dateifilter, Themen von Nachrichten-Services, doppelte IDs, fehlende Pflichtfelder, Extension-Typen ab PYTHA 26 bei älterer Mindestversion, Platzhaltertexte | – |

Beim Speichern:

- `config.xml.bak` sichert die bisherige Datei.
- Vorhandene Lua-Dateien werden nie verändert. Fehlende Einstiegsfunktionen legt der Assistent auf Wunsch in einer eigenen Datei `plugin_assistent_stubs.lua` an.
- Elemente und Felder, die der Assistent nicht kennt, werden unverändert übernommen.

### Übersetzung bearbeiten

1. Das Plugin einmal in PYTHA ausführen. PYTHA erzeugt dabei `localization.base.xlf` mit allen `pyloc`-Texten.
2. Im Assistenten die Basisdatei wählen, dann Quell- und Zielsprache.
3. Texte übersetzen. `[x]` heißt übersetzt, `[ ]` offen, `[?]` bedeutet, dass sich der Quelltext seit der Übersetzung geändert hat.
4. **Speichern** schreibt `localization.<sprache>.xlf` in denselben Ordner. Übersetzungen aus einer vorhandenen Datei werden übernommen.

## Aufbau

Alle Dateien liegen direkt im Plugin-Ordner, weil PYTHA nur dort `*.lua` lädt, in beliebiger Reihenfolge. Jede Datei definiert genau eine globale Tabelle und greift auf andere Module nur innerhalb von Funktionen zu.

| Datei | Inhalt |
|---|---|
| `pa_schema.lua` | Beschreibung aller Extension-Typen und Felder aus dem Wiki; einzige Quelle für Oberfläche, Prüfung und Vorlagen |
| `pa_model.lua` | Projektmodell, Vorgaben, GUID, Namen, Liste der zu schreibenden Dateien |
| `pa_xml.lua` | XML-Hilfen und Schreiben der `config.xml` |
| `pa_config_reader.lua` | `config.xml` (Baum aus `pyio.parse_xml`) → Projektmodell |
| `pa_lua_scan.lua` | Funktionen, History-IDs und `pyloc`-Texte in den Lua-Dateien finden |
| `pa_validate.lua` | Prüfregeln |
| `pa_templates.lua` | Lua-Gerüste je Extension-Typ und Generator-Vorlage |
| `pa_help.lua` | `help.html` |
| `pa_xliff.lua` | XLIFF 2.0 lesen, zusammenführen, schreiben |
| `pa_files.lua` | Öffnen und Speichern über Path-Handles |
| `pa_ui_*.lua`, `pa_main.lua` | Dialoge und Einstiegsfunktion `main` |

## Tests

Die Tests laufen ohne PYTHA mit Standard-Lua 5.3. Sie ersetzen `pytha`, `pyui`, `pyio` und `pyux` durch Nachbildungen mit einem Dateisystem im Speicher und spielen die Dialoge durch.

```sh
tools/plugin-assistent/tests/run_tests.sh
```

Das Skript nutzt `lua5.3` bzw. `lua` (Version 5.3) oder, falls keins installiert ist, Python mit dem Paket `lupa` (`pip install lupa`).

Geprüft wird unter anderem:

- Sandbox-Regeln von PYTHA: kein API-Zugriff beim Laden der Dateien, keine gesperrten Funktionen, beliebige Ladereihenfolge.
- Round Trip aller 18 Sample-`config.xml`.
- Die oben genannten Befunde in den Samples als Testorakel, ohne Fehlalarme.
- Die erzeugten Lua-Vorlagen laden und laufen mit den Nachbildungen.
- XLIFF-Round-Trip mit `samples/Block`.
- Komplette Abläufe durch die Dialoge.

## Test in PYTHA (Checkliste)

Die Nachbildungen folgen der Wiki-Doku, ersetzen aber keinen Test in PYTHA selbst. Bitte einmal durchgehen:

- [ ] Assistent installieren und über das Generatoren-Menü starten.
- [ ] Neues Plugin mit der Vorlage „Generator mit Dialog und Bearbeiten“ und Hilfeseite speichern. Legt PYTHA den Unterordner selbst an, oder erscheint der Hinweis, ihn im Ordnerdialog anzulegen?
- [ ] Das neue Plugin ausführen, Maße ändern, speichern; danach per Rechtsklick → Bearbeiten erneut öffnen.
- [ ] `samples/Waveboards` öffnen: Die Warnung zu `wave_shape_history` erscheint. Bearbeiten-Extension mit ID `wave_shape_history` und Einstiegsfunktion `edit_block` hinzufügen und speichern; `config.xml.bak` existiert.
- [ ] Übersetzungs-Editor mit `samples/Block/localization.base.xlf`: eine Sprache übersetzen, speichern, PYTHA auf diese Sprache umstellen und die Texte prüfen.
- [ ] Mit PYTHA 27: Listen und Textbereiche sind größer (`set_control_min_height`).

## Grenzen

- `pyio.parse_xml` liefert keine Kommentare. Kommentare in einer geöffneten `config.xml` gehen beim Speichern verloren; sie bleiben in `config.xml.bak`.
- Die Code-Analyse erkennt nur die üblichen Schreibweisen (`function name(`, `pytha.set_element_history(element, data, "id")`). Ihre Ergebnisse sind deshalb überwiegend Warnungen; nur eine Einstiegsfunktion, die in keiner Lua-Datei vorkommt, gilt als Fehler, solange kein Gerüst dafür angelegt wird.
- Die IDs in `.xlf`-Dateien berechnet PYTHA. Der Übersetzungs-Editor arbeitet deshalb immer mit einer von PYTHA erzeugten Basisdatei.
