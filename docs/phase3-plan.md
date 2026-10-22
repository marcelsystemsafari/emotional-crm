# Plan Phase 3 (neu) – Automatisch aus der App + neue Oberfläche

Stand: 22.10.2026 · Status: **Entwurf, wartet auf Marcels Go**
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

## Schritt 2 – Erstabgleich und Nachverarbeitung
- Bestehende Mitglieder, Pläne und Events aus Lanas App einmalig übernehmen (über Marcels Flenski-Verbindung).
- Den bisherigen Mitschnitt (seit 22.10.) nachträglich verarbeiten – z. B. Martinas „Artikel gelesen“.

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
