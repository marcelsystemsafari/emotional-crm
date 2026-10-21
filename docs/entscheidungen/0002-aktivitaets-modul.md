# 0002 – Aktivitäts-Dashboard als Modul des CRM

Datum: 21.10.2026
Status: entschieden (Konzept), Umsetzung Phase 4b

## Kontext

Idee von Marcel: Eine Custom Page, auf der Admins sehen, wie aktiv die Mitglieder sind (wer ist dabei, wer nicht), nach dem Vorbild der Aktivitätsansicht im Flenski-Admin-Profil. Erster Einsatz bei Lana, Nutzen für jede Flenski-App.

Die Flenski-Schnittstelle liefert pro Mitglied nur `lastLoginAt`, keinen Aktivitätsverlauf. Der Verlauf aus dem Admin-Profil ist nicht abrufbar (Stand 21.10.2026, getestet).

## Entscheidung

1. Das Dashboard wird **kein eigenes Projekt**, sondern ein Reiter im Emotional CRM (gleiche Datenbank, gleiche Custom Page, gleiche Mandantentrennung).
2. Aktivität = **Studio-Besuche + App-Aktivität**. Ein reines App-Dashboard würde Kundinnen, die nur im Studio sind, fälschlich als inaktiv zeigen.
3. Datenquelle sind Flenski-Webhooks direkt in die Edge Function (kein Make). Die undokumentierte interne Anfrage der Admin-Ansicht ist höchstens ein Spike in Phase 0, nie Fundament.
4. Die Aktivitäts-Trigger werden **schon in Phase 0 aufgezeichnet**, weil Historie nicht rückwirkend entsteht.
5. Zielbild ist ein Frühwarnsystem („Kühlt ab"), keine Rangliste.

## Folgen

- Neue Tabelle `activity_events` und View `v_customer_engagement` (siehe 03).
- Schwellen des Status und des Signals „Droht abzuspringen" müssen vereinheitlicht werden (offener Punkt in 06).
- Datenschutz: Verhaltensdaten, rollierende Aufbewahrung, Hinweis in der Datenschutzerklärung der Lehrerin (siehe 07).
- Das Dashboard hat bei Lana vor Januar kaum praktischen Nutzen (kleine Mitgliederzahl). Es ist Verkaufsargument und Ausblick, kein Blocker für die Demo am 01.11.
