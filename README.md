# R-Agent

## Überblick

R-Agent automatisiert `rclone`-Workflows für Windows 11 mit Fokus auf Mounts und Synchronisation.
Die zentrale Konfiguration liegt in `C:\Users\attila\.Secrets\RClone.Secrets.json`.
Mount- und Sync-Jobs werden deklarativ in dieser Datei gepflegt und über PowerShell-Skripte ausgeführt.
Die aktuelle Projektentscheidung ist bewusst unverschlüsselte Cloud-Ablage, damit Webzugriff und Zugriff von anderen Systemen ohne zusätzliche `rclone`-Konfiguration möglich sind.
Logs werden direkt in `.logs/` geschrieben.

## Voraussetzungen

- Windows 11
- PowerShell 7.x
- rclone (empfohlen unter `C:\Program Files\rclone\rclone.exe`)
- WinFsp (nur für Mounts erforderlich)
- Konfigurierte Remotes in `rclone.conf` (aktuell z. B. `gdrive:` und `pcdrive:`)

## Konfiguration

- Datei: `C:\Users\attila\.Secrets\RClone.Secrets.json`
- Mount-Jobs: `facts.automation.mounts`
- Sync-Jobs: `facts.automation.syncs`
- Ausnahmen je Job: `facts.automation.syncs[].excludes`

## Nutzung

- Mounts starten: `pwsh -File ".Tools/Start-RcloneMounts.ps1" -LiveRun`
- Mounts stoppen: `pwsh -File ".Tools/Stop-RcloneMounts.ps1"`
- Alle Syncs als Dry-Run: `pwsh -File ".Tools/Invoke-RcloneSyncs.ps1"`
- Einzelnen Sync live starten: `pwsh -File ".Tools/Invoke-RcloneSyncs.ps1" -JobName <name> -LiveRun`
- Generischer Runner: `pwsh -File ".Tools/Invoke-RcloneAutomation.ps1" -Kind sync|mount ...`

## Logging

- Ablageort: `.logs/`
- Namensschema: `yyyyMMdd_HHmmss_<id>.log`
