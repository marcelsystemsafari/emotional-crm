# 02 – Architektur (schlanke Variante)

Leitgedanke: **so wenige Bausteine wie möglich**, damit Marcel jeden Teil versteht. Es gibt genau zwei:

1. **Supabase** – Datenbank, Login, Webhook-Empfang (Edge Functions). Hier liegt alles, was gespeichert und verarbeitet wird.
2. **Die Oberfläche** – eine einzige Datei (HTML + JavaScript), die direkt in die Flenski-Custom-Page eingefügt wird.

Kein Next.js, kein Vercel, kein eigener Server.

## Überblick

```
┌───────────────────────────────┐      Webhooks (POST, signiert)      ┌──────────────────────────────┐
│  Flenski-App (je Kundin)      │ ───────────────────────────────────▶ │  Supabase (EU, Irland)       │
│                               │                                      │                              │
│  Custom Page "Kundinnen"      │                                      │  Edge Function               │
│   └─ CRM-Oberfläche (JS) ─────┼──── Login + Daten (über RLS) ──────▶ │    flenski-webhook           │
│      läuft direkt in der Page │                                      │  Postgres + Auth + RLS       │
└───────────────────────────────┘                                      └──────────────────────────────┘
```

## Warum das sicher ist

Die Oberfläche enthält nur die **öffentliche Supabase-URL und den „anon key"**. Dieser Schlüssel ist von Supabase ausdrücklich dafür gedacht, im Browser zu stehen. Er erlaubt ohne Login nichts. Daten gibt es erst nach dem Login, und die Datenbank selbst (Row Level Security) prüft bei jeder Abfrage, ob die eingeloggte Person zu diesem Mandanten gehört.

Was **nie** in die Oberfläche darf: der `service_role`-Key und Webhook-Secrets. Die liegen nur in Supabase (Edge-Function-Secrets).

## Login

- Supabase Auth mit **6-stelligem Code per E-Mail** (Email OTP), **nicht** mit Magic Link.
  Grund: Ein Magic Link öffnet sich im normalen Browser, nicht in der Flenski-App auf dem Handy. Der Code wird einfach in der App eingetippt.
- Die Sitzung liegt im Speicher der Flenski-Seite selbst (keine Third-Party-Cookies nötig). Damit entfällt das iframe-Problem mit Safari.
- Rollen über `tenant_members`: `owner`, `staff`; Marcel als `platform_admin`.

## Oberfläche

- **Eine Datei** `ui/crm.html` (HTML + CSS + JavaScript), ohne Build-Schritt. Bibliotheken nur per CDN (`@supabase/supabase-js`; optional Alpine.js für Interaktivität).
- Mandant wird über eine Konfigurationszeile am Anfang der Datei festgelegt:
  ```html
  <script>window.CRM_CONFIG = { tenant: "yoga-by-lana" };</script>
  ```
- Muss neben dem Flenski-eigenen Layout funktionieren: alle CSS-Klassen mit Präfix `ecrm-`, alles in einem Container `#ecrm-root`, keine globalen Styles.
- Mobil zuerst (375 px).

### Updates bei mehreren Mandantinnen

- Phase 0–4: Datei wird bei Änderungen in jede Custom Page neu eingefügt (bei 1–3 Mandantinnen vertretbar).
- Später (ab ca. 5 Mandantinnen): Die Custom Page enthält nur noch eine Ladezeile, die Oberfläche selbst liegt an einem zentralen Ort. Dann reicht ein Update für alle. Dafür wird erst dann ein Hosting gewählt.

### Abhängigkeit von Phase 0

Diese Variante setzt voraus, dass Flenski eigenes JavaScript in Custom Pages **direkt in der Seite** ausführt und Anfragen an Supabase zulässt. Das wird in Phase 0 mit einem Testskript geprüft.
**Fallback**, falls nicht: dieselbe Datei als statische Seite hosten (z. B. Cloudflare Pages, kostenlos, kein Servercode) und per iframe einbetten. Dann gilt wieder das iframe-Login-Thema (siehe `docs/entscheidungen/`).

## Webhook-Empfang (Supabase Edge Function `flenski-webhook`)

- URL pro Mandant: `https://<projekt>.supabase.co/functions/v1/flenski-webhook?tenant=<tenant_id>`, eigenes Secret pro Mandant.
- Ablauf: Rohdaten + Header in `webhook_events` speichern → sofort `200` antworten → verarbeiten (idempotent über `dedupe_key`).
- Signatur `X-Flenski-Signature` prüfen, sobald das Verfahren bekannt ist (Phase 0). Bis dahin `signature_valid = null`.

## Grundprinzipien (unverändert)

1. Die eigene Datenbank ist die Wahrheit. Flenski liefert Ereignisse, entscheidet nichts.
2. Guthaben ist ein Buchungsprotokoll, kein Zähler.
3. Mandantentrennung in der Datenbank (RLS), nicht nur im Code.
4. Kein Secret im Browser (anon key ist kein Secret, service_role schon).
5. Webhooks erst speichern, dann verarbeiten.

## Fachlogik

Die Regeln (Guthaben, FEFO-Abbuchung, Storno, Ablauf, Signale) liegen **in der Datenbank** als SQL-Funktionen, z. B. `checkin(session_id, customer_id)`, `sell(customer_id, product_id, paid_via)`, `correct(entitlement_id, delta, comment)`. Die Oberfläche ruft nur diese Funktionen auf.
Vorteil: Eine Stelle für alle Regeln, egal ob Aufruf aus der Oberfläche oder aus dem Webhook. Getestet mit SQL-Tests (pgTAP) bzw. Tests gegen eine lokale Supabase.

## Ordnerstruktur

```
/supabase
  /migrations        → Tabellen, RLS, SQL-Funktionen
  /functions
    /flenski-webhook → Edge Function (TypeScript/Deno)
  /tests             → Datenbank-Tests
  seed.sql
/ui
  crm.html           → die komplette Oberfläche
  phase0-test.html   → Testskript für Flenski
/docs
/inbox
```

## Werkzeuge auf Marcels Rechner

- **Claude Code** – baut alles.
- **Supabase CLI** – Claude Code installiert und bedient sie (Migrationen einspielen, Funktion hochladen).
- **Git lokal** – Claude Code legt automatisch eine Versionsgeschichte an (jeder Arbeitsschritt rückgängig machbar). Marcel muss Git nicht bedienen.
- **GitHub** – optional, empfohlen als Sicherungskopie (siehe 06).
