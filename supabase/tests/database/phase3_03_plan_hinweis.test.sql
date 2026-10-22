-- Leere Karte mit Flenski-Plan: Hinweis "Plan entziehen", erledigt sich bei Gegenbuchung von selbst.
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

create function pg_temp.offen(p_customer uuid) returns bigint language sql as $$
  select count(*) from public.customer_notices where customer_id = p_customer and kind = 'plan_entziehen' and resolved_at is null
$$;

insert into public.tenants (id, name, slug, status) values ('00000000-0000-0000-0000-00000000000a', 'Test A', 'test-a', 'active');
insert into public.customers (id, tenant_id, first_name, source) values
  ('c0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'Mit Plan', 'flenski'),
  ('c0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', 'Ohne Plan', 'extern');
insert into public.products (id, tenant_id, name, type, credits, flenski_plan_id) values
  ('a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', '4er App', 'credits', 4, 'b0000000-0000-0000-0000-000000000001'),
  ('a0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', '4er Studio', 'credits', 4, null);
insert into public.entitlements (id, tenant_id, customer_id, product_id) values
  ('e0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001'),
  ('e0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000002');
insert into public.ledger_entries (tenant_id, entitlement_id, customer_id, delta, reason) values
  ('00000000-0000-0000-0000-00000000000a', 'e0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 4, 'purchase'),
  ('00000000-0000-0000-0000-00000000000a', 'e0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000002', 4, 'purchase');

select is(pg_temp.offen('c0000000-0000-0000-0000-000000000001'), 0::bigint, 'Volle Karte: kein Hinweis');

-- auf 0 korrigieren
select public.correct('e0000000-0000-0000-0000-000000000001', -4, 'Test');
select public.correct('e0000000-0000-0000-0000-000000000002', -4, 'Test');
select is(pg_temp.offen('c0000000-0000-0000-0000-000000000001'), 1::bigint, 'Karte mit Flenski-Plan leer: Hinweis "Plan entziehen"');
select is(pg_temp.offen('c0000000-0000-0000-0000-000000000002'), 0::bigint, 'Karte ohne Flenski-Plan: kein Hinweis');
select is((select prio from public.care_list('00000000-0000-0000-0000-00000000000a') where customer_id = 'c0000000-0000-0000-0000-000000000001'), 1,
  'Plan entziehen steht in der Kümmern-Liste ganz oben');

-- nochmal Statuswechsel ohne neue Karte: kein doppelter Hinweis
select public.correct('e0000000-0000-0000-0000-000000000001', 1, 'Kulanz');
select is(pg_temp.offen('c0000000-0000-0000-0000-000000000001'), 0::bigint, 'Wieder aufgefüllt: Hinweis erledigt sich von selbst');
select public.correct('e0000000-0000-0000-0000-000000000001', -1, 'doch nicht');
select is(pg_temp.offen('c0000000-0000-0000-0000-000000000001'), 1::bigint, 'Wieder leer: genau ein offener Hinweis');

select * from finish();
rollback;
