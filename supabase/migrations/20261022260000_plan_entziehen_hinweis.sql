-- Leere oder abgelaufene Karte: Hinweis "Plan in Flenski entziehen" (Marcel, 22.10.2026).
-- Solange das CRM keinen Flenski-Schlüssel hat, entzieht die Lehrerin den Plan selbst (ein Klick im Profil).
-- Mit Schlüssel wird daraus später der automatische Entzug (Entscheidung 0006, Folgen).
-- Wird die Karte wieder aufgefüllt (Gegenbuchung), erledigt sich der Hinweis von selbst.

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
    if not exists (select 1 from public.customer_notices n
                   where n.customer_id = new.customer_id and n.kind = 'plan_entziehen' and n.resolved_at is null
                     and n.detail ->> 'entitlement_id' = new.id::text) then
      insert into public.customer_notices (tenant_id, customer_id, kind, detail)
      values (new.tenant_id, new.customer_id, 'plan_entziehen',
              jsonb_build_object('entitlement_id', new.id, 'produkt', v_prod.name, 'plan', v_prod.name,
                                 'grund', case new.status when 'expired' then 'abgelaufen' else 'aufgebraucht' end));
    end if;
  elsif new.status = 'active' and old.status in ('used_up', 'expired') then
    update public.customer_notices set resolved_at = now()
    where customer_id = new.customer_id and kind = 'plan_entziehen' and resolved_at is null
      and detail ->> 'entitlement_id' = new.id::text;
  end if;
  return new;
end $$;

drop trigger if exists entitlements_plan_hinweis on public.entitlements;
create trigger entitlements_plan_hinweis after update of status on public.entitlements
  for each row execute function public.karte_status_hinweis();
revoke execute on function public.karte_status_hinweis from public, anon, authenticated;

-- Kümmern-Liste: Plan entziehen steht ganz oben
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
           case n.kind when 'plan_entziehen' then 1 when 'zahlung_fehlgeschlagen' then 1 when 'abo_gekuendigt' then 1 when 'plan_entzogen' then 2 else 3 end as prio,
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


-- Bestehende leere/abgelaufene Karten mit Flenski-Plan nachtragen
insert into public.customer_notices (tenant_id, customer_id, kind, detail)
select e.tenant_id, e.customer_id, 'plan_entziehen',
       jsonb_build_object('entitlement_id', e.id, 'produkt', p.name, 'plan', p.name,
                          'grund', case e.status when 'expired' then 'abgelaufen' else 'aufgebraucht' end)
from public.entitlements e join public.products p on p.id = e.product_id
where e.status in ('used_up', 'expired') and p.flenski_plan_id is not null and e.created_at > now() - interval '90 days'
  and not exists (select 1 from public.customer_notices n where n.kind = 'plan_entziehen' and n.detail ->> 'entitlement_id' = e.id::text);
