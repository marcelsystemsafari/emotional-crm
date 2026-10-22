# 06 – Was noch fehlt (Checkliste für Marcel)

Abhaken, sobald erledigt. Ergebnisse in `inbox/` ablegen.

## A. Entscheidungen (blockieren das Konzept)

- [ ] **Ablauf einer Stunde bei Lana:** Melden sich Teilnehmerinnen vorher an (Flenski-Event, anderes Tool) oder kommen sie einfach? → bestimmt, ob der Check-in aus Anmeldungen vorbefüllt wird.
- [ ] **Bindungslogik bestätigt:** CRM ist Teil des Monatspakets, bei Kündigung 30 Tage Lesen + Export, dann Löschung (siehe 01, Abschnitt 6).
- [ ] **Stornoregel Default:** Bis wie viele Stunden vorher kostenlos absagen? Was passiert bei No-Show?
- [ ] **Ruhemodus bei Kündigung:** Daten bis zu 12 Monate aufbewahren, wenn die Kundin das bei Kündigung ausdrücklich wählt (siehe 01, Abschnitt 6)?
- [ ] **Produktname** (Arbeitstitel „Emotional CRM").
- [ ] **Beitragsinhalte im Rohspeicher:** Flenski schickt bei Beiträgen und Kommentaren den kompletten Text und Name/E-Mail der angesprochenen Person mit. Vorschlag: Sobald die Signatur prüfbar ist, prüft der Empfänger sie direkt beim Eingang und speichert danach nur noch eine bereinigte Fassung ohne Texte. Bis dahin liegen die Texte im Rohspeicher (nur Server-Zugriff).
- [ ] **Schwellen vereinheitlichen:** Signal „Droht abzuspringen" (21 Tage + Guthaben) und Aktivitätsstatus „Kühlt ab" (Standard 15–30 Tage) dürfen sich nicht widersprechen. Vorschlag: Status 14/30 Tage, Signal bleibt zusätzlich an Guthaben > 0 gekoppelt. Lana soll im Gespräch sagen, ab wann sie bei einer Kundin sagt „die habe ich lange nicht gesehen".

## B. Von Flenski / aus der Flenski-Oberfläche

- [x] Webhook-Payloads je Trigger über „Testen“ (22.10.2026, 16 Trigger, `inbox/webhooks/`). „Beitrag in der Community“ und „Frage gestellt“ gibt es in Lanas App nicht.
- [ ] **Echte** Ereignisse auslösen (Testmitglied anlegen, Plan zuweisen/entziehen, Event-Teilnahme, Kurs, Beitrag). Bisher sind alles Beispieldaten vom Testen-Knopf.
- [ ] **Signatur-Schlüssel:** Flenski signiert mit `sha256=<hex>` und einem eigenen Schlüssel. Wo zeigt Flenski ihn an (Automation, App-Einstellungen, Integrationen)? Screenshot mit geschwärztem Schlüssel; den Schlüssel selbst trägt Marcel als `FLENSKI_WEBHOOK_SECRET` in `.env.local` ein.
- [ ] Support-Anfrage: REST-API für eigene Server? Plan per API entziehen? Mitgliedsdaten in Custom Pages? Wiederholte Zustellung bei Fehler? (Textvorschlag unten)
- [ ] Test: `ui/phase0-test.html` in eine Test-Custom-Page einfügen und Ergebnis auf Handy + Desktop als Screenshot in `inbox/screenshots/` legen
- [ ] **Aktivität:** Als Admin ein Mitglied → Profil ansehen → Aktivität öffnen, F12 → Reiter „Netzwerk" → Seite neu laden und Screenshot der geladenen Anfrage (nur Name und Adresse) in `inbox/screenshots/` legen. Ergebnis entscheidet, ob es eine Historie gibt oder ob sie erst mit dem Mitschnitt beginnt.
- [x] **Aktivität:** Automationen für die Aktivitäts-Trigger (angelegt 22.10.2026) (Liste in `08-aktivitaet.md`, Abschnitt 6) anlegen und auf den Empfänger zeigen lassen, so früh wie möglich.

## C. Von Lana (erste Mandantin)

- [ ] Liste externer Kundinnen (Excel/CSV: Name, E-Mail oder Telefon, aktuelles Produkt, Restguthaben, Ablauf)
- [ ] Regeln je Produkt → in `inbox/tenants/yoga-by-lana.json` eintragen
- [ ] Kinderyoga: Wer ist Ansprechpartner – Eltern? Welche Daten will sie wirklich festhalten?

## D. Konten und Zugänge (Marcel)

- [x] **Supabase-Konto** vorhanden (Marcel, 21.10.2026). Projekt `emotional-crm` (Irland) ist verknüpft; die CLI arbeitet mit Zugangsschlüssel aus `.env.local`, weil `supabase login` an Norton scheitert.
- [x] `.env.local` lokal anlegen (Vorlage `.env.example`, Werte aus Supabase → Project Settings → API), **nie weitergeben**
- [x] **GitHub-Konto** vorhanden (`marcelsystemsafari`), mit Claude verbunden. Dient als Sicherungskopie; Claude Code lädt nach jedem Arbeitstag hoch.
- [x] Repo `marcelsystemsafari/emotional-crm` angelegt und befüllt. Lokaler Ordner ist seit 21.10.2026 mit dem Repo verbunden. Auf dem eigenen Rechner: einmal bei GitHub anmelden (Browser-Login beim ersten Push).
- ~~Vercel~~ entfällt (schlanke Variante, siehe 02)

## E. Rechtliches (vor dem ersten echten Mandanten)

- [ ] AVV-Vorlage (Systemsafari als Auftragsverarbeiter der Lehrerin)
- [ ] Unterauftragsverarbeiter-Liste: Supabase
- [ ] Datenschutzhinweis-Baustein, den die Lehrerin in ihre Datenschutzerklärung übernimmt (inkl. Satz zur Auswertung der Aktivität von Mitgliedern, siehe 08, Abschnitt 7)

---

### Textvorschlag Support-Anfrage an Flenski

> Hallo Flenski-Team,
> ich baue für meine Kundinnen eine Ergänzung, die Guthaben und Anwesenheit verwaltet und über eure Automationen („Webhook senden") angebunden ist. Dazu vier Fragen:
> 1. Gibt es eine REST-API mit API-Schlüssel, die mein eigener Server aufrufen kann (Mitglieder und Pläne lesen)?
> 2. Kann man über diese API einem Mitglied einen Plan zuweisen oder entziehen?
> 3. Stehen in einer Custom Page Informationen zum eingeloggten Mitglied zur Verfügung (z. B. Profil-ID als Variable)?
> 4. Wie wird X-Flenski-Signature berechnet, und werden Webhooks bei einer Fehlerantwort erneut zugestellt?
> 5. Gibt es einen Trigger oder eine Schnittstelle für den Aktivitätsverlauf eines Mitglieds (so wie ihn Admins im Profil unter „Aktivität" sehen, z. B. „Kurs gestartet")?
> Danke und viele Grüße, Marcel (Systemsafari)
