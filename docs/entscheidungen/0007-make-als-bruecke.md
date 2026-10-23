# 0007 – Make als Brücke für Plan-Entzug und Teilnehmerliste

**Datum:** 23.10.2026 · **Entschieden von:** Marcel

## Kontext
Der Flenski-API-Schlüssel darf nur lesen (Termine, Mitglieder). Plan entziehen/zuweisen (`/apps/{appId}/profiles/plans[/revoke]`) und die vollständige Teilnehmerliste (`/events/{id}/attendees`) liefern 401. Flenski bietet laut Support (noch) keine Schlüssel mit mehr Rechten. Make hat über die App „Flenski“ eine Verbindung mit diesen Rechten („My Flenski connection“).

## Entscheidung
- Ein Make-Szenario **„🧘 ECRM: Flenski-Aktionen“** (ID 10031785, Webhook 4460281) übernimmt genau drei Aktionen: `revoke`, `assign`, `attendees`. Es antwortet dem CRM mit `{"ok": true, …}`.
- Make wird **nur bei Bedarf** von der Edge Function `flenski-sync` angestoßen, nie per Zeitplan:
  - Plan entziehen: Karte leer/abgelaufen (Schalter `settings.plan_entzug_automatisch`).
  - Plan zurückgeben: Karte wieder aufgefüllt.
  - Teilnehmerliste: nur wenn Flenski die Namensliste eines Termins beim Abschluss gekürzt hat.
- Etwa 3 Make-Operationen je Aktion; erwartet unter 50 im Monat je Lehrerin.
- Die Make-Adresse liegt als Supabase-Secret `MAKE_WEBHOOK_URL`; sie ist nicht öffentlich und wird wie ein Schlüssel behandelt.

## Folgen
- Zusätzlicher Baustein neben Supabase und der HTML-Datei (bewusst, mit Rückfrage entschieden). Fällt Make aus, bleiben Hinweise für die Lehrerin stehen (nach 3 Fehlversuchen) bzw. das CRM gleicht vorsichtig ab („Teilnahme unklar“) – es wird nie geraten.
- Für weitere Lehrerinnen: Ihre App muss im Flenski-Projekt der Make-Verbindung liegen; Projekt-ID je Mandantin in `settings.flenski_project_id`.
- Getestet am 23.10.2026 mit Marcels Testkonto (Sarah Oberste): Entzug und Rückgabe über die ganze Kette, keine Doppelkarte.
- Sobald Flenski Schlüssel mit Schreibrechten anbietet, kann Make wieder entfallen (nur `make()` in `flenski-sync` ersetzen).
