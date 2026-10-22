# Plan Phase 2 – Oberfläche

Stand: 22.10.2026 · Status: **Entscheidungen getroffen, wartet auf Go**
Grundlage: `05-phasen.md` (Phase 2), Entscheidung 0001 (läuft im Flenski-Embed-Widget), CLAUDE.md Regel 6 und 7.

## In einem Satz

Lana öffnet in ihrer App die Seite „Kundinnen“, meldet sich einmal per Code an und kann dann am Handy einchecken, verkaufen, korrigieren und nachschauen, wer wie viel Guthaben hat.

## Technik (bleibt bei den zwei Bausteinen)

- **Eine Datei** `ui/crm.html`: HTML + CSS + JavaScript. Kein Build-Schritt.
- Bibliotheken per CDN mit fester Version: `@supabase/supabase-js` (wie im Phase-0-Test) und **Alpine.js** (macht Listen, Filter und Umschalten mit wenig Code; laut CLAUDE.md erlaubt).
- Alles in `#ecrm-root`, alle Klassen mit `ecrm-`, keine Styles, die auf die Flenski-Seite durchschlagen.
- Oben in der Datei steht nur die Konfiguration: `window.CRM_CONFIG = { tenant: "yoga-by-lana" }` sowie Supabase-Adresse und öffentlicher Schlüssel.
- **Keine Regel doppelt in der Oberfläche:** Guthaben, Abbuchung, Signale usw. kommen fertig aus der Datenbank (Regel 6).

## Bildschirme (mobil zuerst, 375 px, mit einer Hand bedienbar)

Unten eine feste Leiste mit vier Reitern: **Check-in · Kundinnen · Verkauf · Mehr**.

### 1. Anmelden
E-Mail → 6-stelliger Code → fertig. Die Anmeldung bleibt gespeichert (in Phase 0 auf dem iPhone getestet). Ist die Person nicht für diese Mandantin freigeschaltet, erscheint eine freundliche Erklärung.

### 2. Check-in (Startseite, wichtigster Screen)
- Oben: **Stunden von heute** als große Karten. Darunter „Stunde anlegen“ mit Vorschlag aus der letzten Woche („Yoga am Dienstag, 18:30 – wie letzte Woche“ = ein Tap).
- In der Stunde: Liste der Angemeldeten (ab Phase 3 automatisch aus Flenski) plus Suchfeld „Kundin hinzufügen“.
- **Antippen = anwesend.** Die Zeile wird grün und zeigt sofort: „noch 2 von 4 · gültig bis 12.12.“.
- Nochmal antippen bzw. „Rückgängig“ in der Meldung unten = Check-in zurück.
- Ohne passende Karte: Zeile wird orange „ohne Karte“ mit Knopf **„Karte verkaufen“**.
- Wischen bzw. Menü an der Zeile: „abgesagt“ / „nicht erschienen“ (die Stornofrist rechnet die Datenbank).

### 3. Kundinnen
- Suchfeld (Name, E-Mail), darunter Filter-Chips: **Produkt · App/extern · Guthaben 0 / 1 / >1 · läuft ab ≤ 14 Tage · lange nicht da (> X Tage) · Tag · archiviert**.
- Zeile: Name, Guthaben-Chip, letzter Besuch, kleines Zeichen für App-Mitglied bzw. Kind.
- Leerer Zustand: „Noch keine Kundinnen – lege die erste an“ (Import kommt in Phase 4).

### 4. Kundin (Detail)
- Kopf: Name, Kontakt (Telefon/E-Mail antippbar), bei Kindern die Eltern.
- **Karten:** je Karte Restguthaben, Ablauf, Zahlweg. Knopf „Korrektur“ (Plus/Minus + Pflichtgrund).
- **Verlauf:** alle Buchungen mit Datum, Stunde, Grund, wer gebucht hat. Damit ist jede Zahl belegbar.
- **Notiz** mit sichtbarem Hinweis „Bitte keine Gesundheitsangaben“.
- Bearbeiten, Archivieren; **Löschen** nur für owner (mit Rückfrage, anonymisiert).

### 5. Verkauf (max. 3 Taps nach Kundinnenwahl)
Kundin wählen oder neu anlegen → **Produkt** (große Kacheln) → **Zahlweg** (bar, Überweisung, Verein, Gutschein, sonstiges) → fertig. Danach Bestätigung „Anna hat jetzt 4 Besuche · gültig bis 31.01.“.

### 6. Mehr
- **Produkte** (nur owner): anlegen, ändern, deaktivieren. Staff sieht sie nur.
- Abmelden, angemeldet als …, Version.

## Was in der Datenbank noch dazukommt (kleine Ergänzungen, mit Tests)
- `session_roster(stunde)`: Teilnehmerliste einer Stunde inkl. Status und Restguthaben in **einer** Abfrage (schnell am Handy).
- `v_customer_history`: Verlauf je Kundin mit Stundentitel und Produktname.
- `v_customer_overview` bekommt die Produktnamen der aktiven Karten (für den Filter „Produkt“).
- `create_session_like_last_week(...)`: Stunde aus der Vorwoche übernehmen.

## Testen
- Die Datenbank-Teile wie bisher mit automatischen Tests.
- Die Oberfläche teste ich in der Vorschau neben dem Chat mit der **Demo-Mandantin** auf 375 px Breite. Für die Anmeldung gibst **du** einmal deine E-Mail und den Code in der Vorschau ein. Ich tippe keine Zugangsdaten ein, danach klicke ich mich durch alle Wege.
- Abnahme laut 05 bei dir am iPhone: 12 Check-ins unter 60 Sekunden, Barverkauf unter 20 Sekunden.

## Reihenfolge (je Schritt ein Commit)
1. Datenbank-Ergänzungen + Tests
2. Grundgerüst: Anmeldung, Leiste, Design
3. Check-in
4. Kundinnen + Detail + Korrektur
5. Verkauf
6. Produkte, Feinschliff, Test am iPhone in Flenski

## Entscheidungen (von Marcel, 22.10.2026)
| Frage | Entscheidung | Folge im Bau |
|---|---|---|
| Farbschema | **Hell, passend zu Flenski** | weiße Karten, dunkle Schrift, Akzent #38725b, Warnung orange; kein Dunkelmodus im Widget |
| Stunden anlegen | **Vorschlag aus der Vorwoche** + kurzes Formular | Funktion `create_session_like_last_week` |
| Rechte Staff | **Verkaufen + einchecken**, Korrektur und Löschen nur owner | `correct()` wird auf owner beschränkt (+ Test) |
