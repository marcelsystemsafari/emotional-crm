-- Phase 1, Schritt 3: Karten (entitlements), Anwesenheit (attendances) und Buchungsprotokoll (ledger_entries).
-- Harte Regel 1: Guthaben = Summe der Buchungen. Buchungen werden nie geändert oder gelöscht.
-- Schreiben nur über die Fachfunktionen aus Schritt 4 (Regel 6), Nutzerinnen haben hier nur Leserechte.

create type public.entitlement_source as enum ('flenski_order', 'flenski_plan', 'manual');
create type public.paid_via as enum ('app', 'bar', 'ueberweisung', 'verein', 'gutschein', 'sonstiges');
create type public.entitlement_status as enum ('active', 'used_up', 'expired', 'cancelled');
create type public.ledger_reason as enum ('purchase', 'visit', 'refund', 'correction', 'expiry', 'transfer');
create type public.attendance_status as enum ('registered', 'present', 'cancelled_in_time', 'cancelled_late', 'no_show');

create table public.entitlements (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenants (id),
  customer_id  uuid not null,
  product_id   uuid not null,
  source       public.entitlement_source not null default 'manual',
  paid_via     public.paid_via,
  -- tatsächlich bezahlt, kann vom Produktpreis abweichen
  price_cents  int check (price_cents >= 0),
  starts_at    timestamptz not null default now(),
  expires_at   timestamptz,
  -- abgeleitet, wird nach jeder Buchung neu bestimmt
  status       public.entitlement_status not null default 'active',
  external_ref text,
  created_by   uuid,
  created_at   timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, id, customer_id),
  foreign key (tenant_id, customer_id) references public.customers (tenant_id, id),
  foreign key (tenant_id, product_id) references public.products (tenant_id, id),
  check (expires_at is null or expires_at > starts_at)
);
create index entitlements_customer_idx on public.entitlements (tenant_id, customer_id, status);

create table public.attendances (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants (id),
  session_id     uuid not null,
  customer_id    uuid not null,
  status         public.attendance_status not null default 'registered',
  -- welche Karte belastet wurde (null = ohne Abzug oder "offen / ohne Guthaben")
  entitlement_id uuid,
  checked_in_by  uuid,
  checked_in_at  timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (tenant_id, id),
  unique (session_id, customer_id),
  foreign key (tenant_id, session_id) references public.sessions (tenant_id, id),
  foreign key (tenant_id, customer_id) references public.customers (tenant_id, id),
  foreign key (tenant_id, entitlement_id) references public.entitlements (tenant_id, id)
);
create index attendances_customer_idx on public.attendances (tenant_id, customer_id);

create table public.ledger_entries (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants (id),
  entitlement_id uuid not null,
  customer_id    uuid not null,
  delta          int not null check (delta <> 0),
  reason         public.ledger_reason not null,
  attendance_id  uuid,
  -- null = System (z. B. nächtlicher Verfall)
  created_by     uuid,
  comment        text,
  created_at     timestamptz not null default now(),
  -- Kundin der Buchung muss die Kundin der Karte sein
  foreign key (tenant_id, entitlement_id, customer_id) references public.entitlements (tenant_id, id, customer_id),
  foreign key (tenant_id, attendance_id) references public.attendances (tenant_id, id),
  check (reason <> 'correction' or coalesce(length(btrim(comment)), 0) > 0)
);
create index ledger_entitlement_idx on public.ledger_entries (entitlement_id);
create index ledger_customer_idx on public.ledger_entries (tenant_id, customer_id, created_at desc);

-- Buchungen sind unveränderlich – für alle, auch für den Server
create function public.ledger_unveraenderlich() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Buchungen können nicht geändert oder gelöscht werden. Korrekturen nur als Gegenbuchung mit Kommentar.'
    using errcode = 'P0001';
end $$;
create trigger ledger_kein_update_delete before update or delete on public.ledger_entries
  for each row execute function public.ledger_unveraenderlich();
create trigger ledger_kein_truncate before truncate on public.ledger_entries
  for each statement execute function public.ledger_unveraenderlich();

-- Status einer Karte aus Buchungen und Ablaufdatum ableiten
create function public.refresh_entitlement_status(p_entitlement uuid) returns void
language sql security definer
set search_path = ''
as $$
  update public.entitlements e
  set status = s.neu
  from (
    select e2.id,
           case
             when e2.status = 'cancelled' then 'cancelled'
             when e2.expires_at is not null and e2.expires_at <= now() then 'expired'
             when p.type in ('credits', 'single')
                  and (select coalesce(sum(l.delta), 0) from public.ledger_entries l where l.entitlement_id = e2.id) <= 0
               then 'used_up'
             else 'active'
           end::public.entitlement_status as neu
    from public.entitlements e2 join public.products p on p.id = e2.product_id
    where e2.id = p_entitlement
  ) s
  where e.id = s.id and e.status is distinct from s.neu
$$;

create function public.ledger_nach_buchung() returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  perform public.refresh_entitlement_status(new.entitlement_id);
  return new;
end $$;
create trigger ledger_status_aktualisieren after insert on public.ledger_entries
  for each row execute function public.ledger_nach_buchung();

-- letzter Besuch einer Kundin = Beginn der letzten Stunde, bei der sie anwesend war
create function public.attendance_letzter_besuch() returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  update public.customers c
  set last_visit_at = (
    select max(s.starts_at) from public.attendances a join public.sessions s on s.id = a.session_id
    where a.customer_id = new.customer_id and a.status = 'present')
  where c.id = new.customer_id;
  return null;
end $$;
create trigger attendances_letzter_besuch after insert or update on public.attendances
  for each row execute function public.attendance_letzter_besuch();
create trigger attendances_updated_at before update on public.attendances
  for each row execute function public.touch_updated_at();

-- Restguthaben je Karte
create view public.v_entitlement_balance with (security_invoker = true) as
select e.id as entitlement_id, e.tenant_id, e.customer_id, e.product_id,
       p.name as product_name, p.type as product_type, p.credits as product_credits, p.category,
       p.type in ('period', 'subscription') as unlimited,
       e.source, e.paid_via, e.price_cents, e.starts_at, e.expires_at, e.status, e.created_at,
       coalesce(l.balance, 0)::int as balance
from public.entitlements e
join public.products p on p.id = e.product_id
left join (select entitlement_id, sum(delta) as balance from public.ledger_entries group by entitlement_id) l
  on l.entitlement_id = e.id;

-- Überblick je Kundin
create view public.v_customer_overview with (security_invoker = true) as
select c.id as customer_id, c.tenant_id, c.first_name, c.last_name, c.email, c.phone, c.source,
       c.is_child, c.tags, c.archived_at, c.last_visit_at, c.last_app_activity_at, c.created_at,
       coalesce(sum(b.balance) filter (where b.status = 'active' and not b.unlimited), 0)::int as credits_balance,
       coalesce(bool_or(b.unlimited) filter (where b.status = 'active'), false) as has_unlimited,
       min(b.expires_at) filter (where b.status = 'active') as next_expiry,
       (count(b.entitlement_id) filter (where b.status = 'active'))::int as active_entitlements
from public.customers c
left join public.v_entitlement_balance b on b.customer_id = c.id
group by c.id;

-- Zugriff: nur lesen
alter table public.entitlements enable row level security;
alter table public.attendances enable row level security;
alter table public.ledger_entries enable row level security;

grant select on public.entitlements, public.attendances, public.ledger_entries to authenticated;
grant select on public.v_entitlement_balance, public.v_customer_overview to authenticated;
create policy entitlements_lesen on public.entitlements for select to authenticated using (public.can_read(tenant_id));
create policy attendances_lesen on public.attendances for select to authenticated using (public.can_read(tenant_id));
create policy ledger_lesen on public.ledger_entries for select to authenticated using (public.can_read(tenant_id));

revoke execute on function public.refresh_entitlement_status from public, anon, authenticated;
