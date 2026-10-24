# Automationen für Yogini Nina anlegen

Stand 24.10.2026. Nina ist im CRM angelegt (Kürzel `yogini-nina`). Jetzt bekommt das CRM die Ereignisse aus Ninas App.

**Wichtig – anders als bei Lana:** Ninas bestehende Automationen (für Make, 8er-Karten usw.) **nicht löschen und nicht ändern**. Die neuen Automationen kommen nur dazu. Flenski schickt dasselbe Ereignis dann an beide.

## Vorbereitung
Öffne die Datei `.env.yogini-nina.local` im Projektordner (`E:CRM Projektemotional-crmemotional-crm`) mit dem Editor. Darin steht für jede Automation eine leere Zeile.

## Für jede Zeile der Tabelle (ca. 1 Minute pro Automation)
1. In Flenski **Ninas App** öffnen → **Automation erstellen**.
2. **Trigger** auswählen (linke Spalte).
3. Aktion **„Webhook senden“**.
4. **Endpoint-URL:** die Adresse aus der mittleren Spalte komplett einfügen.
5. **Zustellungslimits:** Max. Zustellungen pro Stunde → **ohne Limit**, Sammelfenster → **sofort senden**.
6. Speichern. Sobald Flenski den **Schlüssel** zeigt (nur einmal!): kopieren → in `.env.yogini-nina.local` hinter das passende `=` (rechte Spalte) einfügen → **sofort Strg + S** → erst dann den Dialog schließen.
7. Schlüssel nie in den Chat.

| Trigger in Flenski | Endpoint-URL | Zeile in `.env.yogini-nina.local` |
|---|---|---|
| Neues Mitglied | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yogini-nina&trigger=neues-mitglied` | `FLENSKI_SECRET_NEUES_MITGLIED` |
| Neuer Kontakt | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yogini-nina&trigger=neuer-kontakt` | `FLENSKI_SECRET_NEUER_KONTAKT` |
| Plan zugewiesen | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yogini-nina&trigger=plan-zugewiesen` | `FLENSKI_SECRET_PLAN_ZUGEWIESEN` |
| Plan entzogen | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yogini-nina&trigger=plan-entzogen` | `FLENSKI_SECRET_PLAN_ENTZOGEN` |
| Mitglied gelöscht | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yogini-nina&trigger=mitglied-geloescht` | `FLENSKI_SECRET_MITGLIED_GELOESCHT` |
| Bestellung abgeschlossen | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yogini-nina&trigger=bestellung-abgeschlossen` | `FLENSKI_SECRET_BESTELLUNG_ABGESCHLOSSEN` |
| Zahlung fehlgeschlagen | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yogini-nina&trigger=zahlung-fehlgeschlagen` | `FLENSKI_SECRET_ZAHLUNG_FEHLGESCHLAGEN` |
| Abonnement gekündigt | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yogini-nina&trigger=abonnement-gekuendigt` | `FLENSKI_SECRET_ABONNEMENT_GEKUENDIGT` |
| Am Event teilgenommen | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yogini-nina&trigger=am-event-teilgenommen` | `FLENSKI_SECRET_AM_EVENT_TEILGENOMMEN` |
| Event beginnt bald | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yogini-nina&trigger=event-beginnt-bald` | `FLENSKI_SECRET_EVENT_BEGINNT_BALD` |
| Zum Kurs angemeldet | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yogini-nina&trigger=zum-kurs-angemeldet` | `FLENSKI_SECRET_ZUM_KURS_ANGEMELDET` |
| Kurs abgeschlossen | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yogini-nina&trigger=kurs-abgeschlossen` | `FLENSKI_SECRET_KURS_ABGESCHLOSSEN` |
| Beitrag in einer Gruppe erstellt | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yogini-nina&trigger=beitrag-gruppe-erstellt` | `FLENSKI_SECRET_BEITRAG_GRUPPE_ERSTELLT` |
| Kommentar erstellt | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yogini-nina&trigger=kommentar-erstellt` | `FLENSKI_SECRET_KOMMENTAR_ERSTELLT` |
| Datei heruntergeladen | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yogini-nina&trigger=datei-heruntergeladen` | `FLENSKI_SECRET_DATEI_HERUNTERGELADEN` |
| Artikel gelesen | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yogini-nina&trigger=artikel-gelesen` | `FLENSKI_SECRET_ARTIKEL_GELESEN` |
| CTA auf dem Sperrbildschirm geklickt (alle Sperrbildschirme, alle CTA-Typen) | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yogini-nina&trigger=sperrbildschirm-cta-geklickt` | `FLENSKI_SECRET_SPERRBILDSCHIRM_CTA_GEKLICKT` |

**Nicht** anlegen: „Beitrag gelesen“ und „Punkte vergeben“ (zu viele Ereignisse).

## Danach
Sag Claude Bescheid. Claude lädt die Schlüssel hoch (`node scripts/upload-webhook-secrets.mjs yogini-nina`) und prüft mit einer echten Nachricht aus Ninas App, dass alles ankommt.
