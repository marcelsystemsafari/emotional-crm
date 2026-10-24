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

**Custom Pages** haben ein Feld für eigenen Code (`isCustomCodeEnabled`, `header`/`footer` als HTML). Eigenes JavaScript läuft aber nur im **Embed-Widget** der Seite, nicht im Fußzeilen-Feld (getestet 22.10.2026).

**Aktivität (Stand 21.10.2026):** Im Flenski-Admin zeigt „Mitglied → Profil ansehen → Aktivität" einen Verlauf je Mitglied (z. B. „Mai: Kurs gestartet · geführte Audioentspannung · Event registriert"). Dieser Verlauf ist über die abgefragte Schnittstelle **nicht** abrufbar; sie liefert pro Mitglied nur `lastLoginAt`. Weitere für Aktivität relevante Trigger laut Dropdown: Zum Kurs angemeldet, Kurs abgeschlossen, Beitrag in Community/Gruppe erstellt, Kommentar erstellt, Frage in der Fragebox gestellt, Artikel gelesen, Datei heruntergeladen, Punkte vergeben.

## Angenommen (muss in Phase 0 bestätigt werden)

- Signatur ist HMAC-SHA256 über den Rohbody mit einem Secret, das Flenski anzeigt oder das wir setzen.
- Webhooks enthalten die Profil-ID des Mitglieds und bei Plänen die Plan-ID.
- ~~Eigenes JavaScript in Custom Pages läuft direkt in der Seite~~ → **bestätigt** im Embed-Widget (Entscheidung 0001).

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

## Ergebnisse Phase 0 (Stand 22.10.2026, Webhook-Mitschnitt)

Quelle: 19 Webhooks über den Knopf „Testen“ in Lanas App, anonymisiert in `inbox/webhooks/`. **Alles Beispieldaten** („Sample plan“, „SAMPLE-ORDER-1“), das Mitglied ist das Profil der testenden Person. Echte Ereignisse stehen noch aus.

**Format (gesichert):**
- JSON-Body, Header `X-Flenski-Signature: sha256=<hex>`, `User-Agent: Symfony HttpClient (Curl)`.
- Jeder Body hat `envelope` mit `appId`, `appName`, `projectId`, `event` (Ereignisname) und `occurredAt`. Fast jeder Body hat `member` mit `id` (= Profil-ID), `email`, `firstName`, `lastName`, `fullName`, `tags`, `plans`, `isMemberOfTeam` u. a.
- Ein Knopfdruck auf „Testen“ ist am Header `baggage` (`sentry-transaction=…app_automation_webhook_test`) erkennbar. Das ist kein offizielles Merkmal, also nicht als Logik verwenden.

| Trigger (unsere URL) | `envelope.event` | Wichtige Felder außer `member` |
|---|---|---|
| neues-mitglied | `new_member` | – |
| neuer-kontakt | `lead_created` | `contact.id`, `fullName`, `email`, `phone`, `message` (kein `member`) |
| plan-zugewiesen | `member_plan_assigned` | `plan.id`, `plan.name`, `source` (z. B. `payment`), `expireAt`, `assignedBy` |
| plan-entzogen | `member_plan_removed` | `plan.id`, `reason` (z. B. `refunded`), `removedBy` |
| mitglied-geloescht | `member_deleted` | `reason`, `deletedAt` |
| bestellung-abgeschlossen | `order_completed` | `order` (`id`, `orderId`, `amount`, `currency`, `paySystemType`), `plans[]`, `subscription` |
| zahlung-fehlgeschlagen | `payment_failed` | `order`, `subscription`, `attemptNumber`, `failureReason` |
| abonnement-gekuendigt | `subscription_cancelled` | `plans[]`, `subscription`, `cancelledAt`, `lastPaidDay` |
| am-event-teilgenommen | `event_attended` | `event` (`id`, `title`, `startAt`, `endAt`), `category`, `source` (`signup`), `attendedAt` |
| event-beginnt-bald | `event_starts_soon` | `event`, `category`, `minutesBefore` |
| zum-kurs-angemeldet | `course_enrolled` | `course` (`id`, `title`), `accessSource`, `enrolledAt` |
| kurs-abgeschlossen | `course_completed` | `course`, `startedAt`, `completedAt`, `completedLessonsCount` |
| beitrag-gruppe-erstellt | `groups_post_created` | `post` (`id`, **`text` = kompletter Beitrag**), `space.name` |
| kommentar-erstellt | `comment_created` | `comment` (**`text`**), `target` (`title` = Textanfang des Beitrags), **`targetAuthor`** (Name + E-Mail einer zweiten Person) |
| datei-heruntergeladen | `file_downloaded` | `download` (`id`, `title`), `category`, `file` |
| artikel-gelesen | `article_viewed` | `article` (`id`, `title`), `category` |

Nicht in Lanas App verfügbar und deshalb nicht angelegt: „Beitrag in der Community erstellt“, „Frage in der Fragebox gestellt“.

**Damit beantwortet:**
- Webhooks enthalten die Profil-ID (`member.id`) und bei Plänen die Plan-ID (`plan.id`). ✅
- „Bestellung abgeschlossen“ enthält Betrag, Währung, Pläne und Mitglied. ✅ Automatischer Kauf-Eintrag ist möglich.
- Aktivitäts-Webhooks enthalten Profil-ID **und** Titel. ✅
- Fachliche Ereignis-ID für die Doppelerkennung: `envelope.event` + `envelope.occurredAt` + `member.id` + ID des Objekts (Plan, Kurs, Event …). Wird in Phase 3 umgesetzt. Bis dahin gilt der SHA-256 des Bodys.

**Weiter offen:**
- **Signatur (geklärt 22.10.2026):** HMAC-SHA256 über den Rohbody, `sha256=<hex>`, **ein Schlüssel pro Automation**, nur einmal sichtbar. „Testen“ nutzt einen Einmalschlüssel. Umsetzung: Entscheidung 0004. Mit echter Nachricht bestätigt (22.10.2026).
- **Beobachtung:** „Artikel gelesen“ kam pro Mitglied und Artikel nur beim ersten Öffnen. Erneutes Öffnen, ein erneuter Download des „Demo download“ und ein Sperrbildschirm-Klick lösten keine Nachricht aus. Ob das an „nur einmal pro Mitglied“ oder an der Auswahl in der Automation liegt, ist noch offen.
- **„Am Event teilgenommen“ = Anmeldung** (geklärt 22.10.2026: `source: signup`, und Lanas Serien ab Januar 2027 haben bereits Teilnehmende). Umsetzung: `registered`, nach Terminbeginn automatisch `present` + Abbuchung (`finalize_past_sessions`, alle 15 Min.).
- Beispieldaten ersetzen keine echten Ereignisse: Plan-IDs, Beträge und `source` müssen an echten Vorgängen bestätigt werden.
- **Datenschutz:** Beitrags- und Kommentartexte sowie `targetAuthor` kommen mit. Regel 10 (CLAUDE.md) verbietet, Inhalte in `activity_events` zu übernehmen. Im Rohspeicher `webhook_events` liegen sie aber derzeit vollständig. Entscheidung offen (06, Abschnitt A).

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
3. In Flenski je Trigger eine Automation „Webhook senden" anlegen (URL mit `?tenant=<slug>&trigger=<name>`), Limits auf „ohne Limit / sofort". Den angezeigten Schlüssel **sofort** als `FLENSKI_SECRET_<TRIGGER>` in `.env.local` sichern, danach `node scripts/upload-webhook-secrets.mjs <slug>` (Entscheidung 0004).
4. In Flenski eine Custom Page „Kundinnen" anlegen, Sichtbarkeit nur Team, ein **Embed-Widget** einfügen und darin den Inhalt von `ui/crm.html` mit dem Mandanten-Slug einfügen.
5. Erstimport bestehender Mitglieder + CSV der externen Kundinnen.
6. Lehrerin einladen: `node scripts/invite-user.mjs <email> <slug> owner` (Registrierung ist geschlossen).


## Flenski-Schnittstelle mit API-Schlüssel (ermittelt 23.10.2026)

- Basis: `https://app.flenski.io/api/v1`, Header `X-API-KEY: <Schlüssel>` (Bearer wird abgelehnt). Schlüssel je App, liegt in `tenant_secrets` (nur Server).
- Erreichbar mit dem Schlüssel: `/apps/{appId}/events?page=&limit=` (auch vergangene Termine), `/apps/{appId}/profiles`. Pläne vermutlich ebenfalls unter `/apps/{appId}/…`.
- **Nicht** erreichbar mit dem Schlüssel: `/events/{id}/attendees` (401, braucht eingeloggte Person; Make nutzte dafür seine eigene Flenski-Verbindung).
- Je Termin liefert die Liste `attendedCount` (Anzahl Angemeldete) und `lastAttended` (Namen der zuletzt Angemeldeten, nur Profil-ID genutzt). Ob `lastAttended` bei großen Kursen gekürzt ist, ist unbekannt – der Abgleich behandelt das vorsichtig (Entscheidung 0006, Migration `20261023100000_flenski_abgleich`).
- Teilnehmende sind auch Team-Mitglieder und Profile mit Ausschluss-Tag; sie zählen in `attendedCount` mit, werden im CRM aber nicht als Kundin geführt.

- **Plan entziehen / zuweisen** (Pfade ermittelt 23.10.2026, nur per GET abgetastet → 405 "nur POST"): `POST /apps/{appId}/profiles/plans/revoke` bzw. `POST /apps/{appId}/profiles/plans`. Felder vermutlich wie im Make-Modul `revokePlansProfile`: `{ "email": "...", "planIds": ["..."] }` – **Test 23.10.2026 (Marcels Testkonto, freigegeben): 401 „Full authentication is required“.** Der API-Schlüssel darf Pläne nicht entziehen/zuweisen (wie bei `/events/{id}/attendees`). Make nutzte eine andere Flenski-Verbindung. Offen: Schlüssel mit Schreibrechten oder Freigabe durch Flenski.
- **Lösung (23.10.2026, Entscheidung 0007):** Entzug, Zuweisung und vollständige Teilnehmerliste laufen über das Make-Szenario „ECRM: Flenski-Aktionen“. Zuweisen: `POST /apps/{appId}/profiles/plans` mit `{"email","planIds"}` funktioniert (Antwort `{"status":"ok"}`). Teilnehmerliste: `GET /events/{id}/attendees` → `data[].id` = Profil-ID.

## Korrektur 24.10.2026: Der API-Schlüssel wurde nie erkannt
- Lanas App ist auf „öffentlich“ gestellt. Termine und Mitglieder (öffentliche Felder) kommen dort **auch ohne Schlüssel** – der Abgleich für Lana lief bisher über diese öffentliche Ansicht, nicht über den Schlüssel.
- Ninas App ist „nur mit Anmeldung“: Termine → 401, Mitglieder nur öffentliche Felder (Name, Foto, Tags; keine ID/E-Mail/Pläne).
- Getestet (nur lesend) ohne Erfolg: `X-API-KEY`, `Authorization` (roh, Bearer, Token, ApiKey, Basic), `X-Api-Token`, `X-Access-Token`, `Api-Key`, Query-Parameter (`apiKey`, `api_key`, `token`, `access_token`), Tausch-Endpunkte `auth/*`. `Bearer <Schlüssel>` → 401 „The resource server rejected the request“.
- Marcels Make-Verbindung „Flenski“ (nur mit diesem Schlüssel angelegt) kommt an alles. **Offen: Wie schickt die Make-App den Schlüssel mit?** → Flenski-Support fragen bzw. den Verbindungsdialog in Make ansehen.
- Folge: Für Apps mit Anmeldung funktioniert der automatische Abgleich erst, wenn das geklärt ist. Plan-Entzug/-Zuweisung lief ohnehin über Make.
