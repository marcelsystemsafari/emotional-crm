-- Phase 2, Schritt 1: Datenbank-Helfer für die Oberfläche (docs/phase2-plan.md).

-- Entscheidung 22.10.2026: Korrigieren nur owner (Staff darf einchecken und verkaufen)
create or replace function public.correct(p_entitlement uuid, p_delta int, p_comment text) returns int
language plpgsql security definer
set search_path = ''
as $$
declare
  v_karte public.entitlements;
begin
  select * into v_karte from public.entitlements where id = p_entitlement;
  if not found then raise exception 'Karte nicht gefunden.' using errcode = 'P0002'; end if;
  if not public.is_owner(v_karte.tenant_id) then
    raise exception 'Korrekturen darf nur die Inhaberin machen.' using errcode = '42501';
  end if;
  if coalesce(length(btrim(p_comment)), 0) = 0 then
    raise exception 'Bitte gib einen Grund für die Korrektur an.' using errcode = '23514';
  end if;
  if coalesce(p_delta, 0) = 0 then
    raise exception 'Die Korrektur muss mindestens +1 oder −1 sein.' using errcode = '23514';
  end if;
  insert into public.ledger_entries (tenant_id, entitlement_id, customer_id, delta, reason, created_by, comment)
  values (v_karte.tenant_id, p_entitlement, v_karte.customer_id, p_delta, 'correction', auth.uid(), btrim(p_comment));
  return (select balance from public.v_entitlement_balance where entitlement_id = p_entitlement);
end $$;

-- Überblick je Kundin: zusätzlich Produktnamen der aktiven Karten (Filter "Produkt") und Kinder-/Elternangaben
create or replace view public.v_customer_overview with (security_invoker = true) as
select c.id as customer_id, c.tenant_id, c.first_name, c.last_name, c.email, c.phone, c.source,
       c.is_child, c.tags, c.archived_at, c.last_visit_at, c.last_app_activity_at, c.created_at,
       coalesce(sum(b.balance) filter (where b.status = 'active' and not b.unlimited), 0)::int as credits_balance,
       coalesce(bool_or(b.unlimited) filter (where b.status = 'active'), false) as has_unlimited,
       min(b.expires_at) filter (where b.status = 'active') as next_expiry,
       (count(b.entitlement_id) filter (where b.status = 'active'))::int as active_entitlements,
       coalesce(array_agg(distinct b.product_name) filter (where b.status = 'active'), '{}') as active_products,
       c.guardian_name, c.anonymized_at
from public.customers c
left join public.v_entitlement_balance b on b.customer_id = c.id
group by c.id;

-- Verlauf je Kundin: jede Buchung mit Produkt und Stunde (belegt jede Zahl)
create view public.v_customer_history with (security_invoker = true) as
select l.id, l.tenant_id, l.customer_id, l.entitlement_id, l.created_at, l.delta, l.reason, l.comment, l.created_by,
       p.name as product_name, s.title as session_title, s.starts_at as session_starts_at
from public.ledger_entries l
join public.entitlements e on e.id = l.entitlement_id
join public.products p on p.id = e.product_id
left join public.attendances a on a.id = l.attendance_id
left join public.sessions s on s.id = a.session_id;
grant select on public.v_customer_history to authenticated;

-- Team einer Mandantin mit E-Mail (für "gebucht von" und die Seite "Mehr")
create function public.team_members(p_tenant uuid)
returns table (user_id uuid, email text, role public.member_role)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not public.can_read(p_tenant) then
    raise exception 'Keine Berechtigung für diese Mandantin.' using errcode = '42501';
  end if;
  return query
  select m.user_id, u.email::text, m.role from public.tenant_members m join auth.users u on u.id = m.user_id
  where m.tenant_id = p_tenant order by m.role, u.email;
end $$;

-- Teilnehmerliste einer Stunde in einer Abfrage: Status, belastete Karte, Restguthaben
create function public.session_roster(p_session uuid)
returns table (
  attendance_id uuid, customer_id uuid, first_name text, last_name text, is_child boolean,
  status public.attendance_status, checked_in_at timestamptz,
  entitlement_id uuid, abgebucht boolean, unbegrenzt boolean, rest int, von int, gueltig_bis timestamptz,
  credits_balance int, has_unlimited boolean, next_expiry timestamptz)
language plpgsql stable security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  select tenant_id into v_tenant from public.sessions where id = p_session;
  if v_tenant is null or not public.can_read(v_tenant) then
    raise exception 'Stunde nicht gefunden.' using errcode = 'P0002';
  end if;
  return query
  select a.id, a.customer_id, c.first_name, c.last_name, c.is_child,
         a.status, a.checked_in_at,
         a.entitlement_id, public._netto_abzug(a.id) < 0, coalesce(b.unlimited, false), b.balance, b.product_credits, b.expires_at,
         o.credits_balance, o.has_unlimited, o.next_expiry
  from public.attendances a
  join public.customers c on c.id = a.customer_id
  join public.v_customer_overview o on o.customer_id = a.customer_id
  left join public.v_entitlement_balance b on b.entitlement_id = a.entitlement_id
  where a.session_id = p_session
  order by c.first_name, c.last_name;
end $$;

-- Vorschläge für einen Tag: Stunden der Vorwoche (gleicher Wochentag), die es am Tag noch nicht gibt
create function public.session_suggestions(p_tenant uuid, p_day date)
returns table (source_session uuid, title text, starts_at timestamptz, ends_at timestamptz, category text)
language plpgsql stable security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tz text;
begin
  if not public.can_read(p_tenant) then
    raise exception 'Keine Berechtigung für diese Mandantin.' using errcode = '42501';
  end if;
  select timezone into v_tz from public.tenants where id = p_tenant;
  return query
  select s.id, s.title,
         ((s.starts_at at time zone v_tz) + interval '7 days') at time zone v_tz,
         ((s.ends_at at time zone v_tz) + interval '7 days') at time zone v_tz,
         s.category
  from public.sessions s
  where s.tenant_id = p_tenant
    and (s.starts_at at time zone v_tz)::date = p_day - 7
    and not exists (
      select 1 from public.sessions n
      where n.tenant_id = p_tenant and n.title = s.title
        and n.starts_at = ((s.starts_at at time zone v_tz) + interval '7 days') at time zone v_tz)
  order by s.starts_at;
end $$;

-- Stunde übernehmen (Standard: eine Woche später, gleiche Uhrzeit auch über die Zeitumstellung)
create function public.copy_session(p_session uuid, p_days int default 7) returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  v_s public.sessions;
  v_tz text;
  v_id uuid;
begin
  select * into v_s from public.sessions where id = p_session;
  if not found then raise exception 'Stunde nicht gefunden.' using errcode = 'P0002'; end if;
  perform public._require_write(v_s.tenant_id);
  select timezone into v_tz from public.tenants where id = v_s.tenant_id;
  insert into public.sessions (tenant_id, title, starts_at, ends_at, category, capacity)
  values (v_s.tenant_id, v_s.title,
          ((v_s.starts_at at time zone v_tz) + make_interval(days => p_days)) at time zone v_tz,
          ((v_s.ends_at at time zone v_tz) + make_interval(days => p_days)) at time zone v_tz,
          v_s.category, v_s.capacity)
  returning id into v_id;
  -- wer letzte Woche da war, steht schon auf der Liste (angemeldet, noch nicht eingecheckt) – spart Tipparbeit
  insert into public.attendances (tenant_id, session_id, customer_id)
  select a.tenant_id, v_id, a.customer_id
  from public.attendances a join public.customers c on c.id = a.customer_id
  where a.session_id = p_session and a.status = 'present' and c.archived_at is null;
  return v_id;
end $$;

revoke execute on function public.team_members, public.session_roster, public.session_suggestions, public.copy_session
  from public, anon;
grant execute on function public.team_members, public.session_roster, public.session_suggestions, public.copy_session
  to authenticated, service_role;
