# CLAUDE.md – Emotional CRM

Du baust ein eigenständiges, mandantenfähiges CRM für Yogalehrerinnen und kleine Studios, die ihre App auf **Flenski** betreiben. Es zeigt Guthaben (Besuche), Kundinnen aus der App und von extern, Produkte, Aktivität (wer ist dabei, wer kühlt ab) und Signale, um wen sich die Lehrerin kümmern sollte. Die Oberfläche läuft direkt in einer Flenski-Custom-Page, alle Daten und Regeln liegen in Supabase.

**Oberstes Ziel neben Funktion: Einfachheit.** Marcel ist kein Entwickler und muss den Aufbau verstehen. Zwei Bausteine (Supabase + eine HTML-Datei), keine zusätzlichen Dienste, Frameworks oder Build-Schritte ohne ausdrückliche Rückfrage.

Auftraggeber: Marcel (Systemsafari). Erste Mandantin: Yoga by Lana. **Das Produkt ist nicht für eine Kundin gebaut, sondern für jede Flenski-App.**

## Pflichtlektüre vor jeder Arbeit

1. `docs/01-konzept.md` – Was und warum
2. `docs/02-architektur.md` – Stack, Prinzipien, Einbettung
3. `docs/03-datenmodell.md` – Tabellen, Regeln, RLS
4. `docs/04-flenski-integration.md` – was über Flenski gesichert / angenommen / unbekannt ist
5. `docs/05-phasen.md` – Reihenfolge und Abnahmekriterien
6. `docs/07-datenschutz.md` – Leitplanken
7. `docs/08-aktivitaet.md` – Modul Aktivität (Datensammlung ab Phase 0, Oberfläche in Phase 4b)
8. `inbox/` – echte Payloads und Mandanten-Konfiguration von Marcel

Wenn Code und Doku sich widersprechen: anhalten und fragen, nicht raten.

## Arbeitsweise

- Arbeite **phasenweise** nach `docs/05-phasen.md`. Starte nie eine neue Phase, bevor Marcel die vorherige abgenommen hat. Am Ende jeder Phase: kurze Zusammenfassung, was fertig ist, was offen ist, wie man es testet.
- Vor größeren Schritten (neue Tabelle, neue Abhängigkeit, Architekturänderung): Plan zeigen, dann bauen.
- Entscheidungen mit Tragweite als kurze Notiz in `docs/entscheidungen/NNNN-titel.md` (Kontext, Entscheidung, Folgen).
- Marcel ist kein Entwickler. Erkläre Ergebnisse in einfachem Deutsch, gib konkrete Klickschritte für alles, was er selbst tun muss (Supabase, Flenski).

## Stack (nicht ändern ohne Rückfrage)

- **Supabase**, Region Irland (`eu-west-1`, Projekt `emotional-crm`, siehe Entscheidung 0003): Postgres, Auth (Email-OTP-Code, kein Magic Link), Row Level Security, Edge Function `flenski-webhook` (TypeScript/Deno).
- **Oberfläche:** eine Datei `ui/crm.html`, reines HTML/CSS/JavaScript, Bibliotheken nur per CDN (`@supabase/supabase-js`, optional Alpine.js). Kein Build-Schritt, kein npm für die Oberfläche.
- **Fachlogik als SQL-Funktionen** in Supabase (`checkin`, `sell`, `correct`, `cancel_attendance` …), getestet mit Datenbank-Tests.
- **Git lokal:** Nach jedem abgeschlossenen Arbeitsschritt einen Commit mit verständlicher deutscher Nachricht anlegen, damit Marcel jederzeit zurück kann. Marcel bedient Git nicht selbst.
- Kein Next.js, kein Vercel, kein eigener Server.

## Harte Regeln

1. **Guthaben = Summe von `ledger_entries`.** Nie einen Zählerstand speichern oder überschreiben. Buchungen sind append-only, Korrekturen nur als Gegenbuchung mit Kommentar.
2. **Jede Tabelle hat `tenant_id` und RLS.** Für jede neue Tabelle gibt es einen Test, der beweist, dass Mandant A Mandant B nicht sieht.
3. **Kein Secret im Browser.** In `ui/crm.html` stehen nur Supabase-URL und anon key. Service-Role-Key, Webhook-Secrets und Flenski-Zugänge nur als Supabase-Secrets bzw. in `.env.local`. `.env*` nie committen; `.env.example` pflegen.
4. **Webhooks: erst roh speichern, dann verarbeiten.** Immer sofort `200` antworten. Verarbeitung idempotent.
5. **Keine Annahmen über Flenski-Payloads.** Prüfschemas für Payloads nur aus echten Beispielen in `inbox/webhooks/` ableiten. Fehlt ein Beispiel: Schema als `TODO` markieren und Marcel fragen.
6. **Fachlogik nur in SQL-Funktionen**, nie doppelt in der Oberfläche. Oberfläche und Webhook rufen dieselben Funktionen auf. Jede Regel (Guthaben, FEFO-Abbuchung, Storno, Ablauf, Signale) hat einen Datenbank-Test.
7. **Mobil zuerst.** Jede Ansicht muss auf 375 px Breite einhändig bedienbar sein. Der Check-in ist der wichtigste Screen. Die Oberfläche muss im Flenski-Layout leben: Präfix `ecrm-` für alle Klassen, alles in `#ecrm-root`, keine globalen Styles.
8. **Keine Gesundheitsdaten**, keine zusätzlichen personenbezogenen Felder ohne Rückfrage.
9. **Keine Löschung von Buchungen**, auch nicht beim Löschen einer Kundin (dann anonymisieren).
10. **Aktivitätsdaten sparsam:** nur Ereignisart, Zeitpunkt und Titel (Kurs/Event/Artikel), nie Inhalte von Beiträgen, Kommentaren oder Fragen. Rollierend 12 Monate, danach löschen. Der Aktivitätsstatus (Neu/Aktiv/Kühlt ab/Eingeschlafen) wird in der Datenbank berechnet, nicht in der Oberfläche.
11. **Alpine.js: keine Funktionen im beobachteten Zustand.** Alpine ruft Funktionen, die in einem Ausdruck (`x-if`, `x-show`, `x-text` …) als Ergebnis auftauchen, selbst auf. Am 22.10.2026 hat das eine Check-in-Schleife mit über 500 Buchungen ausgelöst. Rückruf-Funktionen außerhalb des Alpine-Zustands halten. Nach jedem Oberflächentest mit Buchungen die Anzahl der Buchungen zweimal zählen.

## Sprache und Ton der Oberfläche

- Deutsch, Du-Form, kurz und warm. Begriffe: „Kundin" (inklusiv gemeint), „Guthaben", „Besuch", „Karte", „Stunde", „Check-in".
- Zahlen immer mit Kontext: „noch 2 von 4 · gültig bis 12.12."
- Leere Zustände erklären den nächsten Schritt („Noch keine Kundinnen – importiere deine Liste oder lege die erste an").

## Befehle (sobald eingerichtet)

```
supabase db push                         # Migrationen ins Supabase-Projekt
supabase functions deploy flenski-webhook
supabase test db                         # Datenbank-Tests
```
Auf Marcels Rechner heißt `supabase` konkret `./.tools/supabase.exe`, mit `SUPABASE_ACCESS_TOKEN` und `SUPABASE_DB_PASSWORD` aus `.env.local` als Umgebungsvariablen (kein `supabase login`, siehe Entscheidung 0003). Diese Werte nie ausgeben.

Weitere Skripte (`scripts/`): `sql.mjs` (SQL ausführen), `test-db.mjs` (Datenbank-Tests), `invite-user.mjs` (Person einladen), `upload-webhook-secrets.mjs` (Flenski-Schlüssel), `export-webhooks.mjs` (Beispiel-Payloads anonymisiert), `setup-flenski-sync.mjs` (Flenski-Schlüssel einer Mandantin hinterlegen, Abgleich einschalten).

Die Oberfläche lokal testen: `ui/crm.html` im Browser öffnen (mit Test-Konfiguration).

## Aktueller Stand

**Neuausrichtung 22.10.2026 (Entscheidung 0005):** Flenski ist die Quelle, das CRM zeigt die Menschen. Plan `docs/phase3-plan.md`: Schritte 1–4 gebaut am 22.10.2026 (Webhook-Verarbeitung, Erstabgleich, Aktivitätsstatus, neue Oberfläche). Oberfläche v2 am 22.10.2026 (Übersicht · Menschen · Kurse · Angebote, Glanzoptik, Profilfotos, Knopf zum Flenski-Profil, keine manuelle Zahlung, Kurse nur echte Flenski-Termine). Automatischer Teilnehmer-Abgleich mit Flenski seit 23.10.2026 (Entscheidung 0006, Edge Function `flenski-sync`, alle 5 Min.). Wartet auf Test in Flenski und Abnahme.

**Phase 0 abgenommen am 22.10.2026. Phase 1 abgenommen am 22.10.2026. Phase 2 (Oberfläche) gebaut und lokal getestet am 22.10.2026, wartet auf Test in Flenski und Abnahme: `docs/phase2-plan.md`, Datei `ui/crm.html`, lokal ansehen mit `node scripts/serve-ui.mjs`.** (`docs/phase1-plan.md`): alle Tabellen, RLS, Fachfunktionen (`sell`, `checkin`, `undo_checkin`, `cancel_attendance`, `correct`, `expire_entitlements`, `customer_signals`, `anonymize_customer`), nächtliche Jobs (pg_cron), Demo-Mandantin `yoga-by-lana-demo` (`supabase/seed.sql`), Registrierung geschlossen – Einladung per `node scripts/invite-user.mjs`. Fertig: Tabellen `tenants` + `webhook_events`, Edge Function `flenski-webhook` (speichert roh, dedupliziert), erweiterte `ui/phase0-test.html`. Erledigt: 17 Automationen mit Signaturprüfung (Entscheidung 0004), eigener Mailversand + deutsche Code-Mail. Einbettung entschieden: direkt im Flenski-Embed-Widget (Entscheidung 0001). iPhone getestet. Für Phase 1 merken: offene Registrierung (`disable_signup`) schließen, Nutzer nur per Einladung. Datenbank-Tests: `node scripts/test-db.mjs` (Ersatz für `supabase test db`, weil Docker fehlt). Offene Entscheidungen: `docs/06-offene-punkte.md`, Abschnitt A.

Neu seit 21.10.2026: Modul Aktivität (`docs/08-aktivitaet.md`, Entscheidung `docs/entscheidungen/0002-aktivitaets-modul.md`). Wichtig für Phase 0: Die Aktivitäts-Trigger müssen von Anfang an mitgeschnitten werden, weil sich Historie nicht nachholen lässt.
