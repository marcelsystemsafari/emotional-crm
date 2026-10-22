-- Phase 1, Schritt 2: Kundinnen, Produkte, Stunden, Aktivität (nur Tabelle) und Änderungsprotokoll.
-- Verweise zwischen Tabellen laufen immer über (tenant_id, id), damit nichts über Mandantengrenzen zeigt.

create type public.customer_source as enum ('flenski', 'extern');
create type public.product_type as enum ('credits', 'period', 'subscription', 'single');
create type public.activity_type as enum (
  'course_enrolled', 'course_completed', 'post_created', 'comment_created', 'question_asked',
  'event_attended', 'file_downloaded', 'article_read', 'other');

create table public.customers (
  id                   uuid primary key default gen_random_uuid(),
  tenant_id            uuid not null references public.tenants (id),
  first_name           text not null,
  last_name            text,
  email                text,
  phone                text,
  source               public.customer_source not null default 'extern',
  flenski_profile_id   uuid,
  -- Kinderkurse: Kontakt läuft über die Eltern
  is_child             boolean not null default false,
  guardian_name        text,
  guardian_email       text,
  guardian_phone       text,
  tags                 text[] not null default '{}',
  -- nur Organisatorisches, keine Gesundheitsangaben (07-datenschutz.md)
  note                 text,
  archived_at          timestamptz,
  anonymized_at        timestamptz,
  -- denormalisiert für schnelle Filter, gepflegt per Trigger (Besuche) bzw. Webhook (App)
  last_visit_at        timestamptz,
  last_app_activity_at timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, flenski_profile_id)
);
create index customers_tenant_name_idx on public.customers (tenant_id, lower(first_name), lower(last_name));
create index customers_tenant_email_idx on public.customers (tenant_id, lower(email));

create table public.products (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenants (id),
  name            text not null,
  type            public.product_type not null,
  -- Einheiten bei credits/single; bei subscription später Monatskontingent (MVP: unbegrenzt)
  credits         int,
  validity_days   int check (validity_days > 0),
  price_cents     int check (price_cents >= 0),
  flenski_plan_id uuid,
  -- steuert, für welche Stunden das Produkt gilt; null = alle
  category        text,
  active          boolean not null default true,
  created_at      timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, flenski_plan_id),
  check (case type
           when 'credits' then credits > 0
           when 'single' then credits = 1
           else credits is null end)
);

create table public.sessions (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants (id),
  title            text not null,
  starts_at        timestamptz not null,
  ends_at          timestamptz,
  category         text,
  flenski_event_id uuid,
  capacity         int check (capacity > 0),
  created_at       timestamptz not null default now(),
  unique (tenant_id, id),
  check (ends_at is null or ends_at > starts_at)
);
create index sessions_tenant_start_idx on public.sessions (tenant_id, starts_at desc);
-- ein Flenski-Event kann mehrere Termine haben, daher eindeutig nur zusammen mit dem Beginn
create unique index sessions_flenski_event_idx on public.sessions (tenant_id, flenski_event_id, starts_at)
  where flenski_event_id is not null;

-- Modul Aktivität (08): Ereignisart, Zeitpunkt, Titel – nie Inhalte. Wird ab Phase 3 vom Webhook befüllt.
create table public.activity_events (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references public.tenants (id),
  customer_id        uuid,
  flenski_profile_id uuid not null,
  type               public.activity_type not null,
  title              text,
  occurred_at        timestamptz not null,
  webhook_event_id   uuid references public.webhook_events (id) on delete set null,
  dedupe_key         text not null,
  created_at         timestamptz not null default now(),
  unique (tenant_id, dedupe_key),
  foreign key (tenant_id, customer_id) references public.customers (tenant_id, id) on delete cascade
);
create index activity_events_customer_idx on public.activity_events (tenant_id, customer_id, occurred_at desc);

create table public.audit_log (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references public.tenants (id),
  actor      uuid,
  action     text not null,
  entity     text not null,
  entity_id  uuid,
  diff       jsonb,
  created_at timestamptz not null default now()
);
create index audit_log_tenant_idx on public.audit_log (tenant_id, created_at desc);

-- Änderungsprotokoll. Bei Kundinnen nur die geänderten Feldnamen, keine Werte:
-- sonst blieben Personendaten nach einer Löschung im Protokoll stehen (07-datenschutz.md).
create function public.audit_row() returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare
  v_old jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  v_new jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  v_diff jsonb;
begin
  if tg_op = 'UPDATE' then
    select jsonb_object_agg(key, value) into v_diff
    from jsonb_each(v_new) where v_old -> key is distinct from value and key not in ('updated_at');
    if v_diff is null then return new; end if;
  else
    v_diff := coalesce(v_new, v_old);
  end if;
  if tg_table_name = 'customers' then
    v_diff := to_jsonb(array(select jsonb_object_keys(v_diff)));
  end if;
  if tg_table_name = 'tenants' then
    v_diff := v_diff - 'webhook_secret';
  end if;
  insert into public.audit_log (tenant_id, actor, action, entity, entity_id, diff)
  values ((coalesce(v_new, v_old) ->> case when tg_table_name = 'tenants' then 'id' else 'tenant_id' end)::uuid,
          auth.uid(), lower(tg_op), tg_table_name, (coalesce(v_new, v_old) ->> 'id')::uuid, v_diff);
  return coalesce(new, old);
end $$;

create function public.touch_updated_at() returns trigger
language plpgsql
set search_path = ''
as $$ begin new.updated_at := now(); return new; end $$;

create trigger customers_updated_at before update on public.customers
  for each row execute function public.touch_updated_at();
create trigger customers_audit after insert or update on public.customers
  for each row execute function public.audit_row();
create trigger products_audit after insert or update on public.products
  for each row execute function public.audit_row();
create trigger tenants_audit after update on public.tenants
  for each row execute function public.audit_row();

-- Zugriff
alter table public.customers enable row level security;
alter table public.products enable row level security;
alter table public.sessions enable row level security;
alter table public.activity_events enable row level security;
alter table public.audit_log enable row level security;

grant select, insert, update on public.customers to authenticated;
create policy customers_lesen on public.customers for select to authenticated using (public.can_read(tenant_id));
create policy customers_anlegen on public.customers for insert to authenticated with check (public.can_write(tenant_id));
create policy customers_aendern on public.customers for update to authenticated
  using (public.can_write(tenant_id)) with check (public.can_write(tenant_id));

grant select, insert, update on public.products to authenticated;
create policy products_lesen on public.products for select to authenticated using (public.can_read(tenant_id));
create policy products_anlegen on public.products for insert to authenticated with check (public.is_owner(tenant_id));
create policy products_aendern on public.products for update to authenticated
  using (public.is_owner(tenant_id)) with check (public.is_owner(tenant_id));

grant select, insert, update, delete on public.sessions to authenticated;
create policy sessions_lesen on public.sessions for select to authenticated using (public.can_read(tenant_id));
create policy sessions_anlegen on public.sessions for insert to authenticated with check (public.can_write(tenant_id));
create policy sessions_aendern on public.sessions for update to authenticated
  using (public.can_write(tenant_id)) with check (public.can_write(tenant_id));
create policy sessions_loeschen on public.sessions for delete to authenticated using (public.can_write(tenant_id));

-- Aktivität: lesen ja, schreiben nur der Server (Webhook)
grant select on public.activity_events to authenticated;
create policy activity_lesen on public.activity_events for select to authenticated using (public.can_read(tenant_id));

-- Protokoll: nur owner liest, geschrieben wird ausschließlich per Trigger/Funktion
grant select on public.audit_log to authenticated;
create policy audit_lesen on public.audit_log for select to authenticated using (public.is_owner(tenant_id));
