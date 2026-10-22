# 0001 – Einbettung: direkt im Flenski-Embed-Widget

Datum: 22.10.2026
Status: entschieden (Desktop und mobiler Browser getestet, native App ausstehend)

## Kontext

Phase 0 sollte klären, ob eigenes JavaScript in Flenski direkt in der Seite läuft (Standard) oder ob die Oberfläche extern gehostet und per iframe eingebettet werden muss (Plan B, siehe 02).

## Ergebnis des Tests (`ui/phase0-test.html`, Lanas App, Seite „CRM-Test“, nur Team)

| Prüfung | Desktop | mobiler Browser |
|---|---|---|
| JavaScript läuft | JA | JA |
| Direkt in der Seite, kein iframe (`appdemo.systemsafari.de`) | JA | JA |
| localStorage verfügbar | JA | JA |
| Verbindung zu Supabase | JA | JA |
| Bibliothek von cdn.jsdelivr.net geladen | JA | JA |
| Login per E-Mail-Code, angemeldet nach Neuladen | JA | – |

Wichtig: Der Code läuft nur im **Embed-Widget** einer Custom Page. Im **Fußzeilen-Feld** (Custom Code der Seite) läuft er **nicht**.

## Entscheidung

1. `ui/crm.html` wird **direkt** in ein Embed-Widget einer Flenski-Custom-Page eingefügt. Kein eigenes Hosting, kein iframe.
2. Login per 6-stelligem E-Mail-Code. Die Sitzung liegt im localStorage der Flenski-Seite (`storageKey: ecrm-auth`).
3. Plan B (statisches Hosting + iframe) wird nicht gebaut.

## Folgen

- Alle Styles mit Präfix `ecrm-`, alles in `#ecrm-root`, weil die Oberfläche im Flenski-Layout lebt (Regel 7 in CLAUDE.md).
- Größe des Widget-Inhalts im Blick behalten. Falls Flenski die Länge begrenzt, wird früher als geplant auf eine Ladezeile mit zentral gehosteter Datei umgestellt (02, „Updates bei mehreren Mandantinnen“).
- **Offen:** Test in der nativen Flenski-App auf iPhone und Android (WebView). Fällt er negativ aus, wird diese Entscheidung neu bewertet.
