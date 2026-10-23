-- Plan zurückgeben, wenn eine leere Karte wieder aufgefüllt wird (Marcel, 23.10.2026: "+1 statt 0").
-- Karte wird wieder aktiv und der Plan war vom CRM entzogen → Hinweis "plan_zurueckgeben" → flenski-sync weist
-- den Plan in der App wieder zu (POST /apps/{appId}/profiles/plans). Die anschließende Flenski-Meldung
-- "Plan zugewiesen" legt dann keine neue Karte an (ein Kauf in der App weiterhin schon).
-- Solange das automatisch läuft, stehen Entzug und Rückgabe nicht in "Heute für dich" (erst nach 3 Fehlversuchen).

alter table public.entitlements add column if not exists flenski_plan_restored_at timestamptz;

create or replace function public.karte_status_hinweis() returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare
  v_prod public.products;
begin
  select * into v_prod from public.products where id = new.product_id;
  if v_prod.flenski_plan_id is null then return new; end if;

  if new.status in ('used_up', 'expired') and old.status = 'active' then
    -- eine offene Rückgabe ist hinfällig
    update public.customer_notices set resolved_at = now(), detail = detail || '{"erledigt": "Karte wieder leer"}'
    where customer_id = new.customer_id and kind = 'plan_zurueckgeben' and resolved_at is null
      and detail ->> 'entitlement_id' = new.id::text;
    if new.flenski_plan_revoked_at is null and not exists (
         select 1 from public.customer_notices n where n.customer_id = new.customer_id and n.kind = 'plan_entziehen'
           and n.resolved_at is null and n.detail ->> 'entitlement_id' = new.id::text) then
      insert into public.customer_notices (tenant_id, customer_id, kind, detail)
      values (new.tenant_id, new.customer_id, 'plan_entziehen',
              jsonb_build_object('entitlement_id', new.id, 'produkt', v_prod.name, 'plan', v_prod.name,
                                 'grund', case new.status when 'expired' then 'abgelaufen' else 'aufgebraucht' end));
    end if;
  elsif new.status = 'active' and old.status in ('used_up', 'expired') then
    update public.customer_notices set resolved_at = now()
    where customer_id = new.customer_id and kind = 'plan_entziehen' and resolved_at is null
      and detail ->> 'entitlement_id' = new.id::text;
    -- Plan war schon entzogen: zurückgeben
    if new.flenski_plan_revoked_at is not null and not exists (
         select 1 from public.customer_notices n where n.customer_id = new.customer_id and n.kind = 'plan_zurueckgeben'
           and n.resolved_at is null and n.detail ->> 'entitlement_id' = new.id::text) then
      insert into public.customer_notices (tenant_id, customer_id, kind, detail)
      values (new.tenant_id, new.customer_id, 'plan_zurueckgeben',
              jsonb_build_object('entitlement_id', new.id, 'produkt', v_prod.name, 'plan', v_prod.name));
    end if;
  end if;
  return new;
end $$;

create or replace function public.flenski_offene_rueckgaben(p_tenant uuid)
returns table (notice_id uuid, email text, plan_id uuid, produkt text)
language plpgsql security definer
set search_path = ''
as $$
begin
  if not public.is_system() then
    raise exception 'Nur für den automatischen Abgleich.' using errcode = '42501';
  end if;
  return query
  select n.id, c.email, p.flenski_plan_id, p.name
  from public.customer_notices n
  join public.tenants t on t.id = n.tenant_id
  join public.entitlements e on e.id = (n.detail ->> 'entitlement_id')::uuid
  join public.products p on p.id = e.product_id
  join public.customers c on c.id = e.customer_id
  where n.tenant_id = p_tenant and n.kind = 'plan_zurueckgeben' and n.resolved_at is null
    and coalesce((t.settings ->> 'plan_entzug_automatisch')::boolean, false)
    and e.status = 'active' and e.flenski_plan_revoked_at is not null
    and p.flenski_plan_id is not null and nullif(c.email, '') is not null and c.anonymized_at is null
    and coalesce((n.detail ->> 'versuche')::int, 0) < 3;
end $$;

create or replace function public.flenski_rueckgabe_ergebnis(p_notice uuid, p_ok boolean, p_info text) returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if not public.is_system() then
    raise exception 'Nur für den automatischen Abgleich.' using errcode = '42501';
  end if;
  if p_ok then
    update public.entitlements set flenski_plan_revoked_at = null, flenski_plan_restored_at = now()
    where id = (select (detail ->> 'entitlement_id')::uuid from public.customer_notices where id = p_notice);
    update public.customer_notices set resolved_at = now(), detail = detail || jsonb_build_object('automatisch', true)
    where id = p_notice;
  else
    update public.customer_notices
    set detail = detail || jsonb_build_object('versuche', coalesce((detail ->> 'versuche')::int, 0) + 1, 'fehler', left(p_info, 300))
    where id = p_notice;
  end if;
end $$;

create or replace function public._app_entitlement(p_customer uuid, p_product uuid, p_at timestamptz, p_source public.entitlement_source,
                                        p_price_cents int, p_ref text) returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
begin
  -- Plan wurde gerade vom CRM selbst zurückgegeben (Karte wieder aufgefüllt): kein neuer Kauf, keine neue Karte
  if p_source = 'flenski_plan' then
    select id into v_id from public.entitlements
    where customer_id = p_customer and product_id = p_product and flenski_plan_restored_at > now() - interval '1 day'
    order by flenski_plan_restored_at desc limit 1;
    if v_id is not null then return v_id; end if;
  end if;
  select id into v_id from public.entitlements
  where customer_id = p_customer and product_id = p_product and source in ('flenski_plan', 'flenski_order')
    and starts_at between p_at - interval '10 minutes' and p_at + interval '10 minutes'
  order by starts_at limit 1;
  if v_id is null then
    v_id := public.sell(p_customer, p_product, 'app', p_price_cents, p_at, p_source, p_ref);
  else
    update public.entitlements
    set price_cents = coalesce(p_price_cents, price_cents), external_ref = coalesce(p_ref, external_ref), paid_via = 'app'
    where id = v_id;
  end if;
  return v_id;
end $$;

create or replace function public.flenski_faellige_mandanten() returns setof uuid
language sql stable security definer
set search_path = ''
as $$
  select t.id
  from public.tenants t join public.tenant_secrets s on s.tenant_id = t.id
  where t.status in ('trial', 'active') and nullif(t.settings ->> 'flenski_app_id', '') is not null
    and (s.last_sync_at is null
         or s.last_sync_at < now() - interval '60 minutes'
         or exists (select 1 from public.sessions x
                    where x.tenant_id = t.id and x.flenski_event_id is not null and x.abgeglichen_at is null
                      and x.starts_at between now() - interval '10 minutes' and now() + interval '20 minutes')
         or exists (select 1 from public.sessions x
                    where x.tenant_id = t.id and x.flenski_event_id is not null and x.abgeglichen_at is null
                      and x.flenski_seen_at >= x.starts_at - interval '15 minutes'
                      and x.starts_at between now() - interval '2 hours' and now() - interval '5 minutes')
         or (coalesce((t.settings ->> 'plan_entzug_automatisch')::boolean, false)
             and s.last_sync_at < now() - interval '10 minutes'
             and exists (select 1 from public.customer_notices n
                         where n.tenant_id = t.id and n.kind in ('plan_entziehen', 'plan_zurueckgeben') and n.resolved_at is null
                           and coalesce((n.detail ->> 'versuche')::int, 0) < 3)))
$$;

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
           case n.kind when 'plan_entziehen' then 1 when 'plan_zurueckgeben' then 1 when 'zahlung_fehlgeschlagen' then 1 when 'abo_gekuendigt' then 1 when 'plan_entzogen' then 2 else 3 end as prio,
           jsonb_build_object('art', n.kind, 'detail', n.detail, 'notice_id', n.id) as grund
    from public.customer_notices n
    where n.tenant_id = p_tenant and n.resolved_at is null and n.customer_id is not null and n.kind <> 'mitglied_geloescht'
      -- Plan-Entzug/-Rückgabe läuft automatisch: erst nach 3 Fehlversuchen an die Lehrerin
      and not (n.kind in ('plan_entziehen', 'plan_zurueckgeben')
               and coalesce((select (t.settings ->> 'plan_entzug_automatisch')::boolean from public.tenants t where t.id = n.tenant_id), false)
               and coalesce((n.detail ->> 'versuche')::int, 0) < 3)
    union all
    select s.customer_id,
           case s.signal when 'droht_abzuspringen' then 1 when 'karte_fast_leer' then 2 when 'laeuft_bald_ab' then 2 else 3 end,
           jsonb_build_object('art', s.signal, 'detail', s.detail)
    from public.customer_signals(p_tenant) s
    union all
    select e.customer_id, 2, jsonb_build_object('art', 'kuehlt_ab', 'detail', jsonb_build_object('tage_still', e.tage_still))
    from public.v_customer_engagement e
    where e.tenant_id = p_tenant and e.status = 'kuehlt_ab'
    union all
    -- Neu in der App, aber noch nicht im Kurs gewesen: willkommen heißen
    select e.customer_id, 3, jsonb_build_object('art', 'neu_in_app', 'detail', jsonb_build_object('seit', e.joined_at))
    from public.v_customer_engagement e
    where e.tenant_id = p_tenant and e.status = 'neu' and e.besuche_gesamt = 0
  )
  select g.customer_id, min(g.prio)::int, jsonb_agg(g.grund order by g.prio)
  from g join public.customers c on c.id = g.customer_id
  where c.archived_at is null and c.anonymized_at is null
  group by g.customer_id
  order by min(g.prio), max(c.last_visit_at) nulls first;
end $$;

revoke execute on function public.flenski_offene_rueckgaben, public.flenski_rueckgabe_ergebnis from public, anon, authenticated;
grant execute on function public.flenski_offene_rueckgaben, public.flenski_rueckgabe_ergebnis to service_role;
