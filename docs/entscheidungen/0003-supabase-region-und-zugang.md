# 0003 – Supabase-Region Irland und CLI-Zugang per Schlüssel

Datum: 21.10.2026
Status: entschieden

## Kontext

Laut 02 und 07 sollte das Supabase-Projekt in Frankfurt (`eu-central-1`) liegen. Beim Anlegen bot Supabase nur die Sammelregion „Europe“ an und wählte selbst Irland (`eu-west-1`). Ein gezieltes Frankfurt-Projekt hätte im kostenlosen Tarif das Löschen eines Projekts erfordert.

Außerdem scheitert `supabase login` auf Marcels Rechner: Norton 360 prüft verschlüsselte Verbindungen und bricht die Anmeldung der CLI ab.

## Entscheidung

1. Projekt `emotional-crm` (Ref `aipnvftsuhnffkvnrygt`) in **Irland** wird verwendet. Irland ist EU, die DSGVO gilt unverändert.
2. Die CLI liegt als `.tools/supabase.exe` im Projekt (nicht im Git) und arbeitet mit `SUPABASE_ACCESS_TOKEN` und `SUPABASE_DB_PASSWORD` aus `.env.local` statt mit `supabase login`.

## Folgen

- In der AVV und der Unterauftragsverarbeiter-Liste steht Supabase mit Region Irland (`eu-west-1`).
- Das alte Projekt „info@systemsafari.de's Project“ wird nicht genutzt und kann gelöscht werden.
- Läuft der Zugangsschlüssel ab oder wird widerrufen, muss Marcel einen neuen mit vollem Zugriff in `.env.local` eintragen.
