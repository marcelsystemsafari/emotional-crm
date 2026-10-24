-- Anmeldung bei Flenski mit Zugangscode (Marcel, 24.10.2026, siehe docs/04 "Lösung gefunden").
-- Der 36-stellige Profil-Schlüssel wird von der Flenski-Schnittstelle nicht erkannt. Flenski erwartet
-- "Authorization: Bearer <Zugangscode>" – den Code einer eingeloggten Sitzung. Er läuft nach einigen Monaten ab;
-- mit dem Erneuerungscode (refreshToken, gilt ein Jahr und verlängert sich) holt flenski-sync rechtzeitig selbst
-- einen neuen (POST /api/v1/auth/refresh-token). Klappt das nicht, bekommt Systemsafari einen Hinweis.

alter table public.tenant_secrets add column if not exists flenski_auth text;
alter table public.tenant_secrets add column if not exists flenski_refresh text;
alter table public.tenant_secrets add column if not exists flenski_auth_expires timestamptz;
alter table public.tenant_secrets add column if not exists flenski_auth_fehler text;
alter table public.tenant_secrets alter column flenski_api_key drop not null;
