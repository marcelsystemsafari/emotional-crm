-- Korrektur: "Karte fast leer" nur für Kundinnen, die eine Karte (mit Einheiten) haben oder hatten.
-- Vorher bekam auch eine Kundin ganz ohne Karte das Signal (gefunden mit den Demo-Daten, 22.10.2026).
create or replace function public.customer_signals(p_tenant uuid)
returns table (customer_id uuid, signal text, detail jsonb)
language plpgsql stable security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_s jsonb;
  v_inaktiv int; v_ablauf int; v_fast_leer int; v_neu int;
begin
  if not public.can_read(p_tenant) then
    raise exception 'Keine Berechtigung für diese Mandantin.' using errcode = '42501';
  end if;
  select settings into v_s from public.tenants where id = p_tenant;
  v_inaktiv   := coalesce((v_s ->> 'signal_inaktiv_tage')::int, 21);
  v_ablauf    := coalesce((v_s ->> 'signal_ablauf_tage')::int, 14);
  v_fast_leer := coalesce((v_s ->> 'signal_fast_leer_ab')::int, 1);
  v_neu       := coalesce((v_s ->> 'signal_neu_tage')::int, 14);

  return query
  with kundinnen as (
    select o.* from public.v_customer_overview o
    join public.customers c on c.id = o.customer_id
    where o.tenant_id = p_tenant and c.archived_at is null and c.anonymized_at is null
  ),
  erster_besuch as (
    select a.customer_id, min(s.starts_at) as am
    from public.attendances a join public.sessions s on s.id = a.session_id
    where a.tenant_id = p_tenant and a.status = 'present'
    group by a.customer_id
  ),
  letzter_kauf as (
    select e.customer_id, max(e.starts_at) as am from public.entitlements e
    where e.tenant_id = p_tenant group by e.customer_id
  )
  -- Droht abzuspringen: noch Guthaben (oder Abo/Block), aber lange nicht da
  select k.customer_id, 'droht_abzuspringen',
         jsonb_build_object('tage_ohne_besuch', extract(day from now() - coalesce(k.last_visit_at, lk.am))::int,
                            'guthaben', k.credits_balance, 'unbegrenzt', k.has_unlimited)
  from kundinnen k left join letzter_kauf lk on lk.customer_id = k.customer_id
  where (k.credits_balance > 0 or k.has_unlimited)
    and coalesce(k.last_visit_at, lk.am) < now() - make_interval(days => v_inaktiv)
  union all
  -- Karte fast leer: kommt regelmäßig (Besuch in den letzten 30 Tagen), Guthaben ≤ Schwelle
  select k.customer_id, 'karte_fast_leer', jsonb_build_object('guthaben', k.credits_balance)
  from kundinnen k
  where not k.has_unlimited and k.credits_balance <= v_fast_leer
    and k.last_visit_at >= now() - interval '30 days'
    and exists (select 1 from public.v_entitlement_balance b
                where b.customer_id = k.customer_id and not b.unlimited and b.status <> 'cancelled')
  union all
  -- Karte läuft bald ab und ist noch nicht verbraucht
  select b.customer_id, 'laeuft_bald_ab',
         jsonb_build_object('produkt', b.product_name, 'gueltig_bis', b.expires_at, 'rest', b.balance)
  from public.v_entitlement_balance b join kundinnen k on k.customer_id = b.customer_id
  where b.status = 'active' and (b.unlimited or b.balance > 0)
    and b.expires_at between now() and now() + make_interval(days => v_ablauf)
  union all
  -- Neu dabei: erster Besuch innerhalb der letzten Tage
  select k.customer_id, 'neu_dabei', jsonb_build_object('erster_besuch', eb.am)
  from kundinnen k join erster_besuch eb on eb.customer_id = k.customer_id
  where eb.am >= now() - make_interval(days => v_neu);
end $$;
