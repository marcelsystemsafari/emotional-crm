# 08 – Modul „Aktivität" (Wer ist dabei, wer kühlt ab)

Stand: 21.10.2026 · Status: Konzept, Datensammlung ab Phase 0, Oberfläche in Phase 4b
Gehört zum Emotional CRM, **kein eigenes Projekt**: gleiche Datenbank, gleiche Custom Page, ein Reiter mehr.

## 1. Problem und Nutzen

Die Lehrerin sieht heute nur im Flenski-Admin Profil für Profil, wer was getan hat. Einen Gesamtüberblick („Wer ist aktiv, wer nicht?") gibt es nicht. Wer unbemerkt abkühlt, kündigt später, und das ist der Umsatz, der der Lehrerin wegbricht.

Das Modul beantwortet eine Frage: **Um wen sollte ich mich kümmern, bevor sie weg ist?** Es ist deshalb nicht als Rangliste der Aktivsten gedacht, sondern als Frühwarnsystem plus Überblick über alle Kundinnen.

## 2. Kernentscheidung: Aktivität = App UND Studio

Ein reines App-Dashboard wäre irreführend. Eine Kundin, die zweimal pro Woche im Studio steht und die App nie öffnet, ist hochaktiv. Ein Dashboard, das sie als „inaktiv" zeigt, zerstört das Vertrauen der Lehrerin in das ganze System.

Darum fließen zwei Quellen zusammen:

| Quelle | Woher | Wer ist abgedeckt |
|---|---|---|
| Studio-Besuche | `attendances` (Check-in, Karten-Abbuchung) | App-Mitglieder **und** externe Kundinnen |
| App-Aktivität | Flenski-Webhooks → `activity_events` | nur App-Mitglieder |

Externe Kundinnen ohne App haben keine App-Aktivität. Ihr Status ergibt sich allein aus Besuchen.

## 3. Status (vier Stufen)

Berechnet in der View `v_customer_engagement`, **nicht** in der Oberfläche (Regel 6 in CLAUDE.md).

| Status | Regel (Standard, pro Mandant in `settings` änderbar) | Bedeutung für die Lehrerin |
|---|---|---|
| **Neu** | erste Aktivität oder Anlage vor ≤ 14 Tagen | begleiten, willkommen heißen |
| **Aktiv** | letzte Aktivität vor ≤ 14 Tagen | alles gut, nichts tun |
| **Kühlt ab** | letzte Aktivität vor 15–30 Tagen | **hier lohnt sich die persönliche Nachricht** |
| **Eingeschlafen** | letzte Aktivität vor > 30 Tagen | Rückholaktion oder loslassen |

`letzte Aktivität = greatest(last_visit_at, last_app_activity_at)`

Zusätzlich je Kundin ein **30-Tage-Wert** (gewichtete Summe), nur zum Sortieren innerhalb der Gruppe:
Besuch = 3 Punkte, aktive App-Handlung (Kurs angemeldet/abgeschlossen, Beitrag, Kommentar, Frage gestellt, Event teilgenommen) = 2 Punkte, passive App-Handlung (Artikel gelesen, Datei heruntergeladen) = 1 Punkt. Gewichte stehen in `tenants.settings`, nicht im Code.

**Abgrenzung zum Signal „Droht abzuspringen"** (siehe 01): Das Signal verlangt zusätzlich Guthaben > 0 und ist damit ein Umsatzsignal. Der Status „Kühlt ab" gilt unabhängig vom Guthaben. Beide Schwellen (21 Tage im Signal, 14/30 im Status) müssen vor dem Bau vereinheitlicht werden, siehe 06, Abschnitt A.

## 4. Oberfläche (Reiter „Aktivität" neben dem Board)

- **Kopf:** vier Zählkacheln (Neu / Aktiv / Kühlt ab / Eingeschlafen). Tipp auf eine Kachel filtert die Liste.
- **Liste:** Name, Status, letzte Aktivität („vor 9 Tagen · Yoga am Dienstag"), Mini-Verlauf der letzten 8 Wochen. Standard-Sortierung: „Kühlt ab" nach oben, dort nach Guthaben absteigend (wer noch Guthaben hat, ist die dringendste Rückhol-Chance).
- **Detail je Kundin:** chronologischer Verlauf wie im Flenski-Admin („Mai: Kurs gestartet · geführte Audioentspannung · Event registriert"), Besuche und App-Handlungen in einer Zeitleiste.
- **Ein-Tap-Aktion** bei „Kühlt ab": vorbefüllte Nachricht (E-Mail/WhatsApp-Link) und „erledigt" markieren, gleiche Mechanik wie das Board in Phase 4. Texte kurz, warm, Du-Form, keine Überwachungssprache („Ich habe gesehen, dass du lange nicht da warst" ist verboten, „Ich habe an dich gedacht" ist erlaubt).
- **Sprache:** nie „inaktiv" oder „Ranking" in der Oberfläche. Begriffe: „dabei", „kühlt ab", „eingeschlafen".
- **Zugriff:** nur `owner` und `staff`. Die Flenski-Sichtbarkeit „nur Team" ist Komfort, **nicht** Schutz. Der Schutz ist RLS in Supabase (siehe 03).

## 5. Datenquellen und was dabei unsicher ist

Die Flenski-Admin-Ansicht „Profil → Aktivität" zeigt mehr, als die bekannten Webhook-Trigger liefern (z. B. „Kurs gestartet", „geführte Audioentspannung"). Ob es dafür einen Trigger gibt, ist **unbekannt** (siehe 04).

Drei mögliche Wege, nach Priorität:

1. **Webhooks direkt in die Edge Function `flenski-webhook`** (Standard, offiziell, stabil). Kein Make nötig. Nachteil: Es gibt nur Daten ab dem Zeitpunkt, an dem die Automationen laufen. Keine Rückwirkung.
2. **Flenski-Schnittstelle für `lastLoginAt`** als Zusatzsignal (Login ohne Handlung). Nur wenn der eigene Server sie aufrufen darf (offene Support-Frage in 06).
3. **Interne Anfrage der Admin-Profilansicht nachbauen** (bringt vielleicht die Historie). **Nur als Spike in Phase 0, nie als Fundament.** Undokumentiert, kann ohne Vorwarnung brechen. Würde sich eine Mandantin darauf verlassen, hätte Systemsafari ein Supportproblem, das es nicht kontrolliert.

**Wichtig für die Reihenfolge:** Aktivitätsdaten lassen sich nicht nachträglich rekonstruieren. Jeder Tag ohne Mitschnitt ist ein verlorener Tag Historie. Darum werden die Aktivitäts-Trigger schon in Phase 0 mit aufgezeichnet (nur roh in `webhook_events`), auch wenn das Dashboard erst in Phase 4b gebaut wird.

## 6. MVP-Trigger (Empfehlung)

Aufnehmen: Zum Kurs angemeldet, Kurs abgeschlossen, Beitrag in der Community erstellt, Beitrag in einer Gruppe erstellt, Kommentar erstellt, Frage in der Fragebox gestellt, Am Event teilgenommen, Datei heruntergeladen, Artikel gelesen.

Zunächst **nicht**: „Beitrag gelesen" (Community/Gruppe). Hohes Volumen, geringe Aussagekraft, und die Zustellungslimits verwerfen Überschuss. Nach 4 Wochen Echtdaten neu bewerten. Zustellungslimits in Flenski immer „ohne Limit / sofort" (siehe 04).

## 7. Datenschutz-Leitplanken (Ergänzung zu 07)

- Gespeichert wird nur: Ereignisart, Zeitpunkt, **Titel** des Kurses/Events/Artikels. Nie Inhalt von Beiträgen, Kommentaren oder Fragen.
- Aufbewahrung: rollierend 12 Monate, danach Löschung (geplanter Job). Der Status braucht nur die letzten 30 Tage; die längere Zeitleiste dient der Ansicht pro Kundin.
- Das ist Verhaltensprofilierung von Mitgliedern. Die Lehrerin muss das in ihrer Datenschutzerklärung nennen (Baustein dafür in 06, Abschnitt E ergänzen).
- Löscht oder anonymisiert die Lehrerin eine Kundin, werden `activity_events` mit gelöscht bzw. anonymisiert (kein Rückbezug auf die Person).
- Aktivität ist kein Gesundheitsdatum, solange Titel nichts Gesundheitliches enthalten. Titel werden im Rohzustand gespeichert; die Oberfläche zeigt sie nur der Lehrerin.

## 8. Abnahmekriterien (Phase 4b)

- Test: Eine Kundin mit Besuch gestern und ohne App-Aktivität ist „Aktiv".
- Test: Eine externe Kundin ohne App und mit Besuch vor 20 Tagen ist „Kühlt ab".
- Test: Dasselbe Webhook-Ereignis zweimal → genau ein Eintrag in `activity_events`.
- Test: Mandant A sieht keine Aktivität von Mandant B (RLS).
- Test: `staff` sieht die Liste, `customer`-Rolle (Phase 5) nicht.
- Praxis: Lana erkennt in der „Kühlt ab"-Liste mindestens 3 Personen, bei denen sie sagt „Stimmt, die habe ich lange nicht gesehen".

## 9. Später (Phase 5+)

- Automatische Nachricht bei „Kühlt ab" (nach Freigabe durch die Lehrerin, nie ungefragt).
- Verlaufsgrafik Aktivität über Monate (Zugkurve des Studios).
- Gegenüberstellung: Welche Angebote (Kurs, Event, Audio) halten Menschen aktiv? Das ist die eigentlich wertvolle Auswertung für Lanas Angebotsplanung.
