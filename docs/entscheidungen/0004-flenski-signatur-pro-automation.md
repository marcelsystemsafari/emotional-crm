# 0004 – Flenski-Signatur: ein Schlüssel pro Automation

Datum: 22.10.2026
Status: entschieden

## Kontext

Flenski signiert jede Webhook-Nachricht im Header `X-Flenski-Signature: sha256=<hex>` (HMAC-SHA256 über den Rohbody). Erkenntnisse aus Phase 0:
- Jede Automation hat einen **eigenen Schlüssel**. Er wird **nur einmal** beim Anlegen angezeigt.
- Der Knopf „Testen“ signiert mit einem **Einmalschlüssel**. Testnachrichten lassen sich also nie prüfen.

Alternative war ein eigenes Geheimwort in der Webhook-URL (eine Einstellung pro Mandantin, keine Flenski-Schlüssel). Marcel hat sich für die Flenski-Schlüssel entschieden und alle Automationen neu angelegt.

## Entscheidung

1. Schlüssel liegen in der Tabelle `webhook_trigger_secrets` (Mandantin + Trigger, nur Service-Role).
2. Der Trigger-Name ist derselbe wie `?trigger=` in der Webhook-URL.
3. Marcel trägt neue Schlüssel als `FLENSKI_SECRET_<TRIGGER>=` in `.env.local` ein. `node scripts/upload-webhook-secrets.mjs [slug]` überträgt sie, ohne sie anzuzeigen.
4. Die Edge Function speichert **jede** Nachricht und setzt `signature_valid`: `true` = passt, `false` = passt nicht (auch alle Testnachrichten), `null` = kein Schlüssel hinterlegt. Verarbeitet werden ab Phase 3 nur Nachrichten mit `true`.

## Folgen

- Einrichtung einer neuen Mandantin: pro Automation den Schlüssel sofort sichern (in `docs/04`, Abschnitt „Einrichtung“, zu ergänzen).
- Geht ein Schlüssel verloren, muss nur diese eine Automation neu angelegt werden.
- Testnachrichten bleiben als Rohdaten nützlich (Aufbau), lösen aber nie eine Wirkung aus.
