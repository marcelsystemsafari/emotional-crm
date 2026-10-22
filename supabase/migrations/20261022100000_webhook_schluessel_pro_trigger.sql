-- Flenski signiert jede Automation mit einem eigenen Schlüssel (X-Flenski-Signature: sha256=<HMAC-SHA256 über den Rohbody>).
-- Der Schlüssel wird nur einmal beim Anlegen angezeigt. Hier liegt er je Mandantin und Trigger.
-- Der Trigger ist derselbe Name wie in der Webhook-URL (?trigger=...). Siehe Entscheidung 0004.

create table public.webhook_trigger_secrets (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references public.tenants (id),
  trigger    text not null,
  secret     text not null,
  created_at timestamptz not null default now(),
  unique (tenant_id, trigger)
);

-- Nur der Server (Service-Role) darf Schlüssel lesen
alter table public.webhook_trigger_secrets enable row level security;
revoke all on public.webhook_trigger_secrets from anon, authenticated;

-- Das alte Mandanten-Secret wird für die Signatur nicht gebraucht (Flenski vergibt die Schlüssel selbst)
comment on column public.tenants.webhook_secret is 'Reserve, derzeit ungenutzt: Flenski-Schlüssel liegen in webhook_trigger_secrets';
