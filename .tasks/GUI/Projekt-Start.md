# R-Agent

## Projekt-Eigenschaften

- Technologie: .NET 10, C#, WPF, MVVM.
- Betriebsart im MVP: Desktop-App, kein Windows-Dienst.
- Einstellungen im MVP: keine Einstellungs-GUI, Konfiguration ausschließlich über `config.json` im App-Ordner.
- `rclone.exe` wird über `GlobalSettings.RclonePath` aus `config.json` geladen.
- Es gibt zwei Modi: `Sync` und `Mount`.

## Konfiguration (`config.json`)

- Speicherort: App-Ordner.
- Das Schema orientiert sich an der vorhandenen Datei und bleibt der Single Source of Truth.
- Formale Validierung erfolgt über `config.schema.json` im Projekt-Root.

### `GlobalSettings`

- `RclonePath` (string, Pflicht): absoluter Pfad zur `rclone.exe`.

### `SyncTasks[]`

- `Id` (string, Pflicht, GUID, pro Task eindeutig).
- `Name` (string, Pflicht).
- `Source` (string, Pflicht).
- `Target` (string, Pflicht).
- `Transfers` (int, optional, Default `8`).
- `Checkers` (int, optional, Default `32`).
- `DriveChunkSize` (string, optional, Default `64M`).
- `SkipLinks` (bool, optional, Default `true`).
- `ExcludeFiles` (string[], optional).

### `MountTasks[]`

- `Id` (string, Pflicht, GUID, pro Task eindeutig).
- `Name` (string, Pflicht).
- `Source` (string, Pflicht, z. B. `gdrive:`).
- `MountPoint` (string, Pflicht, z. B. `G:`).
- `VfsCacheMode` (string, optional, Default `full`).
- `Verbose` (bool, optional, entspricht rclone-Parameter `-v`).
- `Links` (bool, optional, entspricht rclone-Parameter `--links`).

### Validierungsregeln

- Fehlende Pflichtfelder verhindern den Start eines Tasks.
- `Id` muss eindeutig sein; doppelte IDs sind ein Konfigurationsfehler.
- Pfade und Remotes werden vor Task-Start validiert.
- JSON-Schema validiert Struktur, Typen und Wertebereiche; Eindeutigkeit der IDs wird zusätzlich in der App geprüft.

### Mindestversionen (MVP)

- rclone: `>= 1.73.0`
- WinFsp (nur für Mount): `>= 2.1.25156`

### Lokal ermittelte Versionen (Stand 2026-02-14)

- rclone: `v1.73.0`
- WinFsp: `2.1.25156`

## Modus `Sync`

- Synchronisiert Dateien zwischen Quell- und Zielpfad.
- Mehrere Sync-Tasks können parallel im Hintergrund laufen (maximal 6 gleichzeitig).
- Jeder Task ist einzeln startbar und stoppbar.
- Konfigurierbare Parameter: `transfers`, `checkers`, `drive-chunk-size`, `skip-links`.
- Ausgabe/Progress in die GUI:
  - Primär: `--progress`.
  - Fallback: `--stats-one-line --stats 1s`.
  - Optional strukturiert: `--use-json-log`.
- Single-Meldungen werden im Bereich `Systemnachrichten` (DataGrid) angezeigt; laufender Progress im Bereich `Live Log`.
- Erfolgskriterium (MVP): Task gilt als erfolgreich, wenn `ExitCode == 0` und keine Ausgabe auf `stderr` erkannt wurde.

## Modus `Mount`

- Bindet Cloud-Speicher als Laufwerke ein.
- Mehrere Mounts können gleichzeitig aktiv sein.
- Mounts sind in der GUI einzeln aktivierbar/deaktivierbar.
- Konfigurierbare Parameter: `vfs-cache-mode`, `v`, `links`.
- Voraussetzung unter Windows: Für `rclone mount` muss WinFsp installiert sein.

## Lifecycle-Regeln (festgelegt)

- Beim Start der App wird nur Konfiguration geladen und validiert, keine Auto-Starts.
- Ein Task startet nur nach explizitem Benutzer-Start in der GUI.
- `Stop` beendet genau den gewählten Task.
- Bei `Stop` wird zuerst ein modusspezifisches, sauberes Stop-Signal gesendet (Sync/Mount unterschiedlich).
- Wenn der Task nach 20 Sekunden noch läuft, wird hart abgebrochen.
- Beim Schließen der App werden laufende Tasks sauber gestoppt.
- Nach App-Neustart bleibt nur die Konfiguration bestehen, nicht der Laufzeitstatus.

## GUI-Anforderungen (konkretisiert)

- Task-Status pro Eintrag: `Bereit`, `Laufend`, `Stop angefordert`, `Gestoppt`, `Fehler`, `Erfolgreich`.
- Task-Liste zeigt mindestens: `Name`, `Modus`, `Quelle`, `Ziel/MountPoint`, `Status`.
- Fortschritt wird visuell am Task als Balken plus Prozent angezeigt.
- `Live Log` zeigt Meldungen des aktuell ausgewählten Tasks.
- `Systemnachrichten` ist ein DataGrid mit Spalten: `Time`, `Message`, `Severity`, `Task`.
- Sortierung über Spaltenkopf (auf/absteigend) ist im MVP enthalten.
- `Open Settings` ist sichtbar und öffnet die letzte Log-Datei mit der Windows-Standard-App für `.log`.
- Keine Filterung im MVP; Filter bleibt als späteres Todo.

## Tests

- Testframework: xUnit.
- Unit-Tests für Konfigurations-Parsing und -Validierung.
- Unit-Tests für Schema-Validierung gegen `config.schema.json`.
- Unit-Tests für Kommandoaufbau (`Sync`/`Mount`) aus Task-Konfiguration.
- Unit-Tests für Task-Status-Übergänge.
- Integrationsnahe Tests für Start/Stop-Verhalten der Prozesssteuerung.

## Fehlerklassifizierung (festgelegt)

- Severity-Stufen: `Info`, `Warning`, `Error`, `Fatal`.
- `ConfigValidationError` (`Fatal`): `config.json` verletzt Schema oder Laufzeitvalidierung.
- `ProcessStartError` (`Fatal`): `rclone.exe` nicht gefunden oder Prozessstart schlägt fehl.
- `TaskExitCodeError` (`Error`): Prozessende mit `ExitCode != 0`.
- `TaskStderrError` (`Warning`): relevante Ausgabe auf `stderr` trotz `ExitCode == 0`.
- `TaskStopTimeout` (`Error`): graceful Stop überschreitet 20 Sekunden, harter Abbruch nötig.
- `TaskCanceledByUser` (`Info`): Benutzer hat Task explizit gestoppt.

### ExitCode-Mapping (rclone)

- `0` -> `Info` -> Erfolg.
- `1` -> `Error` -> sonstiger nicht kategorisierter Fehler.
- `2` -> `Error` -> Syntax- oder Usage-Fehler.
- `3` -> `Error` -> Verzeichnis nicht gefunden.
- `4` -> `Error` -> Datei nicht gefunden.
- `5` -> `Warning` -> temporärer Fehler (Retry-Kandidat).
- `6` -> `Warning` -> weniger schwerer Fehler (NoRetry).
- `7` -> `Fatal` -> fataler Fehler.
- `8` -> `Error` -> Transfer-Limit überschritten (`--max-transfer`).
- `9` -> `Info` -> Erfolg ohne Transfer (`--error-on-no-transfer`).
- `10` -> `Error` -> Dauer-Limit überschritten (`--max-duration`).

## Retry-Strategie (festgelegt)

- Retry wird nur bei Timeout-Fehlern ausgelöst.
- Es gibt genau einen Retry-Versuch.
- Timeout für den Retry-Versuch: 30 Sekunden.
- Scheitert auch der Retry wegen Timeout, wird der Task auf `Fehler` gesetzt und gestoppt.

## Logging (festgelegt)

- Pro App-Start wird genau eine Log-Datei erstellt.
- Dateiname: `logs/r-agent-YYYYMMDD-HHmmss.log`.
- Die Datei enthält alle Meldungen aller Tasks des aktuellen App-Starts.
- Pro Zeile mindestens: `Zeitpunkt`, `TaskId`, `Modus`, `Quelle`, `Severity`, `Meldung`.
- Log-Dateien werden in UTF-8 geschrieben.
- Retention: Es bleiben die Log-Dateien der letzten 10 App-Starts erhalten, ältere Dateien werden gelöscht.

## GUI-Design-Festlegung (Prozess)

- Schritt 1: ASCII-Skizze im Abschnitt `## GUI > ### Skizze` pflegen.
- Schritt 2: Technischen Screen-Contract im Abschnitt `## GUI` pflegen (`Zweck`, `Daten`, `Aktionen`, `Status`).
- Schritt 3: WPF-Umsetzung gegen die Abschnitte in `Projekt-Start.md` prüfen.
- Schritt 4: Freeze-Stand als `GUI v1` im Abschnitt `## GUI > ### Freeze-Stand` markieren.
- Ein Änderungsantrag enthält immer: Ziel, betroffener Screen, neue/entfernte Felder, neue Aktionen, Auswirkung auf ViewModel und Tests.
- Die GUI-Dokumentation ist zentral in `Projekt-Start.md`.

## Backlog (später)

- Filterung für Task-Liste und Systemnachrichten.

## GUI

### Skizze

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ (SYMBOL) R-Agent                                                [MIN][MAX][X]│
├──────────────────────────────────────────────────────────────────────────────┤
│                                                              [Open Settings] │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│ Task (1)                                                                     │
│ ========                                                                     │
│                                                                              │
│ | Task Name          | Typ   | Status       | Fortschritt      | Aktion    | │
│ | ------------------ | ----- | ------------ | ---------------- | --------- | │
│ | Home => pCloud     | Sync  | (G) Läuft    | [12345678  ] 82% | [Stop   ] | │
│ | Projekte => GDrive | Sync  | (R) Gestoppt | [          ] 0%  | [Start  ] | │
│ | GDrive Laufwerk Z: | Mount | (G) Aktiv    | -                | [Unmount] | │
│                                                                              │
│ Live Log (2)                                                                 │
│ ============                                                                 │
│ Transferred: 1.5G / 5G, 30%, 5M/s, ETA 10m                                   │
│ Checks: 32 / 32, 100%                                                        │
│                                                                              │
│ Systemnachrichten (3)                                                        │
│ =====================                                                        │
│                                                                              │
│ |       Time | Message            | Severity | Task           |              │
│ | ---------: | :----------------- | :------: | :------------- |              │
│ | 2026-02-14 | Sync abgeschlossen |   INFO   | Home => pCloud |              │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│ STATUS-BAR                                                                   │
└──────────────────────────────────────────────────────────────────────────────┘
```

#### Legende

- (SYMBOLE) => 🤖
- (R), (G) => Emojis: 🟢 = Grün, 🔴 = Rot
- [1234567890] => Fortschrittsbalken mit 10 Blöcken, gefüllt entsprechend Prozent
- [BTN] => Aktionstaste, abhängig von Status, ⏹️ Stop, ▶️ Start, ⏏️ Unmount, 🔄 Sync Tasks, 📁 Mounts, ⚙️ Settings
- (1) Optische Grid-Struktur: Die Task-Übersicht ist keine echte Tabelle, sondern eine optisch strukturierte Liste, um Flexibilität bei der Darstellung von Status und Aktionen zu ermöglichen.
- (2) Je Auswahl: Die Live-Log-Anzeige zeigt die aktuell ausgewählten Tasks an. Bei Auswahl eines Sync-Tasks werden dessen Fortschrittsmeldungen angezeigt, bei Auswahl eines Mount-Tasks werden relevante Systemmeldungen oder Fehler angezeigt.
- (3) DataGrid: Die Systemnachrichten sind ein echtes DataGrid mit Spalten für Zeit, Nachricht, Schweregrad und zugehörigem Task. Es zeigt alle Meldungen des aktuellen App-Starts an. Auf die Spaltenüberschriften kann geklickt werden, um auf- bzw. absteigend zu sortieren.

### Zweck

- Dieser Abschnitt konsolidiert ASCII-Skizze und technischen GUI-Contract.
- Die Skizze ist die visuelle Quelle, die Unterabschnitte definieren den technischen Contract.

### Fensterstruktur

- Kopfzeile: App-Titel mit Window-Buttons.
- Top-Action: `Open Settings` bleibt sichtbar und öffnet die letzte Log-Datei über die Windows-Standard-App für `.log`.
- Bereich 1: `Task`-Übersicht (optisch strukturierte Liste, kein klassisches DataGrid).
- Bereich 2: `Live Log` für den aktuell ausgewählten Task.
- Bereich 3: `Systemnachrichten` als echtes DataGrid.
- Fußzeile: `Status-Bar`.

### Bereich 1: Task (1)

- Zweck: Start/Stop/Unmount der Tasks und schnelle Statusübersicht.
- Daten (Input): `TaskId`, `TaskName`, `Typ`, `Status`, `ProgressBar10`, `ProgressPercent`, `ActionLabel`.
- Daten (Output): `StartTask(TaskId)`, `StopTask(TaskId)`, `UnmountTask(TaskId)`, `SelectTask(TaskId)`.
- Statusdarstellung:
  - fachlich: `Bereit`, `Laufend`, `Aktiv`, `Stop angefordert`, `Gestoppt`, `Fehler`, `Erfolgreich`.
  - visuell: gemäß Legende in diesem Abschnitt (Symbol/Emoji-Farbe).
- Regeln:
  - Maximal 6 parallele Sync-Tasks.
  - Aktion ist statusabhängig (`Start`, `Stop`, `Unmount`).
  - Fortschritt wird als 10er-Balken plus Prozent dargestellt.
- Tests:
  - Action-Binding je Status.
  - Fortschrittsdarstellung (Balken + Prozent) ist konsistent.
  - Parallelitätsgrenze wird erzwungen.

### Bereich 2: Live Log (2)

- Zweck: Live-Ausgabe je ausgewähltem Task anzeigen.
- Daten (Input): `SelectedTaskId`, `SelectedTaskName`, `LiveLines[]`.
- Daten (Output): keine direkte Schreibaktion.
- Regeln:
  - Es werden nur Meldungen des selektierten Tasks angezeigt.
  - Bei Task-Wechsel wird die Anzeige sofort umgeschaltet.
  - Bei keinem selektierten Task wird ein neutraler Hinweis angezeigt.
- Tests:
  - Keine Vermischung zwischen Tasks.
  - UI bleibt responsiv bei hoher Meldungsrate.

### Bereich 3: Systemnachrichten (3)

- Zweck: Alle Meldungen des aktuellen App-Starts in einer zentralen Tabelle.
- Typ: echtes DataGrid.
- Pflichtspalten: `Time`, `Message`, `Severity`, `Task`.
- Datenquelle intern: `Zeitpunkt`, `Meldung`, `Severity`, `TaskName`.
- Aktionen:
  - Sortieren über Spaltenkopf auf/absteigend.
- Regeln:
  - Keine Filterung im MVP.
  - Severity visuell unterscheidbar (`Info`, `Warning`, `Error`, `Fatal`).
- Tests:
  - Sortierung ist deterministisch.
  - Neue Meldungen werden appendend und thread-sicher angezeigt.

### Nicht Teil von GUI v1

- Keine Filterfunktion in Task-Liste oder Systemnachrichten.
- Keine separate Einstellungs-GUI.

### Freeze-Stand

- Dieser Stand ist `GUI v1`.
- Änderungen erfolgen nur über den Änderungsantrag-Prozess in `Projekt-Start.md`.

## Referenzen

- rclone Dokumentation (Einstieg): https://rclone.org/docs/
- rclone Exit Codes: https://rclone.org/docs/#list-of-exit-codes
- rclone Global Flags (`--transfers`, `--checkers`, `--progress`, `--stats-one-line`, `--stats`, `--use-json-log`, `-v`, `--links`): https://rclone.org/flags/
- rclone `sync`: https://rclone.org/commands/rclone_sync/
- rclone `mount` (inkl. Windows-Hinweise): https://rclone.org/commands/rclone_mount/
- rclone Google Drive Backend (`--drive-chunk-size`): https://rclone.org/drive/
- WinFsp Dokumentation: https://winfsp.dev/doc/
- WinFsp Download/Installer: https://winfsp.dev/rel/
