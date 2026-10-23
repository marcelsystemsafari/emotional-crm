-- Make-Adresse je Mandantin (Marcel, 23.10.2026): Jede Lehrerin bekommt am Einrichtungstag ihre eigene
-- Flenski-Verbindung in Make und eine Kopie des Szenarios "ECRM: Flenski-Aktionen" (nur für ihre App freigeschaltet).
-- Das CRM ruft pro Lehrerin ihre eigene Make-Adresse auf. Ohne Adresse: kein Make, Hinweise für die Lehrerin wie bisher.
-- Die Adresse wird wie ein Schlüssel behandelt: nur per scripts/setup-make.mjs eintragen, nie in Migrationen oder Git.

alter table public.tenant_secrets add column if not exists make_webhook_url text;
