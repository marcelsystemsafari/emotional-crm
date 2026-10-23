# Plan Phase 3 (neu) – Automatisch aus der App + neue Oberfläche

Stand: 22.10.2026 · Status: **gebaut, wartet auf Test in Flenski + Abnahme** – Schritte 1–4 fertig (22.10.2026)
Grundlage: Entscheidung 0005, echte Payloads in `inbox/webhooks/`, Modul Aktivität (`08-aktivitaet.md`).

## Ziel in einem Satz

Lana öffnet „Kundinnen“ in ihrer App und sieht ohne jede Eingabe alle ihre Menschen: wer dabei ist, wer abkühlt, wer neu ist, was gerade passiert – und bei jeder Person den ganzen Verlauf aus App und Kursen.

## Schritt 1 – Webhooks verarbeiten (Datenbank + Edge Function, mit Tests)

Verarbeitet werden nur Nachrichten mit gültiger Signatur. Testnachrichten bleiben liegen. Jede Nachricht wirkt genau einmal.

| Flenski-Ereignis | Wirkung im CRM |
|---|---|
| Neues Mitglied, Neuer Kontakt | Person anlegen/aktualisieren (Profil-ID), Hinweis bei möglicher Dublette per E-Mail |
| Plan zugewiesen, Bestellung abgeschlossen | Produkt aus dem Plan (automatisch angelegt) + Karte/Kauf bei der Person; Betrag aus der Bestellung |
| Plan entzogen, Abo gekündigt, Zahlung fehlgeschlagen | Hinweis bei der Person (Übersicht „kümmern“) |
| Am Event teilgenommen | Kurs/Termin automatisch anlegen, Teilnahme = Besuch, Abbuchung von passender Karte |
| Kurs angemeldet/abgeschlossen, Beitrag, Kommentar, Artikel gelesen, Datei, Sperrbildschirm-Klick | Aktivität (Art, Zeit, Titel – nie Inhalte) |
| Mitglied gelöscht | Person archivieren |

Dazu: Beitrags-/Kommentartexte werden nach der Prüfung aus dem Rohspeicher entfernt (offener Punkt Datenschutz, 06).

**Stand Schritt 1 (22.10.2026):** Verarbeitung als SQL-Funktion `process_webhook_event` (+ `process_pending_webhooks`, `setup_product`), Tabelle `customer_notices`, Edge Function verarbeitet sofort. 34 Tests mit den echten Beispiel-Payloads (`scripts/build-webhook-tests.mjs`), insgesamt 146 grün. Mitschnitt nachverarbeitet: Martina Böttcher (Artikel gelesen) und ein neues Mitglied stehen automatisch im CRM. Nicht verarbeitet: eine echte Nachricht vom 22.10. 10:53 der alten, gelöschten Automation (Signatur nicht prüfbar).

Festgelegt beim Bau: Team-/Admin-Profile werden keine Kundinnen. „Event beginnt bald“ gilt als Anmeldung. Neue Pläne werden als „noch einzurichten“ angelegt (zählen Teilnahmen, buchen erst nach `setup_product` ab, dann rückwirkend).

## Schritt 2 – Erstabgleich und Nachverarbeitung
- Bestehende Mitglieder, Pläne und Events aus Lanas App einmalig übernehmen (über Marcels Flenski-Verbindung).
- Den bisherigen Mitschnitt (seit 22.10.) nachträglich verarbeiten – z. B. Martinas „Artikel gelesen“.

**Stand Schritt 2 (22.10.2026):** Erstabgleich Lana über `import_flenski_snapshot`: 2 Personen (Martina Böttcher, Sarah Oberste), 3 Pläne als Produkte „noch einzurichten“, 5 Kursserien = 44 Termine (Jan.–März 2027), 1 Anmeldung. Nicht übernommen: Swetlana (Team) und Maria Musterfrau (Tag „Yogalehrerin“, `ausschluss_tags`).

**Wichtige Erkenntnis:** Flenskis „Am Event teilgenommen“ kommt schon bei der **Anmeldung** (Lanas Serien beginnen erst im Januar 2027 und haben bereits Teilnehmende). Deshalb: Anmeldung = „angemeldet“; nach Terminbeginn macht `finalize_past_sessions()` (alle 15 Minuten) daraus „da“ + Abbuchung. Offen: Meldet Flenski Abmeldungen? Falls nicht, würde eine abgemeldete Person trotzdem abgebucht (06).

## Schritt 3 – Aktivitätsstatus
- Ansicht `v_customer_engagement`: **Neu · Dabei · Kühlt ab · Eingeschlafen** aus App-Aktivität **und** Kursbesuchen (08).
- 8-Wochen-Verlauf je Person, „gerade passiert“-Liste für die Übersicht.

## Schritt 4 – Neue Oberfläche (ersetzt die Phase-2-Oberfläche)
- **Übersicht:** Begrüßung, 4 Kennzahlen, „Um diese Menschen kümmerst du dich jetzt“ (mit Ein-Tap-Nachricht), „Gerade passiert“.
- **Menschen:** Suche, Filter nach Status, Liste mit Avatar-Initialen, Statusfarbe, Mini-Verlauf. Detail: Kennzahlen, 8-Wochen-Balken, kompletter Verlauf aus App + Kursen + Karten; versteckt: „Zahlung von Hand nachtragen“, „Korrektur“.
- **Kurse:** Flenski-Termine mit Teilnehmenden und Auslastung.
- **Einstellungen** (klein, über ein Symbol): Pläne einmalig einrichten (Einheiten, Gültigkeit), Team, Abmelden.
- Design nach dem Entwurf: hell, ruhig, viel Weißraum, Initialen-Avatare, Statusfarben Grün/Amber/Türkis, Lanas Akzent #38725b.

## Was bleibt
Datenbank-Regeln aus Phase 1 (Buchungsprotokoll, FEFO, Storno, Signale) – sie werden jetzt automatisch aufgerufen.

## Abnahme
- Ein neues Testmitglied in Lanas App erscheint ohne Zutun im CRM.
- „Am Event teilgenommen“ erscheint als Besuch im Verlauf und bucht von der Karte ab (sobald der Plan eingerichtet ist).
- Martinas Artikel-Lesen steht in ihrem Verlauf, ihr Status stimmt.
- Lana sagt beim Blick auf die Übersicht: „Ja, so sehe ich meine Leute.“

## Stand Schritt 3 + 4 (22.10.2026)
- Aktivitätsstatus `v_customer_engagement`, Zeitleiste `activity_feed`, Kümmern-Liste `care_list` (inkl. „neu in der App – willkommen heißen“), Beitrittsdatum aus Flenski. 175 Tests grün.
- Neue Oberfläche `ui/crm.html`: Übersicht · Menschen · Kurse · Einstellungen (Zahnrad). Mit Lanas echten Daten in der Vorschau geprüft (Martina, Sarah, 44 Termine, 3 Pläne zum Einrichten); Schreibwege (Zahlung von Hand) in der Demo geprüft, Buchungen gezählt.
- Gefunden und behoben: Neue Mitglieder fehlten in der Kümmern-Liste; Guthaben zeigte „Block“ bei nicht eingerichtetem Plan; E-Mail-Betreff passte nicht zum Anlass; Demo-Personen waren alle „neu“ (Beitrittsdatum).
- Offen: Lanas Pläne einrichten (macht Lana), Test in Flenski am iPhone, Abnahme.


## Oberfläche v2 (22.10.2026)

Nach Marcels Feedback: hochwertiger (Glas- und Glanzoptik, eigene beige Fläche mit gleichmäßigem Innenabstand), selbsterklärend (Erklärtexte unter jeder Kachel), Knopf „Begrüßen/Schreiben“ öffnet das Flenski-Profil (`settings.profil_url`, die Chat-ID lässt sich nicht ableiten), „Zahlung von Hand“ entfernt, Kurse-Menü als Knöpfe statt Ausklappmenü, Reiter „Angebote“ mit Chips zum Verbinden der Flenski-Pläne und Erklärung der Kopplung, Kurse nur echte Flenski-Termine (Migration 240000), Profilfotos (Migration 250000).


## Automatischer Teilnehmer-Abgleich (23.10.2026, Entscheidung 0006)
Edge Function `flenski-sync` (alle 5 Min. per pg_cron + pg_net) → `sync_flenski_events`: Termine anlegen, Anmeldungen live angleichen (Flenski gewinnt), 5 Min. nach Beginn abschließen (auf der Liste = war da + Abzug, abgemeldet = kein Abzug, gekürzte Liste = „Teilnahme unklar“). Ohne Stand von Kursbeginn wird nichts abgebucht; nach 24 h „Abgleich fehlt“. Lehrerin: „Prüfen“ (War da / War nicht da) und „Kulanz“ in der Kurs-Ansicht (`set_attendance`). Einrichten je Mandantin: `node scripts/setup-flenski-sync.mjs <slug> <app-id>`. Tests: `phase3_04_flenski_abgleich` (23).

**Nachtrag 23.10.2026 (Marcel: nicht zu viele Abfragen):** pg_cron prüft alle 5 Minuten nur in der Datenbank (`flenski_faellige_mandanten`), Flenski wird nur gefragt, wenn ein Kurs in den nächsten 20 Minuten beginnt bzw. vor höchstens 10 Minuten begonnen hat, oder der letzte Abgleich über eine Stunde her ist. Etwa 24 Abfragen am Tag plus etwa 7 je Kurs. Oberfläche: „Dabei“ heißt jetzt „Aktiv“; Übersicht ohne doppelte Kacheln (Kurzinfo im grünen Feld, Karte „Deine Menschen“ mit Verteilungsbalken).

## Automatischer Plan-Entzug (23.10.2026)
Leere/abgelaufene Karte mit Flenski-Plan → Hinweis „plan_entziehen“ → beim nächsten fälligen Abgleich entzieht `flenski-sync` den Plan (`flenski_offene_entzuege`, `flenski_entzug_ergebnis`). Nicht bei neuer aktiver Karte desselben Angebots; Rückmeldung „Plan entzogen“ danach still erledigt; entzieht die Lehrerin selbst, erledigt sich ihr Hinweis. 3 Fehlversuche → bleibt als Hinweis. Schalter je Mandantin: `settings.plan_entzug_automatisch` (Lana: aus bis zum echten Test). Tests: `phase3_05_plan_entzug` (15).
Plan-Rückgabe bei Wiederauffüllen (+1) gebaut (`flenski_offene_rueckgaben`, keine Doppelkarte durch die Rückmeldung „Plan zugewiesen“). Echter Test 23.10.2026: Flenski lehnt Entzug mit dem API-Schlüssel ab (401) – Funktion bleibt aus, bis ein Zugang mit Schreibrechten da ist.

## Neue Pläne und Ladeanimation (23.10.2026)
Neue Flenski-Pläne erscheinen automatisch unter „Angebote“ als „noch nicht verbunden“: Make-Aktion „plans“ (Projekt-Planliste, gefiltert auf die App), einmal am Tag und sofort auf Knopfdruck (`request_plan_sync` → `flenski_plaene_faellig` → `sync_flenski_plans`). Tests `phase3_06_plaene` (12). Oberfläche: Skelett-Ladeanimation statt leerer Fläche; Rechte und Daten werden gleichzeitig geladen.
