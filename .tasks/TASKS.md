# Aufgaben

## Aktiv

- **Logging / Info**
  - Wenn eine Synchronisierung läuft die besonders lange dauert wäre es schön wenn man eine Möglichkeit hätte die zum Beispiel anzeigt wie lange sie schon läuft oder wie lang es noch laufen wird oder eine Fortschritt in Prozent Oder ähnliches

- **Folgenden Block in AGENTS.md einarbeiten:**

```markdown
## Projektentscheidungen (mit User abgestimmt)

- **Stand 2026-02-15:** Cloud-Ablage bleibt bewusst **unverschlüsselt** (kein `crypt`-Remote), damit Zugriff über Anbieter-Weboberfläche und andere Systeme ohne zusätzliche `rclone`-Konfiguration möglich ist.
- Für dieses Projekt daher keine automatische Crypt-Erstellung, außer der User fordert sie später explizit an.
- **Logging-Regel (Stand 2026-02-15):** Logs liegen direkt in `.logs\` nach dem Muster `yyyyMMdd_HHmmss_<id>.log` (keine Unterordner pro Lauf).
- **Mount/Unmount/Check-Regel (Stand 2026-02-15):** Details stehen zentral unter `## Deine Workflows` in `Mounten (Sofortstart)`, `Unmounten` und `Self Health Check (bei Problemen)`.
```

## Erledigt

- **Übersichtstabelle in AGENTS.md mit Tool-Name/Aufruf und Beschreibung ergänzen**
  - Kontext: Aus übergebenem Command-Text übernommen; Ziel ist eine klare Tool-Übersicht für Aufgabenverwaltung.
