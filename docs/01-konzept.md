# 01 – Produktkonzept

Arbeitstitel: **Emotional CRM** (Name noch offen)
Anbieter: Systemsafari (Marcel)
Stand: 20.10.2026

## 1. Problem

Yogalehrerinnen, Pilates-Trainerinnen und kleine Studios verkaufen Karten (4er, 10er), Kursblöcke und Abos. Den Überblick führen sie heute auf Papier, in Excel, im Kopf oder in Eversports.

Was dabei schiefgeht:
- Niemand weiß sicher, wie viele Besuche eine Kundin noch hat. Diskussionen („Ich hatte doch noch drei!") kosten Vertrauen.
- Kundinnen, die extern zahlen (bar, Überweisung, über einen Verein), tauchen in keinem System auf.
- Abwanderung wird erst bemerkt, wenn die Kundin weg ist. Das Signal (kommt seit drei Wochen nicht mehr, hat aber noch Guthaben) ist da, aber niemand sieht es.
- Der Verkaufsmoment wird verpasst: Wenn die Karte fast leer ist, wäre der beste Zeitpunkt für die Verlängerung.

Flenski (die App-Plattform) kennt Mitglieder und Zugangspläne, aber **keine Guthaben, keine Preise, keine Anwesenheit und keine externen Kundinnen**. Diese Lücke schließt das Produkt.

## 2. Für wen

- **Primär:** die Lehrerin bzw. Studioinhaberin (Rolle `owner`) und ggf. Vertretungen (Rolle `staff`).
- **Später:** die Endkundin, die im eigenen App-Bereich ihr Restguthaben sieht (Phase 5).
- **Erste Mandantin:** Lana (Yoga by Lana). Das Produkt wird aber **nicht** für Lana gebaut, sondern für jede Flenski-App.

## 3. Jobs to be done (Lehrerin)

1. Vor/in der Stunde: „Wer ist da? Hakt ab, zieht ab." (unter 30 Sekunden, am Handy)
2. „Wie viel hat Kundin X noch – und seit wann?" (Nachweis per Verlauf)
3. „Jemand hat bar bezahlt – Karte eintragen." (unter 20 Sekunden)
4. „Wen muss ich diese Woche persönlich ansprechen?" (Abwanderung, leere Karte, Ablauf)
5. „Alle meine Kundinnen auf einen Blick, filterbar." (App + extern, Produkt, Status)
6. „Wer ist gerade dabei, wer kühlt ab?" (App-Aktivität und Studio-Besuche zusammen, siehe 08)

## 4. Was das Produkt *emotional* macht

Ein normales CRM speichert Daten. Dieses CRM sagt der Lehrerin, **um welche Menschen sie sich jetzt kümmern sollte**. MVP-Signale:

| Signal | Regel (konfigurierbar) | Handlung für die Lehrerin |
|---|---|---|
| Droht abzuspringen | Guthaben > 0, letzter Besuch > 21 Tage | persönlich anschreiben |
| Karte fast leer | Restguthaben ≤ 1 | Verlängerung anbieten |
| Karte läuft bald ab | Ablauf in ≤ 14 Tagen, Guthaben > 0 | an Resteinlösung erinnern |
| Neu dabei | erster Besuch in den letzten 14 Tagen | willkommen heißen, nach 2. Besuch fragen |

Später (Phase 4+): Meilensteine (10. Besuch), Geburtstage, Notizen zur Person.

### Aktivität (Modul, Phase 4b)

Ergänzend zu den Signalen zeigt ein Reiter „Aktivität" alle Kundinnen in vier Stufen: **Neu · Aktiv · Kühlt ab · Eingeschlafen**. Grundlage sind App-Aktivität (Flenski-Webhooks) **und** Studio-Besuche (Check-in), damit Kundinnen, die nur ins Studio kommen, nicht als inaktiv gelten. Ziel ist ein Frühwarnsystem, keine Rangliste. Details: `08-aktivitaet.md`.

## 5. Abgrenzung (bewusst NICHT im Produkt)

- Keine Zahlungsabwicklung, keine Rechnungen. Zahlungen laufen weiter über Flenski bzw. extern. Das CRM protokolliert nur, *dass* bezahlt wurde und wie.
- Kein Buchungskalender. Termine kommen aus Flenski-Events oder werden einfach angelegt.
- Keine Gesundheitsdaten (siehe 07-datenschutz.md).
- Kein Ersatz für Flenski. Die App bleibt der Ort für Inhalte und Community.

## 6. Geschäftsmodell und Bindung

**Positionierung:** Systemsafari steht für *Eigentum statt Miete* (Feindbild Eversports). Das CRM muss diese Haltung tragen, nicht unterlaufen.

**Entscheidung (bestätigt 20.10.2026):**
- Das CRM ist **Bestandteil des monatlichen Pakets**, nicht einzeln kaufbar. Es steckt technisch in jeder betreuten App im Hintergrund und wird pro Mandantin ein- oder ausgeschaltet.
- Wer das Paket kündigt, verliert den **Zugriff auf die Software**. Wer wieder bucht, bekommt ihn zurück.
- Die Daten gehören der Kundin: Bei Kündigung erhält sie einen vollständigen CSV-Export.
- Die Bindung entsteht durch **Gewohnheit und Arbeitsersparnis**: tägliches Abhaken, Abwanderungs-Hinweise, automatisch eingepflegte App-Käufe. Wer das hat, will es nicht mehr manuell machen.

**Ruhemodus (Rückkehr-Hebel):** Bei Kündigung kann die Kundin wählen:
- *Löschen* (Standard): 30 Tage Lesezugriff + Export, danach Löschung.
- *Ruhen lassen*: Daten bleiben bis zu 12 Monate gespeichert (mit ihrer ausdrücklichen Zustimmung), kein Zugriff. Bei Rückkehr ist alles sofort wieder da: Kundinnen, Guthaben, Verlauf.
Das macht die Rückkehr leicht, ohne jemanden festzuhalten: Wer zurückkommt, startet nicht bei null.

Mandantenstatus im System: `trial` → `active` → `cancelled` (30 Tage lesen + Export) → `dormant` (Ruhemodus, kein Zugriff) oder `deleted`. Von `dormant` zurück zu `active` ist ein Schalter.

## 7. Erfolgskriterien MVP

- Lana nutzt den Check-in in mindestens 80 % ihrer Stunden über 4 Wochen.
- Kein einziger Fall, in dem der angezeigte Stand nicht durch den Verlauf belegbar ist.
- Eine neue Flenski-App lässt sich in unter 30 Minuten anbinden (Mandant anlegen, Produkte zuordnen, Webhooks eintragen, Custom Page einbetten).
