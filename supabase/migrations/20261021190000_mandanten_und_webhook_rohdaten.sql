-- Phase 0: Mandanten und Webhook-Mitschnitt
-- Jede Anfrage von Flenski wird unverändert in webhook_events gespeichert (erst speichern, dann verarbeiten).
-- Verarbeitung kommt in Phase 3. Siehe docs/03-datenmodell.md und docs/05-phasen.md.

create type public.tenant_status as enum ('trial', 'active', 'cancelled', 'dormant', 'deleted');

create table public.tenants (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null,
  slug               text not null unique,
  timezone           text not null default 'Europe/Berlin',
  status             public.tenant_status not null default 'trial',
  dormant_consent_at timestamptz,
  delete_after       date,
  flenski_app_url    text,
  -- nur serverseitig lesbar; Policies für tenant_members kommen in Phase 1 und dürfen diese Spalte nicht freigeben
  webhook_secret     text not null default encode(extensions.gen_random_bytes(32), 'hex'),
  settings           jsonb not null default '{}'::jsonb,
  created_at         timestamptz not null default now()
);

create table public.webhook_events (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenants (id),
  -- Triggername aus der Webhook-URL (?trigger=...), weil unbekannt ist, ob Flenski ihn im Body mitschickt
  trigger         text,
  headers         jsonb not null default '{}'::jsonb,
  -- null, wenn der Body kein gültiges JSON war
  payload         jsonb,
  -- unveränderter Body: Die Signatur X-Flenski-Signature wird über die Rohbytes berechnet, jsonb ordnet Schlüssel um
  raw_body        text not null,
  signature_valid boolean,
  -- Phase 0: SHA-256 des Rohbodys. TODO Phase 3: aus echten Payloads eine fachliche Ereignis-ID ableiten
  dedupe_key      text not null,
  received_at     timestamptz not null default now(),
  processed_at    timestamptz,
  error           text,
  created_at      timestamptz not null default now(),
  unique (tenant_id, dedupe_key)
);

create index webhook_events_tenant_received_idx on public.webhook_events (tenant_id, received_at desc);

-- Nur der Server (Service-Role) darf in Phase 0 an diese Tabellen. RLS ohne Policies = kein Zugriff für Browser-Nutzer.
alter table public.tenants enable row level security;
alter table public.webhook_events enable row level security;
revoke all on public.tenants from anon, authenticated;
revoke all on public.webhook_events from anon, authenticated;

-- Erste Mandantin (Werte aus inbox/tenants/yoga-by-lana.json; ??? dort = hier null)
insert into public.tenants (name, slug, timezone, flenski_app_url, settings)
values (
  'Yoga by Lana',
  'yoga-by-lana',
  'Europe/Berlin',
  'https://appdemo.systemsafari.de/yoga-by-lana',
  '{
    "storno_frist_stunden": null,
    "abzug_bei_spaeter_absage": true,
    "abzug_bei_no_show": true,
    "signal_inaktiv_tage": 21,
    "signal_ablauf_tage": 14,
    "signal_fast_leer_ab": 1,
    "engagement_neu_tage": 14,
    "engagement_aktiv_tage": 14,
    "engagement_abkuehlt_tage": 30
  }'::jsonb
)
on conflict (slug) do nothing;
