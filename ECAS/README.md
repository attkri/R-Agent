# ECAS

## Überblick

ECAS (Event Controlled Agent System) ist ein Windows-only WPF-Tool, das OpenCode-Agents ereignisgesteuert startet.
Die App läuft als Tray-Anwendung, zeigt einen Chatbereich und zwei operative Grids (Chronik + akute Statusmeldungen).
OpenCode wird lokal per CLI aufgerufen (`opencode run --format json`).
Antworten werden als genau ein JSON-Objekt im festen Schema verarbeitet.

## Voraussetzungen

- Windows 11
- .NET SDK 10.x
- OpenCode CLI im PATH (`opencode`)

## Start

```powershell
dotnet build "ECAS/ECAS.csproj"
dotnet run --project "ECAS/ECAS.csproj"
```

## Konfiguration

Die Laufzeitkonfiguration liegt in `ECAS/app.config.json` und wird beim Build nach `bin/...` kopiert.

Wichtige Punkte:

- `MaxParallelRuns`: maximale parallele Agent-Runs (V1: 4)
- `Chat`: Prompt/Timeout für manuelle Chat-Eingaben
- `Triggers`: trigger-spezifische Prompts, Intervalle und Timeouts
- `Autostart`: HKCU Run-Key (`mode: hkcu_run`)

## Antwortschema

OpenCode muss genau ein JSON-Objekt liefern:

```json
{
  "id": 1,
  "action": "notify",
  "title": "Titel",
  "message": "Nachricht",
  "reference": "quelle/ref",
  "timestamp": "2026-02-18T12:34:56+01:00"
}
```

Erlaubte `action`-Werte (OpenCode -> ECAS):

- `notify`
- `chat_reply`
- `status_changed`

## Logs und Laufzeitdaten

- Lauf-Logs: `ECAS/logs/` (Aufbewahrung: letzte 10 Runs)
- Chat-Logs: `ECAS/chat/` (tägliche Datei)
- Runtime-State: nur im RAM
