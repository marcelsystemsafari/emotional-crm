# 03 – Datenmodell

Alle Tabellen haben `id uuid pk default gen_random_uuid()`, `tenant_id uuid not null` (außer `tenants`), `created_at timestamptz default now()`. Geldbeträge in Cent (`integer`). Zeiten in UTC speichern, in der Zeitzone des Mandanten anzeigen.

## Mandanten und Zugriff

**tenants**
- `name`, `slug` (unique, für URLs), `timezone` (default `Europe/Berlin`)
- `status` enum: `trial | active | cancelled | dormant | deleted`
- `dormant_consent_at` nullable (Zustimmung zum Ruhemodus), `delete_after` (Datum der geplanten Löschung)
- `flenski_app_url` (z. B. `https://appdemo.systemsafari.de/yoga-by-lana`)
- `webhook_secret` (nur serverseitig lesbar)
- `settings jsonb` (Schwellen für Signale, Stornofrist in Stunden, Branding-Farbe)

**tenant_members**
- `tenant_id`, `user_id` (auth.users), `role` enum: `owner | staff`
- unique (`tenant_id`, `user_id`)

**platform_admins** – `user_id` (Marcel)

## Kundinnen

**customers**
- `first_name`, `last_name`, `email` (nullable), `phone` (nullable)
- `source` enum: `flenski | extern`
- `flenski_profile_id` uuid nullable, unique pro Mandant
- `is_child` boolean default false, `guardian_name`, `guardian_email`, `guardian_phone` (für Kinderkurse: Kontakt läuft über die Eltern)
- `tags text[]` (eigene + aus Flenski übernommene)
- `note text` – **nur organisatorisch** (UI-Hinweis: keine Gesundheitsangaben)
- `archived_at` nullable
- `last_visit_at` (denormalisiert, per Trigger aus `attendances` gepflegt, für schnelle Filter)
- `last_app_activity_at` (denormalisiert, per Trigger aus `activity_events` gepflegt; nur bei `source = flenski`)

Dubletten-Regel: Kommt ein Flenski-Mitglied mit einer E-Mail, die schon bei einer externen Kundin steht, wird **nicht automatisch zusammengeführt**, sondern ein Hinweis „Mögliche Dublette" erzeugt. Die Lehrerin entscheidet.

## Produkte und Ansprüche

**products**
- `name`, `active`
- `type` enum:
  - `credits` – Karte mit n Einheiten (4er-Paket, 10er-Karte)
  - `period` – fester Zeitraum/Kursblock, Teilnahme ohne Abzug (Kursblock 10 Wochen)
  - `subscription` – laufendes Abo, unbegrenzt oder n Einheiten pro Monat
  - `single` – Einzelstunde (= credits mit 1)
- `credits` int nullable (bei `credits`/`single`; bei `subscription` optional pro Monat)
- `validity_days` int nullable (Gültigkeit ab Kauf; null = unbegrenzt)
- `price_cents` int nullable
- `flenski_plan_id` uuid nullable – Zuordnung zum Flenski-Plan
- `category` text nullable (z. B. „Kinderyoga", „Erwachsene") – steuert, für welche Stunden das Produkt gilt

**entitlements** (ein Kauf / eine Berechtigung einer Kundin)
- `customer_id`, `product_id`
- `source` enum: `flenski_order | flenski_plan | manual`
- `paid_via` enum: `app | bar | ueberweisung | verein | gutschein | sonstiges`
- `price_cents` (tatsächlich bezahlt, kann vom Produktpreis abweichen)
- `starts_at`, `expires_at` (aus `validity_days` berechnet, manuell änderbar mit Protokolleintrag)
- `status` enum: `active | used_up | expired | cancelled` (abgeleitet, per Funktion aktualisiert)
- `external_ref` (Flenski-Bestell-ID o. Ä.)

**ledger_entries** (append-only, nie UPDATE/DELETE – per RLS und Trigger erzwingen)
- `entitlement_id`, `customer_id`
- `delta` int (+4 Kauf, −1 Besuch, +1 Storno, ±n Korrektur, −n Verfall)
- `reason` enum: `purchase | visit | refund | correction | expiry | transfer`
- `attendance_id` nullable
- `created_by` (user_id oder `system`), `comment` (Pflicht bei `correction`)

Restguthaben einer Berechtigung = `sum(delta)`. Restguthaben einer Kundin = Summe über aktive Berechtigungen. Als View `v_entitlement_balance` und `v_customer_overview`.

**Abbuchungsreihenfolge** bei mehreren passenden Karten: die zuerst ablaufende zuerst (FEFO), dann die ältere.

## Stunden und Anwesenheit

**sessions**
- `title`, `starts_at`, `ends_at`, `category`
- `flenski_event_id` nullable (unique pro Mandant)
- `capacity` nullable

**attendances**
- `session_id`, `customer_id`
- `status` enum: `registered | present | cancelled_in_time | cancelled_late | no_show`
- `entitlement_id` nullable (welche Karte belastet wurde)
- `checked_in_by`, `checked_in_at`
- unique (`session_id`, `customer_id`)

Regeln (als SQL-Funktionen in Supabase, mit Datenbank-Tests):
- `present` → −1 von passender `credits`-Berechtigung. Bei `period`/`subscription` ohne Limit: kein Abzug, nur Anwesenheit.
- `cancelled_in_time` (vor Stornofrist) → kein Abzug bzw. Rückbuchung.
- `cancelled_late` / `no_show` → Abzug gemäß Mandanten-Einstellung (Default: Abzug).
- Keine passende Berechtigung → Check-in trotzdem möglich, Kundin wird als „offen / ohne Guthaben" markiert.

## Aktivität (Modul, siehe 08)

**activity_events** (nur Anfügen, wird nur durch die rollierende Löschung nach 12 Monaten und durch Kundinnen-Löschung entfernt)
- `customer_id` nullable (wird über `flenski_profile_id` zugeordnet; ohne Zuordnung bleibt der Eintrag liegen und wird beim Anlegen der Kundin nachgezogen)
- `flenski_profile_id` uuid
- `type` enum: `course_enrolled | course_completed | post_created | comment_created | question_asked | event_attended | file_downloaded | article_read | other` (Erweiterung nur anhand echter Payloads aus `inbox/webhooks/`)
- `title` text nullable (Kurs-/Event-/Artikelname, **nie Inhalte**)
- `occurred_at` timestamptz, `webhook_event_id` nullable, `dedupe_key` (unique pro Mandant)
- Index auf (`tenant_id`, `customer_id`, `occurred_at desc`)

**View `v_customer_engagement`** (pro Kundin): `last_activity_at = greatest(last_visit_at, last_app_activity_at)`, `status` (`neu | aktiv | kuehlt_ab | eingeschlafen`), `score_30d`, `events_8w` (Wochenwerte für den Mini-Verlauf). Die Berechnung liegt als SQL-Funktion in der Datenbank.

**Einstellungen** in `tenants.settings`: `engagement_neu_tage` (14), `engagement_aktiv_tage` (14), `engagement_abkuehlt_tage` (30), Gewichte je Ereignisart und für Besuche.

## Integration und Protokoll

**webhook_events**
- `tenant_id`, `trigger` (Flenski-Triggername), `headers jsonb`, `payload jsonb`
- `signature_valid` boolean nullable, `dedupe_key` (unique)
- `received_at`, `processed_at`, `error`

**audit_log** – wer hat wann was an Kundinnen/Produkten/Einstellungen geändert (`actor`, `action`, `entity`, `entity_id`, `diff jsonb`).

## Row Level Security

- Jede Tabelle: `select/insert/update` nur, wenn `auth.uid()` in `tenant_members` für die `tenant_id` steht (bzw. `platform_admins`).
- `staff` darf keine `products`, `tenants.settings` oder Exporte ändern/abrufen.
- `ledger_entries`: nur `insert`, kein `update/delete` für irgendwen.
- `webhook_events`, `tenants.webhook_secret`: nur Service-Role (Server).
- Mandantenstatus `cancelled`: alle Schreibrechte entzogen, Lesen + Export erlaubt.
- Mandantenstatus `dormant`: kein Zugriff für Mandanten-Nutzer, Webhooks werden angenommen, aber nicht verarbeitet. Nur `platform_admins` können reaktivieren.
- `activity_events` und `v_customer_engagement`: nur `owner` und `staff` des eigenen Mandanten. Schreiben nur Service-Role (Webhook-Funktion).
