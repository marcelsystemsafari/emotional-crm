-- Verlauf: Käufe nur mit Produktnamen, interne Buchungskommentare (z. B. "Produkt eingerichtet") nur bei Korrekturen zeigen.
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
           case when l.reason = 'purchase' then p.name else p.name || coalesce(' – ' || l.comment, '') end, l.delta
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
