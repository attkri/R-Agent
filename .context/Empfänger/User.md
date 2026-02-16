# User

## Arbeitspräferenzen

- Sprache: Deutsch.
- Mounts per Zuruf (Just-in-Time); Standard-Start detached.
- Entscheidung nach Mount: `temporär` oder `dauerhaft`.
- Aktueller Stand: `dauerhaft` gewünscht (Auto-Mount bei Anmeldung aktivieren/verwenden).
- Cloud-Ablage bewusst unverschlüsselt für Zugriff über Web und andere Systeme.
- Logging direkt in `.logs/` mit Muster `yyyyMMdd_HHmmss_<id>.log`.
- Bei Sync-Läufen Abschlussbericht mit Dauer, Änderungen und ExitCode.

## Operative Hinweise

- Vor Änderungen an bestehenden Dateien immer zuerst Änderungsstatus prüfen, da parallele User-Änderungen möglich sind.
- Syncs laufen prioritätsgesteuert und parallel (max. 10 je Prioritätsstufe).
