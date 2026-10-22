# Plan Phase 1 – Fundament

Stand: 22.10.2026 · Status: **abgenommen am 22.10.2026** – 93 Datenbank-Tests grün
Grundlage: `03-datenmodell.md`, `05-phasen.md`. Phase 1 baut **keine Oberfläche**. Alles passiert in der Datenbank und wird mit automatischen Tests bewiesen. Die Oberfläche kommt in Phase 2.

## In einem Satz

Danach kann die Datenbank Kundinnen, Karten, Verkäufe, Check-ins, Stornos, Korrekturen und Signale verwalten, sicher getrennt pro Mandantin, und jede Regel ist durch einen Test belegt.

## Bauschritte (je Schritt ein Commit, nach jedem Schritt laufen alle Tests)

### 1. Zugriff und Rollen
- Tabellen `tenant_members` (Rolle `owner` / `staff`) und `platform_admins` (Marcel).
- Hilfsfunktionen für die Sicherheitsregeln: „Ist diese Person Mitglied dieser Mandantin?“, „Ist sie owner?“.
- Mandantenstatus wird durchgesetzt: `cancelled` = nur lesen, `dormant` = kein Zugriff.
- Das Feld `webhook_secret` bleibt für Browser unsichtbar.
- **Login:** Die offene Registrierung wird geschlossen. Neue Nutzerinnen kommen nur per Einladung durch Marcel (Skript `scripts/invite-user.mjs <email> <mandant> <rolle>`).
- Marcel (`info@systemsafari.de`) wird `platform_admin`.

### 2. Kundinnen, Produkte, Stunden
- `customers` (inkl. Kinder-/Eltern-Felder, Notiz *ohne Gesundheitsdaten*, archiviert), `products`, `sessions`, `audit_log`.
- `activity_events` (nur Tabelle, für den Mitschnitt in Phase 3; Auswertung erst in 4b).
- Regel: `staff` darf Produkte und Einstellungen nur ansehen, nicht ändern.

### 3. Karten und Buchungsprotokoll
- `entitlements` (gekaufte Karten/Blöcke/Abos) und `ledger_entries` (Buchungen).
- `ledger_entries` ist **nur anfügbar**: Ändern und Löschen sind für alle gesperrt, auch für den Server (Trigger).
- Ansichten `v_entitlement_balance` (Rest je Karte) und `v_customer_overview` (Rest, Ablauf, letzter Besuch je Kundin).

### 4. Fachlogik als SQL-Funktionen
| Funktion | Was sie tut |
|---|---|
| `sell(kundin, produkt, zahlweg, preis?)` | Karte anlegen + Kauf-Buchung (+4 usw.), Ablaufdatum aus Gültigkeit |
| `checkin(stunde, kundin)` | Anwesend + −1 von der passenden Karte: zuerst die, die zuerst abläuft (FEFO), dann die ältere. Kursblock/Abo: kein Abzug. Keine passende Karte → Check-in trotzdem, Kundin „offen“ |
| `undo_checkin(...)` | Rückgängig direkt nach dem Antippen (Gegenbuchung, nichts wird gelöscht) |
| `cancel_attendance(...)` | Absage: rechtzeitig = Rückbuchung, zu spät / nicht erschienen = Abzug laut Einstellung |
| `correct(karte, ±n, kommentar)` | Korrektur, Kommentar ist Pflicht |
| `expire_entitlements()` | Abgelaufene Karten verfallen (Verfall-Buchung), läuft nachts automatisch |
| `customer_signals()` | Droht abzuspringen · Karte fast leer · läuft bald ab · neu dabei – Schwellen aus den Einstellungen |
| `anonymize_customer(...)` | Kundin löschen = Personendaten weg, Buchungen bleiben anonym |

Jede Änderung an Kundinnen, Produkten und Einstellungen landet im `audit_log`.

### 5. Demo-Daten
- Eigene Mandantin **„Yoga by Lana (Demo)“** (`yoga-by-lana-demo`), getrennt von Lanas echter Mandantin.
- Beide Produkte, ~15 erfundene Kundinnen (App + extern, eine mit Kind), Stunden der letzten Wochen, Käufe und Besuche, sodass jedes Signal mindestens einmal vorkommt.

## Tests (Abnahme laut 05, plus Regeln)
- Mandantin A sieht **keine einzige Zeile** von Mandantin B, für jede Tabelle.
- `ledger_entries` lässt sich nicht ändern oder löschen.
- Karte mit 4 → drei Besuche → ein Storno → Stand 2, Verlauf zeigt 5 Buchungen.
- FEFO: Von zwei Karten wird die zuerst ablaufende belastet.
- Produkt vom Typ Zeitraum/Abo: Teilnahme ohne Abzug. Keine Karte: Check-in klappt, Kundin „offen“.
- Storno rechtzeitig / zu spät / nicht erschienen nach Einstellung.
- Ablauf: Rest verfällt mit Buchung. Korrektur ohne Kommentar wird abgelehnt.
- Jedes Signal mit Beispiel. `staff` kann keine Produkte ändern. `cancelled` kann nur lesen, `dormant` gar nichts.

## Was du danach siehst
Noch keine Oberfläche, aber: eine Liste grüner Tests und auf Wunsch eine Tabelle der Demo-Kundinnen mit Restguthaben und Signalen, abgefragt direkt aus der Datenbank.

## Entscheidungen (von Marcel, 22.10.2026)
| Frage | Entscheidung | Folge im Bau |
|---|---|---|
| Stornofrist | **12 Stunden** | `storno_frist_stunden = 12`; später absagen oder nicht kommen = Abzug |
| Kursblock Erwachsene | **10er-Karte flexibel** | Produkt `type = credits`, `credits = 10`, `validity_days = 70`; jeder Besuch zieht 1 ab |
| Abos | **nur unbegrenzt** | `subscription` ohne Kontingent, kein Abzug; Monatskontingente später |
| Droht abzuspringen | **21 Tage + Guthaben** | `signal_inaktiv_tage = 21`; Status „Kühlt ab" bleibt 15–30 Tage, beides pro Mandantin änderbar |
