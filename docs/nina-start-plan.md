# Plan: Emotional CRM für Yogini Nina

Stand 23.10.2026 · Entwurf zur Abstimmung mit Marcel. Nina bekommt das CRM ein Jahr kostenlos, danach Abo.

## Ausgangslage (gelesen aus Marcels Make, nichts verändert)
- Ninas App „yogini.nina“ (App-ID `e457ef92-…`) liegt in Marcels Flenski-Projekt. Marcels Make-Verbindung sieht sie → **Claude muss nicht in Ninas App**.
- **8er-Karten laufen live über Make:**
  - Kauf über Stripe/systeme.io (SZ1) bzw. von Hand über eine Google-Tabelle (Sz4) → Datenspeicher „Flenski_8er_Karten Yogini.Nina“ (Token, E-Mail, „Noch übrig“), Plan „YN 8er Karte“ in Flenski, QR-Code per Flenski-Chat.
  - **QR-Code** = Link auf einen Make-Webhook mit persönlichem Token. Beim Scannen zieht Make einen Besuch ab und zeigt „Check-in erfolgreich – noch X von 8“. Bei 2 Rest: Chat-Nachricht. Bei 0: E-Mail + Plan-Entzug (SZ3).
  - Online-Events: Make zieht zweimal täglich Credits für Event-Teilnahmen ab.
- Bestand heute: 9 aktive Karten (davon 1 Testkarte von Marcel), Reste 1–8, letzte Check-ins am 22.10.

## Ziel
Alles, was Make heute für die Karten tut, macht das CRM – sichtbar für Nina in ihrem CRM. Make bleibt nur Brücke für Flenski-Aktionen (Plan entziehen/zuweisen, Chat-Nachricht).

## Schritte

### A. Vorbereitung (stört Ninas Alltag nicht)
1. **Mandantin anlegen** (Claude): `yogini-nina`, Status Testphase mit Enddatum (+1 Jahr), Logo, Profil-Link (`https://yogini.nina.systemsafari.de/app/m/{id}/`), Hintergrund.
2. **API-Schlüssel** in Ninas App erzeugen (Marcel) → `setup-flenski-sync.mjs` (nur lesend).
3. **Erstabgleich** (Claude): Mitglieder, Termine, Pläne. Angebote verbinden: „YN 8er Karte“ = 8 Besuche, Mitgliedschaften = ohne Zählen.
4. **Make-Szenario kopieren** für Ninas App (Claude), `setup-make.mjs`.
5. **Automationen** in Ninas Flenski anlegen (Marcel, ca. 30 Min.) – zusätzlich zu den bestehenden, nichts abschalten.

### B. Neu bauen: Check-in per QR im CRM
6. **Check-in-Adresse** des CRM (Edge Function): Token → Karte → Besuch abziehen → Seite „Check-in erfolgreich – noch X von 8“ (wie heute).
7. **Benachrichtigungen** wie heute: bei 2 Rest Chat-Nachricht, bei 0 Plan-Entzug (gibt es schon) + E-Mail.
8. **Kurs-Zuordnung:** Der Check-in wird dem passenden Termin zugeordnet (Flenski-Event zur Uhrzeit, sonst „Studio-Check-in“ des Tages).
9. **Neue Karten:** SZ1/Sz4 legen die Karte künftig im CRM an (Make → CRM) statt im Datenspeicher; QR-Code zeigt auf die CRM-Adresse.

### C. Umstellung am Stichtag
10. Ruhiger Zeitpunkt (z. B. abends nach der letzten Stunde).
11. Reststände aus dem Datenspeicher ins CRM übernehmen (je Karte: Kauf + Reststand, Token bleibt gleich).
12. Alte QR-Codes weiter gültig machen (siehe Frage 3).
13. Alte Make-Szenarien SZ1–SZ4 und „Online Events Credits abziehen“ abschalten (nicht löschen).
14. Test mit Marcels Testkarte: Scan, Abzug, Anzeige im CRM, zweimal Buchungen zählen.
15. CRM-Seite in Ninas App einbauen (Marcel).

## Offene Fragen (vor dem Bauen klären)
1. **Präsenzstunden:** Sind Ninas Studiostunden auch Flenski-Events (mit Anmeldung) oder feste Zeiten ohne Event? → bestimmt, welchem Termin ein Check-in zugeordnet wird, und ob bei Anmeldung + Scan doppelt abgezogen werden könnte.
2. **Wer scannt?** Nina mit ihrem Handy? Heute kann jede Person mit dem Link selbst einchecken. Soll künftig nur Nina (angemeldet im CRM) einchecken können?
3. **Alte QR-Codes:** (a) weiter gültig über eine kleine Weiterleitung in Make (ca. 3 Operationen pro Scan) oder (b) allen 8 Kundinnen einmalig einen neuen Code schicken (danach 0 Make-Operationen).
4. **Gültigkeit der 8er-Karte:** Läuft sie ab (z. B. 6 Monate) oder unbegrenzt?
5. **Stichtag:** Wann, und weiß Nina Bescheid?
