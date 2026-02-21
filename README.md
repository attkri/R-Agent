# R-Agent

## Überblick

R-Agent enthält aktuell ausschließlich autarke `rclone`-Skripte für Mount- und Sync-Jobs unter Windows 11.

Die Jobsteuerung (Intervall, Aktivierung, Ausführung) erfolgt bewusst **nicht** in diesem Repository, sondern über das externe Projekt `AgentCommandWorker`.

Die zentrale sensible Konfiguration bleibt in `C:\Users\attila\.Secrets\RClone.Secrets.json`.

Cloud-Ablage ist gemäß Projektentscheidung derzeit unverschlüsselt, um Webzugriff und Zugriff von anderen Systemen ohne zusätzliche `rclone`-Konfiguration zu ermöglichen.

## Voraussetzungen

- Windows 11

- PowerShell 7.x

- rclone (z. B. `C:\Program Files\rclone\rclone.exe`)

- WinFsp (nur für Mount-Skripte erforderlich)

- Konfigurierte Remotes in `rclone.conf` (z. B. `gdrive:`, `pcdrive:`)

- Konfigurationsdatei `C:\Users\attila\.Secrets\RClone.Secrets.json`

## Aktueller Ist-Zustand

- Es gibt **nur** jobbezogene Skripte in `./.Scripts`.

- Das frühere `.Tools`-basierte Runner-System wurde entfernt.

- Jedes Skript ist autark und ruft keine anderen Projektskripte auf.

- Statusmeldungen werden als JSONC-Datei im aktuellen Arbeitsverzeichnis geschrieben.

- Der Status-Dateiname ist GUID-basiert: `<JobGuid>.Status.jsonc`.

- Zwischen zwei Statusschreibvorgängen wird ein Mindestabstand (Standard: 2 Sekunden) eingehalten.

## Skripte

- `./.Scripts/Mount-m1-pcdrive-p.ps1`

- `./.Scripts/Mount-m2-gdrive-g.ps1`

- `./.Scripts/Sync-s1-projects-to-google.ps1`

- `./.Scripts/Sync-s2-config-opencode-to-google.ps1`

- `./.Scripts/Sync-s3-local-share-opencode-to-google.ps1`

- `./.Scripts/Sync-s4-attila-home-to-pcloud-bisync.ps1`

- `./.Scripts/Sync-s5-hot-to-google-bisync.ps1`

## Job-Integration (AgentCommandWorker)

- Jobdateien liegen in `C:\Users\attila\Projects\AgentCommandWorker\Jobs`.

- Dateinamen folgen der Job-GUID: `<Job.ID>.Job.jsonc`.

- `Job.Command` setzt das Working Directory direkt über `pwsh.exe -WorkingDirectory ...`.

- `Job.Enabled` ist initial für alle Jobs `false`, außer dem freigegebenen Startjob `m1`.

## Aufgabe und Grenzen dieses Repositories

- **Aufgabe hier:** Pflege und Weiterentwicklung der autarken `rclone`-Skripte in `./.Scripts` inklusive robuster Statusausgabe.

- **Nicht Aufgabe hier:** Orchestrierung, Scheduler-Logik, Jobauswahl, Intervallsteuerung, Queueing und Worker-Lifecycle.

- Diese Orchestrierungsaufgaben liegen vollständig im externen Projekt `AgentCommandWorker`.

## Logging

- Laufzeitlogs der Skripte werden in `./.logs` nach dem Muster `yyyyMMdd_HHmmss_<id>.log` geschrieben.
