-- Verlauf je Kundin: eigenes "passiert am" (Stunde bei Besuchen, Kaufdatum bei Käufen, sonst Buchungszeit),
-- damit nachgetragene Verkäufe und Besuche richtig einsortiert werden (gefunden beim Oberflächentest 22.10.2026).
create or replace view public.v_customer_history with (security_invoker = true) as
select l.id, l.tenant_id, l.customer_id, l.entitlement_id, l.created_at, l.delta, l.reason, l.comment, l.created_by,
       p.name as product_name, s.title as session_title, s.starts_at as session_starts_at,
       coalesce(s.starts_at, case when l.reason = 'purchase' then e.starts_at end, l.created_at) as occurred_at
from public.ledger_entries l
join public.entitlements e on e.id = l.entitlement_id
join public.products p on p.id = e.product_id
left join public.attendances a on a.id = l.attendance_id
left join public.sessions s on s.id = a.session_id;
