# Phase 0 – deine Klick-Anleitung

Stand: 21.10.2026. Alles, was Claude Code allein bauen konnte, ist fertig und läuft:
der Webhook-Empfänger in Supabase und die Testseite. Jetzt brauchen wir Flenski, und das geht nur über dich.

Reihenfolge nach Wichtigkeit. **Teil 1 zuerst**, denn jeder Tag ohne Mitschnitt ist verlorene Aktivitäts-Historie.

---

## Teil 1 – Automationen in Flenski anlegen (am wichtigsten)

Für **jede Zeile** der Tabelle unten legst du eine Automation an. Pro Automation dauert das etwa eine Minute.

1. In Flenski (Lanas App) → **Automation erstellen**.
2. **Trigger** auswählen (linke Spalte der Tabelle).
3. Aktion **„Webhook senden“** wählen.
4. **Endpoint-URL:** die passende Adresse aus der rechten Spalte komplett einfügen.
5. **Zustellungslimits:**
   - Max. Zustellungen pro Stunde → **ohne Limit** (sonst wirft Flenski Ereignisse weg!)
   - Sammelfenster → **sofort senden**
6. Falls Flenski ein **Secret / Signatur-Schlüssel** anzeigt oder verlangt: **Screenshot vom Dialog** in `inbox/screenshots/` legen, den Schlüssel selbst darauf schwärzen. Den Schlüssel bitte nicht in den Chat schicken.
7. **Speichern**, dann auf **„Testen“** klicken.

| Trigger in Flenski | Endpoint-URL |
|---|---|
| Neues Mitglied | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yoga-by-lana&trigger=neues-mitglied` |
| Neuer Kontakt | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yoga-by-lana&trigger=neuer-kontakt` |
| Plan zugewiesen | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yoga-by-lana&trigger=plan-zugewiesen` |
| Plan entzogen | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yoga-by-lana&trigger=plan-entzogen` |
| Mitglied gelöscht | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yoga-by-lana&trigger=mitglied-geloescht` |
| Bestellung abgeschlossen | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yoga-by-lana&trigger=bestellung-abgeschlossen` |
| Zahlung fehlgeschlagen | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yoga-by-lana&trigger=zahlung-fehlgeschlagen` |
| Abonnement gekündigt | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yoga-by-lana&trigger=abonnement-gekuendigt` |
| Am Event teilgenommen | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yoga-by-lana&trigger=am-event-teilgenommen` |
| Event beginnt bald | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yoga-by-lana&trigger=event-beginnt-bald` |
| Zum Kurs angemeldet | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yoga-by-lana&trigger=zum-kurs-angemeldet` |
| Kurs abgeschlossen | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yoga-by-lana&trigger=kurs-abgeschlossen` |
| Beitrag in der Community erstellt | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yoga-by-lana&trigger=beitrag-community-erstellt` |
| Beitrag in einer Gruppe erstellt | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yoga-by-lana&trigger=beitrag-gruppe-erstellt` |
| Kommentar erstellt | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yoga-by-lana&trigger=kommentar-erstellt` |
| Frage in der Fragebox gestellt | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yoga-by-lana&trigger=frage-gestellt` |
| Datei heruntergeladen | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yoga-by-lana&trigger=datei-heruntergeladen` |
| Artikel gelesen | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yoga-by-lana&trigger=artikel-gelesen` |
| CTA auf dem Sperrbildschirm geklickt (alle Sperrbildschirme, alle CTA-Typen) | `https://aipnvftsuhnffkvnrygt.supabase.co/functions/v1/flenski-webhook?tenant=yoga-by-lana&trigger=sperrbildschirm-cta-geklickt` |

**Nicht** anlegen: „Beitrag gelesen“ (zu viele Ereignisse, siehe `08-aktivitaet.md`) und „Punkte vergeben“.

**Danach echt auslösen** (Test-Payloads enthalten oft Platzhalter): ein Testmitglied anlegen, ihm einen Plan zuweisen und wieder entziehen, an einem Event teilnehmen, einen Kurs starten, einen Beitrag schreiben. Sag Claude Code danach Bescheid. Claude holt die Nachrichten aus der Datenbank, legt sie als Beispiele in `inbox/webhooks/` ab und ersetzt dabei echte Namen durch Fantasiewerte.

---

## Teil 1b – Automationen neu anlegen und Schlüssel sichern (22.10.2026)

Flenski signiert jede echte Nachricht mit einem **eigenen Schlüssel pro Automation** und zeigt ihn **nur einmal** beim Anlegen. Der „Testen“-Knopf benutzt dagegen einen Einmalschlüssel, Testnachrichten lassen sich also nie prüfen. Echte Nachrichten schon.

Vorbereitung: `.env.local` im Editor öffnen. Ganz unten steht für jede Automation eine leere Zeile `FLENSKI_SECRET_…=`.

Für **jede** der 16 Automationen (auch „Neues Mitglied“, dessen Schlüssel im Chat stand):
1. **Alte Automation löschen.** Sonst kommen Nachrichten doppelt, eine davon mit unbekanntem Schlüssel.
2. Neue Automation anlegen, gleicher Trigger, **gleiche Adresse** wie in der Tabelle oben, Limits „ohne Limit / sofort“.
3. Sobald Flenski den Schlüssel zeigt: kopieren → im Editor hinter das passende `=` einfügen → **sofort Strg + S**.
4. Erst danach den Flenski-Dialog schließen.

Den Schlüssel nie in den Chat. Wenn alle 16 drin sind, Claude Code Bescheid geben. Claude überträgt sie dann sicher in die Datenbank und prüft mit einer echten Nachricht.

---

## Teil 2 – Eigener Mailversand in Supabase (für den Login per Code)

Im kostenlosen Supabase-Tarif steht in der Login-Mail nur ein Link und **kein Code**. Der Link öffnet sich aber im normalen Browser statt in der Flenski-App. Deshalb soll Supabase die Mails über dein eigenes Postfach verschicken. Das ist sowieso nötig, denn Supabase selbst verschickt nur 2 Mails pro Stunde und nur an dich.

1. Supabase → Projekt **emotional-crm** → links **Authentication** → **Emails** (bzw. „SMTP Settings“).
2. **Enable Custom SMTP** einschalten.
3. Die Daten deines Postfachs eintragen, z. B. bei ALL-INKL: Host, Port (meist 465 oder 587), Benutzername, Passwort, Absender-Adresse und Absendername „Systemsafari CRM“. Die Werte stehen im KAS bei deinem Postfach.
4. **Speichern.** Das Passwort trägst du nur dort ein, nicht im Chat.
5. Claude Code Bescheid geben. Claude stellt dann die deutsche Mail mit dem 6-stelligen Code ein.

---

## Teil 3 – Testseite in Flenski

1. In Flenski eine **neue Custom Page** anlegen, Name z. B. „CRM-Test“, Sichtbarkeit **nur Team**.
2. **Eigenen Code** einschalten (`isCustomCodeEnabled`).
3. Den kompletten Inhalt der Datei `ui/phase0-test.html` in das Code-Feld kopieren. Claude Code kann dir die Datei öffnen, dann **Strg + A** und **Strg + C**.
4. Seite speichern und öffnen auf:
   - dem **iPhone** (Flenski-App bzw. Homescreen),
   - einem **Android-Handy** (falls vorhanden),
   - dem **Desktop**.
5. Von jedem Gerät einen **Screenshot** machen und in `inbox/screenshots/` legen.
6. Erst **nach Teil 2:** Login testen. E-Mail eingeben → Code aus der Mail eintippen → Seite neu laden → bist du noch angemeldet? Auch davon einen Screenshot.

Bei allen Zeilen sollte **JA** stehen. Ein **NEIN** ist kein Drama, dann greift der Plan B aus `02-architektur.md`.

---

## Teil 4 – Kurzer Blick in die Aktivität (optional, 5 Minuten)

Flenski-Admin → ein Mitglied → **Profil ansehen** → **Aktivität**. **F12** drücken → Reiter **„Netzwerk“** → Seite neu laden. Einen Screenshot der Liste machen (nur Namen und Adressen der Anfragen, keine Inhalte) und in `inbox/screenshots/` legen.
