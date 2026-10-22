# 0006 – Teilnahme kommt aus der finalen Flenski-Teilnehmerliste

**Datum:** 22.10.2026 · **Entschieden von:** Marcel

## Kontext
Flenski meldet per Automation nur die Anmeldung („Am Event teilgenommen“), nicht die Abmeldung. Bisher hat `finalize_past_sessions()` nach Terminbeginn jede Anmeldung als „war da“ gezählt und abgebucht. Wer sich in Flenski wieder abgemeldet hat, wurde trotzdem belastet, oder die Lehrerin musste das von Hand korrigieren. Beim Test ist das auseinandergelaufen: Sarah war in Flenski angemeldet, im CRM aber als „abgesagt“ eingetragen. Das verwirrt die Lehrerin.

## Entscheidung
- **5 Minuten nach Kursbeginn** liest das CRM selbst die finale Teilnehmerliste des Termins aus Flenski. Die Liste ist die Wahrheit.
  - Wer drauf steht, war da und bekommt einen Besuch abgezogen. Wer sich nicht rechtzeitig ausgetragen hat, hat Pech gehabt, das ist so gewollt.
  - Wer nicht mehr drauf steht, hat sich abgemeldet. Kein Abzug.
  - Wer drauf steht, aber dem CRM fehlt (Webhook verpasst), wird nachgetragen.
- Ohne Make. Das Auslesen macht Supabase selbst (pg_cron und Edge Function) mit einem Flenski-API-Zugang je Mandantin.
- Die Lehrerin greift nur im Ausnahmefall ein (Kulanz: Besuch zurückgeben).

## Folgen
- `finalize_past_sessions()` bucht nicht mehr blind ab. Abgebucht wird nur noch nach erfolgreichem Abgleich.
- Ist Flenski nicht erreichbar, versucht das CRM es erneut. Nach 24 Stunden gibt es einen Hinweis an die Lehrerin statt einer geratenen Abbuchung.
- Es braucht einen Flenski-API-Schlüssel für den Server. Marcel hat einen solchen Zugang bereits in Make genutzt (Verbindung „My Flenski connection“, Module `makeAPIcall` auf `/apps/{appId}/events` und `revokePlansProfile`).
- Mit demselben Zugang werden später möglich: neue Termine automatisch übernehmen und Plan entziehen, wenn die Karte leer oder abgelaufen ist.
