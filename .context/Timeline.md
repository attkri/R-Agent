# Timeline

- 2026-02-15: Projekt auf unverschlüsselten Cloud-Betrieb festgelegt (kein `crypt`-Remote).
- 2026-02-15: Mount-/Sync-Automation in `.Tools/` aufgebaut und zentral über `C:\Users\attila\.Secrets\RClone.Secrets.json` gesteuert.
- 2026-02-15: Logging auf `.logs/` mit Namensschema `yyyyMMdd_HHmmss_<id>.log` vereinheitlicht.
- 2026-02-15: Sync-Orchestrierung auf Priorität + Parallelität (max. 10 je Prioritätsstufe) umgestellt.
- 2026-02-15: Abschlussbericht pro Job und Gesamtlauf eingeführt (Dauer, Änderungen, ExitCode).
- 2026-02-16: `s4`-Excludes nach Fehlern erweitert (`ElevatedDiagnostics`, `.logs/**`, `**/*.partial`), Lauf danach mit ExitCode 0 erfolgreich.
- 2026-02-16: Filter-Mismatch bei `Access is denied` auf `AppData/Local/ElevatedDiagnostics` dokumentiert; robuster Fix mit quellrelativem Exclude (`/AppData/Local/ElevatedDiagnostics/**` bzw. bei Quelle `.../AppData` -> `/Local/ElevatedDiagnostics/**`).
- 2026-02-16: Mount-Workflow auf Just-in-Time + detached Sofortstart (`-DetachedViaTask`) umgestellt, damit Mounts beim Schließen von OpenCode bestehen bleiben.
- 2026-02-16: User-Entscheidung `dauerhaft` umgesetzt; Auto-Mount bei Login über `RcloneMountsAtLogon` eingerichtet.
- 2026-02-16: Mount-Fehler behoben (`Can't set -v and --log-level`) durch Runner-Anpassung bei Verbose-Flags.
- 2026-02-16: Schutzmaßnahmen ergänzt: Skip bei bereits belegtem Mountpoint + Entprellung für On-Demand-Starts (20s).
- 2026-02-16: HEALTH_CHECK um Repo-Pfad-Abgleich gegen `facts.repo_local_path` erweitert.
- 2026-02-17: `/MySyncNow`-Command erstellt für repo-unabhängigen Sync-Aufruf mit absoluten Pfaden.
- 2026-02-17: Globale Permissions in `opencode.json` erweitert (`bash: allow`, `external_directory`).
- 2026-02-17: `s1` durch Exclude `R-Agent/.logs/**` stabilisiert.
- 2026-02-17: `s4` und `s5` auf `bisync` umgestellt (bidirektionale Sync).
- 2026-02-17: `bisync`-Auto-Resync bei ExitCode 7 im Runner implementiert.
