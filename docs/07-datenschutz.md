# 07 – Datenschutz (Leitplanken für den Bau)

Keine Rechtsberatung, sondern technische Leitplanken. Vor dem ersten zahlenden Mandanten einmal juristisch prüfen lassen.

## Rollen

- Die **Lehrerin** ist Verantwortliche für die Daten ihrer Kundinnen.
- **Systemsafari** ist Auftragsverarbeiter (Art. 28 DSGVO) → AVV pro Mandantin nötig.
- Supabase ist Unterauftragsverarbeiter → EU-Region wählen, in der AVV benennen. (Flenski selbst ist Vertragspartner der Lehrerin, nicht von Systemsafari.)

## Folgen für den Code

1. **Datensparsamkeit:** Nur Felder aus 03-datenmodell.md. Keine Geburtsdaten von Kindern, keine Adressen im MVP.
2. **Keine Gesundheitsdaten.** Yogalehrerinnen notieren gern Verletzungen („Bandscheibe"). Das sind besondere Kategorien (Art. 9) mit hohen Anforderungen. Deshalb:
   - Das Notizfeld trägt den sichtbaren Hinweis „Bitte keine Gesundheitsangaben".
   - Kein eigenes Feld für Beschwerden, Einschränkungen o. Ä.
3. **Export (Art. 20) und Löschung (Art. 17, Art. 28 Abs. 3 lit. g):**
   - Export pro Kundin und pro Mandant als CSV.
   - Löschen einer Kundin = Personendaten entfernen/anonymisieren; Buchungen bleiben anonym erhalten (Summen stimmen weiter).
   - Mandant gekündigt → nach 30 Tagen automatische Löschung aller personenbezogenen Daten (geplanter Job), Protokolleintrag.
   - Ausnahme Ruhemodus: nur wenn die Lehrerin bei Kündigung ausdrücklich zustimmt (dokumentiert, mit Datum), Aufbewahrung bis max. 12 Monate, danach Löschung. Erinnerung 30 Tage vor Löschung.
4. **Zugriff protokollieren:** `audit_log` für Änderungen; Exporte ebenfalls protokollieren.
5. **Hosting:** Supabase `eu-west-1` Irland (Datenbank, Login, Edge Functions). Keine US-Analytics, keine Tracking-Skripte im CRM. CDN-Bibliotheken nur von etablierten Quellen (jsDelivr) mit fester Versionsnummer.
6. **Secrets:** Service-Role-Key und Webhook-Secrets nur serverseitig, nie im Browser, nie im Repo.
7. **Aktivitätsdaten (Modul 08):** Nur Ereignisart, Zeitpunkt, Titel; nie Inhalte. Rollierend 12 Monate. Verhaltensauswertung muss in der Datenschutzerklärung der Lehrerin genannt sein. Anzeige nur für `owner`/`staff`; bei Löschung einer Kundin werden ihre Aktivitätsdaten mit entfernt.
