# 04 – Flenski-Integration

Unterschieden wird strikt zwischen **gesichert** (gesehen/getestet), **angenommen** und **unbekannt**. Claude Code darf auf Annahmen und Unbekanntem nichts Unumkehrbares aufbauen.

## Gesichert (Stand 20.10.2026, aus der Demo-App „Yoga by Lana")

**Mitglied (Profil)** liefert über die Flenski-Schnittstelle:
`id` (uuid), `fullName`, `email` (kann `null` sein, z. B. bei Team-Profilen), `status`, `isAdmin`, `isMemberOfTeam`, `isInvited`, `isBlocked`, `tags` (Namen als Strings), `plans` (**Namen** als Strings, keine IDs), `createdAt`, `lastLoginAt`.

**Plan** liefert: `id` (uuid), `name`, `type` (z. B. `private`). **Kein** Preis, **keine** Einheiten, **keine** Laufzeit.

Pläne der ersten Mandantin: „Kinderyoga 4er-Paket" und „Kursblock Erwachsene (10 Wochen)".

**Automationen** (Flenski → „Automation erstellen"), Aktion „Webhook senden":
- Endpoint-URL (POST), zusätzliche Header möglich
- Body wird im Header `X-Flenski-Signature` signiert
- Testfunktion „Testen"
- Zustellungslimits: Max. Zustellungen pro Stunde (**Überschuss wird verworfen!** → für das CRM immer „ohne Limit" lassen), Sammelfenster in Minuten (→ für das CRM „sofort senden")

Relevante Trigger: Neues Mitglied, Plan zugewiesen, Plan entzogen, Mitglied gelöscht, Neuer Kontakt, Bestellung abgeschlossen, Zahlung fehlgeschlagen, Abonnement gekündigt, Am Event teilgenommen, Event beginnt bald.

**Custom Pages** haben ein Feld für eigenen Code (`isCustomCodeEnabled`, `header`/`footer` als HTML).

**Aktivität (Stand 21.10.2026):** Im Flenski-Admin zeigt „Mitglied → Profil ansehen → Aktivität" einen Verlauf je Mitglied (z. B. „Mai: Kurs gestartet · geführte Audioentspannung · Event registriert"). Dieser Verlauf ist über die abgefragte Schnittstelle **nicht** abrufbar; sie liefert pro Mitglied nur `lastLoginAt`. Weitere für Aktivität relevante Trigger laut Dropdown: Zum Kurs angemeldet, Kurs abgeschlossen, Beitrag in Community/Gruppe erstellt, Kommentar erstellt, Frage in der Fragebox gestellt, Artikel gelesen, Datei heruntergeladen, Punkte vergeben.

## Angenommen (muss in Phase 0 bestätigt werden)

- Signatur ist HMAC-SHA256 über den Rohbody mit einem Secret, das Flenski anzeigt oder das wir setzen.
- Webhooks enthalten die Profil-ID des Mitglieds und bei Plänen die Plan-ID.
- Eigenes JavaScript in Custom Pages läuft direkt in der Seite (nicht in einem abgeschotteten iframe) und darf Anfragen an Supabase stellen. Test: `ui/phase0-test.html`.

## Unbekannt (blockiert einzelne Funktionen, nicht das MVP)

| Frage | Blockiert | Ohne Antwort machen wir |
|---|---|---|
| Was bedeutet „Am Event teilgenommen" – angemeldet oder anwesend? | automatischer Abzug | Webhook füllt nur die Teilnehmerliste (`registered`), Abzug erst beim Check-in |
| Enthält „Bestellung abgeschlossen" Betrag, Produkt/Plan und Mitglied? | automatischer Kauf-Eintrag | Plan zugewiesen erzeugt Berechtigung, Preis aus Produktkonfiguration |
| Gibt es eine REST-API mit eigenem Schlüssel für unseren Server? | Erstimport, Abgleich | Erstimport per CSV-Export aus Flenski oder einmalig über Marcel |
| Kann ein Plan per API entzogen werden? | Zugang bei 0 Guthaben automatisch sperren | Hinweis an die Lehrerin, manuell entziehen |
| Stellt die Custom Page Infos zum eingeloggten Mitglied bereit (Variablen)? | Endkundinnen-Ansicht (Phase 5) | Phase 5 zurückgestellt |
| Wird bei Webhooks wiederholt zugestellt, wenn wir nicht mit 200 antworten? | Robustheit | wir antworten immer sofort 200 und verarbeiten danach |
| Welcher Trigger deckt „Kurs gestartet", Lektion/Audio abgespielt ab? (kommt im Admin-Verlauf vor, im Trigger-Dropdown nicht erkennbar) | vollständige App-Aktivität | nur die vorhandenen Trigger zählen; Lücke in der Oberfläche nicht verschweigen |
| Enthalten die Aktivitäts-Webhooks Profil-ID **und** Titel (Kurs/Artikel/Event)? | Zuordnung zur Kundin, Anzeige im Verlauf | Ereignis ohne Titel speichern, Zuordnung nur über Profil-ID |
| Liefert die Admin-Profilansicht ihren Verlauf über eine Anfrage, die ein eigener Server (mit Schlüssel) aufrufen dürfte? | Historie rückwirkend | Historie beginnt erst mit dem Mitschnitt; Spike in Phase 0, kein Fundament |

## Mapping Trigger → Domain-Ereignis

| Flenski-Trigger | Wirkung im CRM |
|---|---|
| Neues Mitglied / Neuer Kontakt | Kundin anlegen oder aktualisieren (`source = flenski`), Dublettenprüfung per E-Mail |
| Plan zugewiesen | Falls Produkt mit `flenski_plan_id` existiert: Berechtigung anlegen (`source = flenski_plan`) + Kauf-Buchung. Kein Produkt zugeordnet → Hinweis „Plan ohne Produkt" |
| Bestellung abgeschlossen | Preis/`paid_via = app` an passende Berechtigung hängen; sonst Berechtigung anlegen. Doppelanlage mit „Plan zugewiesen" verhindern (gleiche Kundin + Plan innerhalb 10 Min. = ein Kauf) |
| Plan entzogen | Berechtigung **nicht** löschen, nur Hinweis. Guthaben bleibt sichtbar (Plan entzogen ≠ Guthaben verbraucht) |
| Abonnement gekündigt / Zahlung fehlgeschlagen | Signal am Board („Zahlung fehlgeschlagen", „gekündigt") |
| Mitglied gelöscht | Kundin archivieren (nicht löschen, wegen Buchungsnachweis), Flenski-Verknüpfung entfernen |
| Am Event teilgenommen | Stunde anlegen/finden, Anwesenheit `registered` (Abzug erst nach Phase-0-Klärung automatisch); zusätzlich `activity_events` (`event_attended`) |
| Zum Kurs angemeldet / Kurs abgeschlossen / Beitrag erstellt / Kommentar erstellt / Frage gestellt / Datei heruntergeladen / Artikel gelesen | nur `activity_events` (Ereignisart, Zeitpunkt, Titel), Zuordnung über Profil-ID; Doppelzustellung über `dedupe_key` unschädlich |

## Einrichtung pro neuer Flenski-App (Ziel: < 30 Min.)

1. Mandant im CRM anlegen → erhält Slug, Webhook-URL, Secret.
2. Flenski-Pläne auflisten und je einem CRM-Produkt zuordnen (Typ, Einheiten, Gültigkeit, Preis).
3. In Flenski je Trigger eine Automation „Webhook senden" anlegen (URL + Secret), Limits auf „ohne Limit / sofort".
4. In Flenski eine Custom Page „Kundinnen" anlegen, Sichtbarkeit nur Team, Inhalt von `ui/crm.html` mit dem Mandanten-Slug einfügen.
5. Erstimport bestehender Mitglieder + CSV der externen Kundinnen.
