# HotCache

- Stand: 2026-02-16
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

- `s4`-Fehlerbild wurde durch Excludes stabilisiert (`ElevatedDiagnostics`, `.logs/**`, `*.partial`).
- Runner unterstützt Job-Filter per Name oder ID (z. B. `s5`).
- Bei `Access is denied` auf `AppData/Local/ElevatedDiagnostics` war die Ursache ein Exclude-Muster, das nicht zur Quellwurzel passte.
- Bewährtes Muster bei Quelle `C:\Users\attila`: `--exclude "/AppData/Local/ElevatedDiagnostics/**"`.
- Wenn die Quelle bereits `...\AppData` ist: `--exclude "/Local/ElevatedDiagnostics/**"`.
- Filterprüfung für solche Fälle: `-n -vv --dump filters`.
- Mount-Fehler `Can't set -v and --log-level` wurde im Runner behoben (kein doppeltes Loglevel mehr bei `-v`).
- Doppelstart-Schutz: belegte Mountpoints werden je Job übersprungen statt erneut gemountet.
- Entprellung aktiv: On-Demand-Detached-Start ignoriert unmittelbare Folgeaufrufe (20s-Fenster).
- HEALTH_CHECK enthält Repo-Pfad-Abgleich gegen `.Secrets/config.rclone.json` (`facts.repo_local_path`).
