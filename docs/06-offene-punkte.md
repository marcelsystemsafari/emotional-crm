# 06 – Was noch fehlt (Checkliste für Marcel)

Abhaken, sobald erledigt. Ergebnisse in `inbox/` ablegen.

## A. Entscheidungen (blockieren das Konzept)

- [ ] **Ablauf einer Stunde bei Lana:** Melden sich Teilnehmerinnen vorher an (Flenski-Event, anderes Tool) oder kommen sie einfach? → bestimmt, ob der Check-in aus Anmeldungen vorbefüllt wird.
- [ ] **Bindungslogik bestätigt:** CRM ist Teil des Monatspakets, bei Kündigung 30 Tage Lesen + Export, dann Löschung (siehe 01, Abschnitt 6).
- [ ] **Stornoregel Default:** Bis wie viele Stunden vorher kostenlos absagen? Was passiert bei No-Show?
- [ ] **Ruhemodus bei Kündigung:** Daten bis zu 12 Monate aufbewahren, wenn die Kundin das bei Kündigung ausdrücklich wählt (siehe 01, Abschnitt 6)?
- [ ] **Produktname** (Arbeitstitel „Emotional CRM").

## B. Von Flenski / aus der Flenski-Oberfläche

- [ ] Echte Webhook-Payloads je Trigger (Phase 0, Anleitung in `inbox/README.md`)
- [ ] Wie das Signatur-Secret gesetzt/angezeigt wird (Screenshot)
- [ ] Support-Anfrage: REST-API für eigene Server? Plan per API entziehen? Mitgliedsdaten in Custom Pages? Wiederholte Zustellung bei Fehler? (Textvorschlag unten)
- [ ] Test: `ui/phase0-test.html` in eine Test-Custom-Page einfügen und Ergebnis auf Handy + Desktop als Screenshot in `inbox/screenshots/` legen

## C. Von Lana (erste Mandantin)

- [ ] Liste externer Kundinnen (Excel/CSV: Name, E-Mail oder Telefon, aktuelles Produkt, Restguthaben, Ablauf)
- [ ] Regeln je Produkt → in `inbox/tenants/yoga-by-lana.json` eintragen
- [ ] Kinderyoga: Wer ist Ansprechpartner – Eltern? Welche Daten will sie wirklich festhalten?

## D. Konten und Zugänge (Marcel)

- [x] **Supabase-Konto** vorhanden (Marcel, 21.10.2026). Offen: Claude Code per `supabase login` verbinden und Projekt verknüpfen.
- [ ] `.env.local` lokal anlegen (Vorlage `.env.example`, Werte aus Supabase → Project Settings → API), **nie weitergeben**
- [x] **GitHub-Konto** vorhanden (`marcelsystemsafari`), mit Claude verbunden. Dient als Sicherungskopie; Claude Code lädt nach jedem Arbeitstag hoch.
- [x] Repo `marcelsystemsafari/emotional-crm` angelegt und befüllt. Auf dem eigenen Rechner: einmal bei GitHub anmelden (Browser-Login beim ersten Push oder `gh auth login`).
- ~~Vercel~~ entfällt (schlanke Variante, siehe 02)

## E. Rechtliches (vor dem ersten echten Mandanten)

- [ ] AVV-Vorlage (Systemsafari als Auftragsverarbeiter der Lehrerin)
- [ ] Unterauftragsverarbeiter-Liste: Supabase
- [ ] Datenschutzhinweis-Baustein, den die Lehrerin in ihre Datenschutzerklärung übernimmt

---

### Textvorschlag Support-Anfrage an Flenski

> Hallo Flenski-Team,
> ich baue für meine Kundinnen eine Ergänzung, die Guthaben und Anwesenheit verwaltet und über eure Automationen („Webhook senden") angebunden ist. Dazu vier Fragen:
> 1. Gibt es eine REST-API mit API-Schlüssel, die mein eigener Server aufrufen kann (Mitglieder und Pläne lesen)?
> 2. Kann man über diese API einem Mitglied einen Plan zuweisen oder entziehen?
> 3. Stehen in einer Custom Page Informationen zum eingeloggten Mitglied zur Verfügung (z. B. Profil-ID als Variable)?
> 4. Wie wird X-Flenski-Signature berechnet, und werden Webhooks bei einer Fehlerantwort erneut zugestellt?
> Danke und viele Grüße, Marcel (Systemsafari)
