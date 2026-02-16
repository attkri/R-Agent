# Sync und Mount

## Mounts

- Quelle: `.Secrets/config.rclone.json` -> `facts.automation.mounts`
- Aktuelle Jobs:
  - `m1` / `pcdrive-p`: `pcdrive:` -> `P:`
  - `m2` / `gdrive-g`: `gdrive:` -> `G:`
- Start (JIT, detached): `pwsh -NoProfile -File ".Utils/Start-RcloneMounts.ps1" -LiveRun -DetachedViaTask`
- Stop: `pwsh -NoProfile -File ".Utils/Stop-RcloneMounts.ps1"`
- Grundsatz: Mounts per Zuruf (Just-in-Time).
- Persistenz-Entscheidung nach Mount:
  - `temporär`: keine Login-Persistenz.
  - `dauerhaft`: Auto-Mount bei Login über `RcloneMountsAtLogon`.
- Wichtige Schutzlogik:
  - belegte Mountpoints (`P:`, `G:`) werden pro Job übersprungen.
  - On-Demand-Detached-Start ist gegen Doppelklick/Mehrfachstart entprellt (20s).

## Syncs

- Quelle: `.Secrets/config.rclone.json` -> `facts.automation.syncs`
- Ausführung: `pwsh -File ".Utils/Invoke-RcloneSyncs.ps1" -LiveRun -MaxParallel 10`
- Steuerung:
  - Priorität aufsteigend (`priority`)
  - parallel je Prioritätsstufe (max. 10)
  - nächste Priorität erst nach Abschluss der aktuellen Stufe
- Jobfilter:
  - per Name oder ID (`-JobName s5`)

## Logging und Abschluss

- Logdateien direkt in `.logs/`
- Muster: `yyyyMMdd_HHmmss_<id>.log`
- Abschlussbericht:
  - pro Job: Dauer, Geändert (aus Log, wenn verfügbar), ExitCode
  - Gesamtlauf: Dauer, Jobs, Fehler/Erfolge, ExitCode

## HEALTH_CHECK bei Problemen

- Schnellcheck: `pwsh -NoProfile -Command 'Test-Path P:\; Test-Path G:\'`
- Prozesscheck: `pwsh -NoProfile -Command 'Get-CimInstance Win32_Process -Filter "name = ''rclone.exe''" | Where-Object { $_.CommandLine -match '' mount '' } | Select-Object ProcessId,CreationDate,CommandLine'`
- Logcheck: `pwsh -NoProfile -Command 'Get-ChildItem ".logs" -File | Sort-Object LastWriteTime -Descending | Select-Object -First 5 Name,LastWriteTime'`
- Repo-Pfad-Check: `pwsh -NoProfile -Command '$current=(Resolve-Path ".").Path; $cfg=Get-Content ".Secrets\config.rclone.json" -Raw | ConvertFrom-Json; $expected=[string]$cfg.facts.repo_local_path; if([string]::IsNullOrWhiteSpace($expected)){"repo_local_path fehlt in config"} elseif($current -ieq $expected){"repo_path_ok=true"} else {"repo_path_ok=false"; "expected=$expected"; "current=$current"}'`
- Wenn `repo_path_ok=false`: User informieren, dass u.a. Scheduled Tasks, Skriptpfade und weitere Automationspfade angepasst werden müssen.

## Troubleshooting: Excludes und Zugriffsfehler

- Bei `Access is denied` auf `AppData/Local/ElevatedDiagnostics` zuerst Exclude relativ zur Quellwurzel prüfen.
- Für Quelle `C:\Users\attila`: `--exclude "/AppData/Local/ElevatedDiagnostics/**"`.
- Für Quelle `...\AppData`: `--exclude "/Local/ElevatedDiagnostics/**"`.
- Zur Diagnose: `-n -vv --dump filters`.
