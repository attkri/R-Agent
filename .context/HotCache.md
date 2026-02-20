# HotCache

- Stand: 2026-02-17
- Projektfokus: Cloud-Storage-Automatisierung mit `rclone` und `WinFsp` unter Windows 11.
- Cloud-Modus: bewusst unverschlüsselt (kein `crypt`-Remote), damit Webzugriff und Zugriff von anderen Systemen ohne Zusatzkonfiguration möglich sind.
- Mount-Verhalten: Just-in-Time auf Zuruf; Sofortstart detached über Scheduled Task (`RcloneMountsOnDemand`).
- Persistenz-Option: nach Mount entscheidet der User `temporär` oder `dauerhaft`.
- Auto-Mount bei Login: nur bei User-Entscheidung `dauerhaft` über Scheduled Task `RcloneMountsAtLogon`.
- Unmount-Regel: `Stop-RcloneMounts.ps1` entfernt zusätzlich `RcloneMountsAtLogon`.
- Log-Regel: direkte Ablage in `.logs/` mit Muster `yyyyMMdd_HHmmss_<id>.log`.
- Sync-Regel: prioritätsgesteuert (`priority` aufsteigend), pro Stufe parallel bis max. 10 Jobs.
- Abschlussberichte: pro Sync-Job und Gesamtlauf mit Dauer, Änderungsumfang (wenn im Log verfügbar) und ExitCode.
- Aktive Remotes: `gdrive:`, `pcdrive:`.
- Rclone-Pfad: `C:\Program Files\rclone\rclone.exe`.
- WinFsp: installiert (für Mounts erforderlich).

## Letzte relevante Punkte

- **s4 und s5 auf `bisync` umgestellt** (bidirektionale Sync).
- `bisync` benötigt initialen `--resync`-Lauf; Runner führt diesen automatisch bei ExitCode 7 durch.
- `bisync` ist strenger als `sync`: bei Fehlern Abbruch + neuer `--resync` nötig.
- `/MySyncNow`-Command erstellt für repo-unabhängigen Sync-Aufruf (absolute Pfade).
- Globale Permissions in `opencode.json` erweitert (`bash: allow`, `external_directory`).
- `s1`-Fehler durch Exclude `R-Agent/.logs/**` stabilisiert.
- Runner unterstützt Job-Filter per Name oder ID (z. B. `s5`).
- HEALTH_CHECK enthält Repo-Pfad-Abgleich gegen `C:\Users\attila\.Secrets\RClone.Secrets.json` (`facts.repo_local_path`).
