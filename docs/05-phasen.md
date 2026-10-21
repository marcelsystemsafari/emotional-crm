# 05 – Bauphasen mit Abnahmekriterien

Regel: Eine Phase gilt erst als fertig, wenn alle Abnahmekriterien erfüllt und die Tests grün sind. Claude Code arbeitet Phase für Phase und hält nach jeder Phase an, damit Marcel abnehmen kann.

## Phase 0 – Technische Klärung (Spikes, ca. 1 Tag)

Ziel: die zwei Risiken beseitigen, die das ganze Konzept kippen könnten.

1. **Läuft eigenes JavaScript in der Flenski-Custom-Page?** Marcel fügt `ui/phase0-test.html` in eine Test-Custom-Page ein und öffnet sie auf: iPhone (Flenski-App bzw. Homescreen), Android, Desktop. Das Skript zeigt an, ob JavaScript läuft, ob es in einem iframe steckt, ob Speicher (localStorage) verfügbar ist und ob Anfragen nach außen funktionieren.
   Danach dasselbe mit echter Supabase-Verbindung und Login per E-Mail-Code.
   Ergebnis in `docs/entscheidungen/0001-einbettung.md` festhalten: direkte Einbettung (Standard) oder Fallback mit statischem Hosting (siehe 02).
2. **Webhook-Mitschnitt:** Supabase Edge Function, die jeden Request unverändert in `webhook_events` speichert (alternativ vorab webhook.site, siehe `inbox/README.md`). In Flenski je relevanten Trigger eine Automation darauf zeigen lassen und echte Ereignisse auslösen.
   Ergebnis: echte Beispiel-Payloads in `inbox/webhooks/`, Signaturverfahren dokumentiert.

3. **Aktivitäts-Mitschnitt starten (Modul 08):** Die Aktivitäts-Trigger aus `08-aktivitaet.md`, Abschnitt 6, zusätzlich auf denselben Empfänger zeigen lassen. Grund: Aktivitätshistorie lässt sich nicht nachträglich holen, jeder Tag ohne Mitschnitt ist verloren. Zusätzlich ein kurzer Spike (30 Minuten): Im Flenski-Admin Profil → Aktivität öffnen, im Browser mit F12 → Netzwerk die geladene Anfrage ansehen und Name/Adresse als Screenshot in `inbox/screenshots/` legen. **Nur Erkenntnis, kein Fundament.**

**Abnahme:** Entscheidung Einbettung dokumentiert; für jeden Trigger aus 04 liegt mindestens ein echtes Payload vor; Signatur lässt sich verifizieren (oder bekannt, dass nicht); die Aktivitäts-Trigger laufen und erzeugen Rohdaten in `webhook_events`.

## Phase 1 – Fundament

- Supabase-Projekt (EU), Migrationen für alle Tabellen aus 03, RLS-Policies, Views.
- Auth (E-Mail-Code), Mandantenauswahl, Rollen.
- SQL-Funktionen für Guthaben, Verkauf, Check-in (FEFO-Abbuchung), Storno, Korrektur, Ablauf, Signale – **mit Datenbank-Tests**.
- Seed: Mandant „Yoga by Lana (Demo)" mit den beiden Produkten und ~15 fiktiven Kundinnen.

**Abnahme:**
- Test: Nutzer aus Mandant A sieht keine einzige Zeile von Mandant B (automatisierter RLS-Test).
- Test: `ledger_entries` lässt sich nicht ändern oder löschen.
- Test: Guthaben 4 → drei Besuche → ein Storno → Stand 2, Verlauf zeigt 5 Buchungen.

## Phase 2 – MVP-Oberfläche (mobil zuerst, eine Datei `ui/crm.html`)

- **Kundinnenliste** mit Suche und Filtern: Produkt, Quelle (App/extern), Guthaben (0 / 1 / >1), läuft ab in ≤ 14 Tagen, letzter Besuch > X Tage, Tag, archiviert.
- **Kundinnen-Detail:** Stammdaten, aktive Berechtigungen mit Restguthaben + Ablauf, kompletter Buchungsverlauf, Notiz.
- **Verkauf erfassen:** Kundin wählen/anlegen → Produkt → Zahlweg → fertig (max. 3 Taps nach Kundinnenwahl).
- **Check-in:** Stunde wählen/anlegen → Liste (aus Anmeldungen oder Suche) → antippen = anwesend, mit Rückgängig. Anzeige des Reststands direkt am Namen.
- **Korrektur:** Plus/Minus mit Pflichtkommentar.
- **Produkte** verwalten (nur `owner`).

**Abnahme:** Check-in für 12 Personen auf dem iPhone in unter 60 Sekunden; Verkauf bar in unter 20 Sekunden; alle Texte auf Deutsch, Du-Form.

## Phase 3 – Flenski-Anbindung

- Webhook-Verarbeitung in der Edge Function gemäß Mapping in 04, basierend auf den echten Payloads aus Phase 0 (Prüfschemas daraus ableiten).
- Idempotenz, Wiederholung fehlgeschlagener Ereignisse, Fehlerliste in den Einstellungen.
- Plan-Zuordnung in der Oberfläche (Flenski-Plan → Produkt).
- Erstimport bestehender Flenski-Mitglieder.

**Abnahme:** Jedes Beispiel-Payload aus `inbox/webhooks/` als Test-Fixture verarbeitet; dasselbe Ereignis zweimal gesendet → genau eine Wirkung; ungültige Signatur → gespeichert, aber nicht verarbeitet.

## Phase 4 – Emotionales Board + Import/Export

- **Board** (Startseite): Karten „Droht abzuspringen", „Karte fast leer", „Läuft bald ab", „Neu dabei", „Zahlung fehlgeschlagen" mit Personen und Ein-Tap-Aktion (E-Mail/WhatsApp-Link vorbefüllt, „erledigt" markieren).
- **CSV-Import** externer Kundinnen (mit Vorschau, Spaltenzuordnung, Dublettenprüfung).
- **CSV-Export** aller Daten eines Mandanten (Kundinnen, Berechtigungen, Buchungen, Stunden).

**Abnahme:** Lanas echte Excel-Liste importiert ohne manuelle Nacharbeit außer Dubletten-Entscheidungen; Export lässt sich in Excel öffnen und vollständig wieder importieren.

## Phase 4b – Aktivität (Modul 08)

Voraussetzung: Phase 3 abgenommen und mindestens 4 Wochen echte Aktivitätsdaten aus dem Mitschnitt.

- Tabelle `activity_events`, View `v_customer_engagement`, Verarbeitung in der Edge Function (Prüfschemas aus echten Payloads).
- Reiter „Aktivität": Zählkacheln, Liste mit Mini-Verlauf, Detailverlauf je Kundin, Ein-Tap-Nachricht bei „Kühlt ab".
- Rollierende Löschung nach 12 Monaten (geplanter Job).

**Abnahme:** siehe `08-aktivitaet.md`, Abschnitt 8 (inkl. RLS-Test und Test, dass Studio-Besuche allein als „Aktiv" zählen).

## Phase 5 – später (nicht jetzt bauen)

- Endkundinnen-Ansicht „Mein Guthaben" in der Flenski-App (abhängig von Flenski-Identität in Custom Pages).
- Automatischer Plan-Entzug bei 0 Guthaben (abhängig von Flenski-API).
- Onboarding-Assistent für neue Mandanten, Mandanten-Abrechnung, Branding pro Mandant.
- Zentrale Auslieferung der Oberfläche (eine Ladezeile pro Custom Page statt Kopie), sobald es ca. 5 Mandantinnen gibt.
- Meilensteine, Geburtstage, Notizen-Erweiterungen.
- Aktivität: automatische Nachricht bei „Kühlt ab" (nur nach Freigabe), Verlaufsgrafik, Auswertung „welche Angebote halten Menschen aktiv".
