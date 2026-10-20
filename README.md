# Emotional CRM (Arbeitstitel)

Guthaben-, Kundinnen- und Bindungsübersicht für Flenski-Apps von Yogalehrerinnen und Studios. Ein Produkt von Systemsafari.

## Start mit Claude Code

1. Diesen Ordner als eigenes Projekt öffnen (nicht im Ordner einer Kundin).
2. `docs/06-offene-punkte.md`, Abschnitt A und D, erledigen.
3. Echte Webhook-Payloads in `inbox/webhooks/` legen (Anleitung: `inbox/README.md`).
4. Claude Code starten und schreiben:
   > Lies CLAUDE.md und alle Dateien in docs/ und inbox/. Fasse zusammen, was du verstanden hast und was dir für Phase 0 noch fehlt. Dann starte Phase 0.

## Inhalt

| Datei | Inhalt |
|---|---|
| `CLAUDE.md` | Arbeitsanweisung für Claude Code |
| `docs/01-konzept.md` | Problem, Zielgruppe, Signale, Geschäftsmodell |
| `docs/02-architektur.md` | Zwei Bausteine: Supabase + eine HTML-Datei |
| `docs/03-datenmodell.md` | Tabellen, Buchungsprotokoll, RLS |
| `docs/04-flenski-integration.md` | Gesichertes, Annahmen, Unbekanntes, Trigger-Mapping |
| `docs/05-phasen.md` | Bauphasen mit Abnahmekriterien |
| `docs/06-offene-punkte.md` | Checkliste, was noch fehlt |
| `docs/07-datenschutz.md` | DSGVO-Leitplanken |
| `inbox/` | Rohmaterial (Payloads, Mandanten-Konfiguration) |
| `ui/phase0-test.html` | 2-Minuten-Test für Flenski: läuft eigenes JavaScript in der Custom Page? |
