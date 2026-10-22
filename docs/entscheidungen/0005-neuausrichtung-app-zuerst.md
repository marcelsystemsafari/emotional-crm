# 0005 – Neuausrichtung: Die App ist die Quelle, das CRM zeigt die Menschen

Datum: 22.10.2026
Status: entschieden (Marcel, nach dem ersten Test der Oberfläche in Flenski)

## Kontext

Die Phase-2-Oberfläche (Reiter Check-in · Kundinnen · Verkauf · Mehr) folgte der ursprünglichen Reihenfolge in `05-phasen.md`: erst Handbetrieb, dann in Phase 3 die Flenski-Anbindung. Beim Test in Lanas App zeigte das CRM **0 Kundinnen**, obwohl es in der App Mitglieder gibt und deren Aktivität bereits per Webhook ankommt (nur roh gespeichert).

Marcels Rückmeldung:
- Ziel des CRM ist vor allem, **vollautomatisch mit der App verbunden** zu sein und zu sehen, **wie sich die Menschen verhalten** (wie oft sie teilnehmen, wer abkühlt).
- Check-in von Hand ist unnötig: Kurse/Termine laufen in Flenski über Events.
- Verkauf und Produkte von Hand sind unnötig: Käufe und Pläne kommen aus der App.
- Die Oberfläche wirkt weder modern noch übersichtlich, man hat keinen Überblick über die Menschen.

## Entscheidung

1. **Flenski ist die Quelle.** Mitglieder, Pläne (= Produkte), Käufe und Event-Teilnahmen kommen automatisch per Webhook (plus einmaliger Erstabgleich). Die Lehrerin pflegt nichts doppelt.
2. **Teilnahme = „Am Event teilgenommen“ aus Flenski.** Das zählt als Besuch und bucht von der passenden Karte ab. Es gibt kein Abhaken im CRM.
3. **Externe Zahlungen bleiben möglich**, aber versteckt in der Detailansicht einer Person („Zahlung von Hand nachtragen“), nicht als eigener Reiter. Lana hat auch Kundinnen außerhalb der App.
4. **Neue Oberfläche** nach dem Entwurf vom 22.10.2026, mit drei Reitern: **Übersicht** (Kennzahlen, „um diese Menschen kümmerst du dich jetzt“, „gerade passiert“) · **Menschen** (Liste + Detail mit Aktivitätsverlauf) · **Kurse** (Flenski-Events mit Teilnehmenden).
5. **Reihenfolge geändert:** Phase 3 (Anbindung) und der Kern von Phase 4b (Aktivitätsstatus) kommen **vor** die Abnahme der Oberfläche. Die Phase-2-Oberfläche wird ersetzt, nicht weiter ausgebaut.

## Folgen

- Bleibt gültig: Datenbank, Regeln und Tests aus Phase 1 (Buchungsprotokoll, FEFO, Storno, Signale). Sie werden jetzt vom Webhook aufgerufen statt von Hand.
- Produkte entstehen aus Flenski-Plänen. Flenski kennt aber **keine Einheiten, keine Gültigkeit und keinen Preis**. Deshalb muss Lana pro Plan **einmal** angeben, z. B. „10er-Karte = 10 Besuche, 70 Tage“. Bis dahin zählt das CRM die Teilnahmen, bucht aber nichts ab.
- Die Aktivitätsdaten des Mitschnitts seit 22.10. werden nachträglich verarbeitet.
- Der Erstabgleich bestehender Mitglieder/Pläne/Events läuft vorerst über Marcels Flenski-Verbindung (von Claude Code ausgelöst). Ein dauerhafter Abgleich durch den Server braucht einen Flenski-API-Schlüssel (offene Support-Frage, 06).
