# inbox – Rohmaterial für Claude Code

Hier legt Marcel alles ab, was Claude Code nicht selbst herausfinden kann. Claude Code liest diesen Ordner, ändert ihn aber nicht (außer auf Bitte).

## webhooks/

Echte Beispiel-Payloads aus Flenski, **eine Datei pro Trigger**, z. B.:

```
webhooks/neues-mitglied.json
webhooks/plan-zugewiesen.json
webhooks/plan-entzogen.json
webhooks/bestellung-abgeschlossen.json
webhooks/am-event-teilgenommen.json
webhooks/mitglied-geloescht.json
webhooks/abonnement-gekuendigt.json
webhooks/zahlung-fehlgeschlagen.json
webhooks/zum-kurs-angemeldet.json          (Aktivität, siehe docs/08)
webhooks/kurs-abgeschlossen.json
webhooks/beitrag-erstellt.json
webhooks/kommentar-erstellt.json
webhooks/frage-gestellt.json
webhooks/datei-heruntergeladen.json
webhooks/artikel-gelesen.json
```

So kommst du an die Payloads (bevor Phase 0 einen eigenen Empfänger hat):
1. https://webhook.site öffnen → die angezeigte eindeutige URL kopieren.
2. In Flenski: Automation erstellen → Trigger wählen → Aktion „Webhook senden" → URL einfügen → „Testen".
3. Besser zusätzlich echt auslösen (Testmitglied anlegen, Plan zuweisen, an Event teilnehmen), weil Test-Payloads oft Platzhalter enthalten.
4. Auf webhook.site den **Body** als JSON in die passende Datei kopieren, die **Header** (besonders `X-Flenski-Signature`) darunter in `<name>.headers.txt`.
5. Persönliche Daten echter Kundinnen vorher durch Fantasiewerte ersetzen.

## tenants/

Pro Mandantin eine Konfigurationsdatei nach Vorlage `yoga-by-lana.json`. Daraus erzeugt Claude Code Seed-Daten und die Produktzuordnung.

## kundinnen/

CSV/Excel-Listen externer Kundinnen (nur mit Einverständnis der Lehrerin, nicht ins Git-Repo committen – Ordner steht in `.gitignore`).

## screenshots/

Screenshots aus Flenski (Automations-Dialog, Custom-Page-Editor, Signatur-Einstellung), wenn etwas unklar ist.
