-- Kümmern-Liste: auch neue App-Mitglieder ohne Kursbesuch (willkommen heißen). Gefunden beim Test mit Lanas Daten, 22.10.2026.
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

