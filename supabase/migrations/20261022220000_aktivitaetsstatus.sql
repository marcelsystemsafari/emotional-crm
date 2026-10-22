-- Phase 3 (neu), Schritt 3: Aktivitätsstatus, Zeitleiste, "Um diese Menschen kümmerst du dich jetzt".
-- Dazu: Beitrittsdatum aus Flenski (member.createdAt), damit "neu" das Neu-in-der-App meint,
-- nicht den Tag des Erstabgleichs.

alter table public.customers add column if not exists joined_at timestamptz;
update public.customers set joined_at = created_at where joined_at is null;
alter table public.customers alter column joined_at set default now();

create or replace function public._upsert_member(p_tenant uuid, p_member jsonb, p_event uuid) returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_profile uuid := nullif(p_member ->> 'id', '')::uuid;
  v_first text := nullif(btrim(p_member ->> 'firstName'), '');
  v_last text := nullif(btrim(p_member ->> 'lastName'), '');
  v_full text := nullif(btrim(p_member ->> 'fullName'), '');
  v_email text := nullif(lower(btrim(p_member ->> 'email')), '');
  v_tags text[] := coalesce(array(select jsonb_array_elements_text(case when jsonb_typeof(p_member -> 'tags') = 'array' then p_member -> 'tags' end)), '{}');
  v_id uuid;
  v_dublette uuid;
  v_ausschluss text[];
  v_joined timestamptz := public._ts(p_member ->> 'createdAt');
begin
  if v_profile is null then return null; end if;
  -- Profile mit Ausschluss-Tag (z. B. "Yogalehrerin") sind keine Kundinnen (tenants.settings.ausschluss_tags)
  select coalesce(array(select jsonb_array_elements_text(settings -> 'ausschluss_tags')), '{}') into v_ausschluss
  from public.tenants where id = p_tenant;
  if v_tags && v_ausschluss then return null; end if;
  if coalesce((p_member ->> 'isMemberOfTeam')::boolean, false) or coalesce((p_member ->> 'isAdmin')::boolean, false) then
    return null;
  end if;
  if v_first is null then
    v_first := coalesce(split_part(v_full, ' ', 1), 'Mitglied');
    v_last := coalesce(v_last, nullif(btrim(substr(v_full, length(split_part(v_full, ' ', 1)) + 1)), ''));
  end if;

  select id into v_id from public.customers where tenant_id = p_tenant and flenski_profile_id = v_profile;
  if v_id is not null then
    update public.customers
    set first_name = v_first, last_name = v_last, email = coalesce(v_email, email),
        tags = (select array(select distinct unnest(tags || v_tags))),
        joined_at = coalesce(v_joined, joined_at)
    where id = v_id and anonymized_at is null;
    return v_id;
  end if;

  insert into public.customers (tenant_id, first_name, last_name, email, source, flenski_profile_id, tags, joined_at)
  values (p_tenant, v_first, v_last, v_email, 'flenski', v_profile, v_tags, coalesce(v_joined, now()))
  returning id into v_id;

  -- Mögliche Dublette: gleiche E-Mail bei einer Person ohne App-Verknüpfung – nicht zusammenführen, nur Hinweis
  if v_email is not null then
    select id into v_dublette from public.customers
    where tenant_id = p_tenant and id <> v_id and lower(email) = v_email and anonymized_at is null limit 1;
    if v_dublette is not null then
      insert into public.customer_notices (tenant_id, customer_id, kind, detail, webhook_event_id)
      values (p_tenant, v_id, 'moegliche_dublette', jsonb_build_object('andere_person', v_dublette), p_event);
    end if;
  end if;
  return v_id;
end $$;

-- ===== Aktivitätsstatus je Person (08-aktivitaet.md, Abschnitt 3) =====
-- Status: neu (Beitritt/erste Aktivität ≤ engagement_neu_tage) · dabei (letzte Aktivität ≤ engagement_aktiv_tage)
--         kuehlt_ab (bis engagement_abkuehlt_tage) · eingeschlafen (länger oder nie aktiv)
-- Aktivität = Studio-Besuche UND App-Aktivität, damit reine Studio-Kundinnen nicht als still gelten.
create or replace view public.v_customer_engagement with (security_invoker = true) as
with basis as (
  select c.id as customer_id, c.tenant_id, c.first_name, c.last_name, c.source, c.is_child, c.tags,
         coalesce(c.joined_at, c.created_at) as joined_at, c.last_visit_at, c.last_app_activity_at,
         greatest(c.last_visit_at, c.last_app_activity_at) as last_activity_at,
         coalesce((t.settings ->> 'engagement_neu_tage')::int, 14) as neu_tage,
         coalesce((t.settings ->> 'engagement_aktiv_tage')::int, 14) as aktiv_tage,
         coalesce((t.settings ->> 'engagement_abkuehlt_tage')::int, 30) as abkuehlt_tage,
         coalesce((t.settings ->> 'gewicht_besuch')::int, 3) as g_besuch,
         coalesce((t.settings ->> 'gewicht_aktiv')::int, 2) as g_aktiv,
         coalesce((t.settings ->> 'gewicht_passiv')::int, 1) as g_passiv
  from public.customers c join public.tenants t on t.id = c.tenant_id
  where c.archived_at is null and c.anonymized_at is null
),
besuche as (
  select a.customer_id, s.starts_at as am
  from public.attendances a join public.sessions s on s.id = a.session_id
  where a.status = 'present'
),
app as (
  select customer_id, occurred_at as am,
         case when type in ('article_read', 'file_downloaded', 'lockscreen_cta') then 'passiv' else 'aktiv' end as art
  from public.activity_events where customer_id is not null
)
select b.customer_id, b.tenant_id, b.first_name, b.last_name, b.source, b.is_child, b.tags, b.joined_at,
       b.last_visit_at, b.last_app_activity_at, b.last_activity_at,
       case
         when b.joined_at >= now() - make_interval(days => b.neu_tage) then 'neu'
         when b.last_activity_at >= now() - make_interval(days => b.aktiv_tage) then 'dabei'
         when b.last_activity_at >= now() - make_interval(days => b.abkuehlt_tage) then 'kuehlt_ab'
         else 'eingeschlafen'
       end as status,
       case when b.last_activity_at is null then null
            else extract(day from now() - b.last_activity_at)::int end as tage_still,
       ( (select count(*) from besuche v where v.customer_id = b.customer_id and v.am between now() - interval '30 days' and now()) * b.g_besuch
       + (select count(*) from app x where x.customer_id = b.customer_id and x.am >= now() - interval '30 days' and x.art = 'aktiv') * b.g_aktiv
       + (select count(*) from app x where x.customer_id = b.customer_id and x.am >= now() - interval '30 days' and x.art = 'passiv') * b.g_passiv
       )::int as score_30d,
       (select count(*) from besuche v where v.customer_id = b.customer_id and v.am <= now())::int as besuche_gesamt,
       array(
         select ((select count(*) from besuche v where v.customer_id = b.customer_id
                    and v.am >= now() - make_interval(days => 7 * (w + 1)) and v.am < now() - make_interval(days => 7 * w))
               + (select count(*) from app x where x.customer_id = b.customer_id
                    and x.am >= now() - make_interval(days => 7 * (w + 1)) and x.am < now() - make_interval(days => 7 * w)))::int
         from generate_series(7, 0, -1) w
       ) as events_8w
from basis b;
grant select on public.v_customer_engagement to authenticated;

-- ===== Verlauf "Gerade passiert" bzw. je Person: App-Aktivität, Besuche, Anmeldungen, Käufe in einer Zeitleiste =====
create or replace function public.activity_feed(p_tenant uuid, p_customer uuid default null, p_limit int default 30)
returns table (customer_id uuid, first_name text, last_name text, am timestamptz, art text, titel text, delta int)
language plpgsql stable security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not public.can_read(p_tenant) then
    raise exception 'Keine Berechtigung für diese Mandantin.' using errcode = '42501';
  end if;
  return query
  select * from (
    select e.customer_id, c.first_name, c.last_name, e.occurred_at, e.type::text, e.title, null::int
    from public.activity_events e join public.customers c on c.id = e.customer_id
    where e.tenant_id = p_tenant and e.type <> 'event_attended'
    union all
    select a.customer_id, c.first_name, c.last_name, s.starts_at,
           case a.status when 'present' then 'besuch' when 'registered' then 'angemeldet'
                         when 'no_show' then 'nicht_erschienen' else 'abgesagt' end,
           s.title,
           (select sum(l.delta)::int from public.ledger_entries l where l.attendance_id = a.id)
    from public.attendances a join public.sessions s on s.id = a.session_id join public.customers c on c.id = a.customer_id
    where a.tenant_id = p_tenant and (a.status <> 'registered' or s.starts_at > now() - interval '1 day')
    union all
    select l.customer_id, c.first_name, c.last_name,
           coalesce(case when l.reason = 'purchase' then en.starts_at end, l.created_at),
           case l.reason when 'purchase' then 'kauf' when 'correction' then 'korrektur' when 'expiry' then 'verfallen' else l.reason::text end,
           p.name || coalesce(' – ' || l.comment, ''), l.delta
    from public.ledger_entries l join public.entitlements en on en.id = l.entitlement_id join public.products p on p.id = en.product_id
    join public.customers c on c.id = l.customer_id
    where l.tenant_id = p_tenant and l.attendance_id is null
    union all
    -- Käufe von Produkten, die noch nicht eingerichtet sind (noch ohne Buchung)
    select en.customer_id, c.first_name, c.last_name, en.starts_at, 'kauf', p.name, null::int
    from public.entitlements en join public.products p on p.id = en.product_id join public.customers c on c.id = en.customer_id
    where en.tenant_id = p_tenant and not exists (select 1 from public.ledger_entries l where l.entitlement_id = en.id and l.reason = 'purchase')
  ) f (customer_id, first_name, last_name, am, art, titel, delta)
  where (p_customer is null or f.customer_id = p_customer)
    and exists (select 1 from public.customers c2 where c2.id = f.customer_id and c2.anonymized_at is null)
  order by f.am desc
  limit p_limit;
end $$;

-- ===== "Um diese Menschen kümmerst du dich jetzt": eine Zeile je Person, Gründe nach Dringlichkeit =====
create or replace function public.care_list(p_tenant uuid)
returns table (customer_id uuid, prio int, gruende jsonb)
language plpgsql stable security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not public.can_read(p_tenant) then
    raise exception 'Keine Berechtigung für diese Mandantin.' using errcode = '42501';
  end if;
  return query
  with g as (
    select n.customer_id,
           case n.kind when 'zahlung_fehlgeschlagen' then 1 when 'abo_gekuendigt' then 1 when 'plan_entzogen' then 2 else 3 end as prio,
           jsonb_build_object('art', n.kind, 'detail', n.detail, 'notice_id', n.id) as grund
    from public.customer_notices n
    where n.tenant_id = p_tenant and n.resolved_at is null and n.customer_id is not null and n.kind <> 'mitglied_geloescht'
    union all
    select s.customer_id,
           case s.signal when 'droht_abzuspringen' then 1 when 'karte_fast_leer' then 2 when 'laeuft_bald_ab' then 2 else 3 end,
           jsonb_build_object('art', s.signal, 'detail', s.detail)
    from public.customer_signals(p_tenant) s
    union all
    select e.customer_id, 2, jsonb_build_object('art', 'kuehlt_ab', 'detail', jsonb_build_object('tage_still', e.tage_still))
    from public.v_customer_engagement e
    where e.tenant_id = p_tenant and e.status = 'kuehlt_ab'
  )
  select g.customer_id, min(g.prio)::int, jsonb_agg(g.grund order by g.prio)
  from g join public.customers c on c.id = g.customer_id
  where c.archived_at is null and c.anonymized_at is null
  group by g.customer_id
  order by min(g.prio), max(c.last_visit_at) nulls first;
end $$;

revoke execute on function public.activity_feed, public.care_list from public, anon;
grant execute on function public.activity_feed, public.care_list to authenticated, service_role;
