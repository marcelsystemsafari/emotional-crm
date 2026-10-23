# Einrichtungstag: CRM für eine neue Lehrerin

Stand 23.10.2026. Ziel: so wenig Handarbeit wie möglich. Was Marcel (oder Claude) tut, ist markiert.

## Vorher (ohne Lehrerin)
1. **Mandantin anlegen** (Claude): Name, Kürzel (z. B. `yogini-nina`), Profil-Link, Logo, Signatur, Ausschluss-Tags.
2. **Lehrerin einladen** (Claude): `node scripts/invite-user.mjs` mit ihrer E-Mail, Rolle Inhaberin.

## Am Einrichtungstag (gemeinsam, ca. 30–45 Minuten)
3. **Flenski-Automationen** in ihrer App anlegen (Marcel), wie bei Lana (`docs/phase0-anleitung.md`). Webhook-Adresse jeweils mit `?tenant=<kürzel>&trigger=<trigger>`. Die Schlüssel der Automationen in ihre eigene Datei `.env.<kürzel>.local` eintragen (Vorlage `.env.lehrerin.example` kopieren), Claude lädt sie hoch: `node scripts/upload-webhook-secrets.mjs <kürzel>`.
4. **Flenski-API-Schlüssel** der App erzeugen und als `FLENSKI_API_KEY` in `.env.<kürzel>.local` eintragen (Marcel). Dann (Claude):
   `node scripts/setup-flenski-sync.mjs <kürzel> <flenski-app-id>`
   → Termine, Anmeldungen und Teilnehmer-Abgleich laufen ab jetzt automatisch.
5. **Make** (nur wenn die Lehrerin automatischen Plan-Entzug möchte; Make ist ohnehin für ihre Automationen eingerichtet):
   - In Make eine **Flenski-Verbindung mit ihrem Flenski-Login** anlegen (Marcel, mit ihr zusammen). Module mindestens: „Revoke a Plan for a Profile“ und „Make an API Call“.
   - **Szenario kopieren** (Claude): Vorlage „🧘 ECRM: Flenski-Aktionen – Yoga by Lana“ duplizieren, ihre Verbindung eintragen, in den vier Filtern ihre App-ID statt Lanas eintragen, im Weg „Pläne“ ihre Projekt-ID in der Adresse, neuen Webhook anlegen, aktivieren.
   - Im CRM hinterlegen (Claude): `node scripts/setup-make.mjs <kürzel> <flenski-projekt-id> <make-webhook-url> an`
     (`aus` statt `an`: nur vollständige Teilnehmerliste, Pläne entzieht sie selbst.)
6. **Oberfläche einbauen** (Marcel): Custom Page „CRM“ (nur Team sichtbar), Embed-Widget, Code aus `ui/crm.html` mit ihrer Zeile `window.CRM_CONFIG = { tenant: "<kürzel>" }`.
7. **Angebote verbinden** (Lehrerin, im Reiter „Angebote“): pro Plan einmal wählen, was drin steckt.

## Ohne Make
Alles läuft, nur drei Dinge sind Handarbeit bzw. langsamer:
- Neue Pläne erscheinen unter „Angebote“ erst, wenn sie jemand kauft oder zugewiesen bekommt (mit Make: beim Öffnen von „Angebote“ sofort abgeglichen, gelöschte Pläne verschwinden).
- Leere/abgelaufene Karte → Hinweis „Plan entziehen“ in „Heute für dich“, ein Klick im Profil.
- Große Kurse, bei denen Flenski die Namensliste kürzt → „Teilnahme unklar – kurz bestätigen“.

## Bekannte Grenze
Der Flenski-API-Schlüssel darf nur lesen. Bietet Flenski später Schlüssel mit Schreibrechten an, entfällt Schritt 5 (Entscheidung 0007).
