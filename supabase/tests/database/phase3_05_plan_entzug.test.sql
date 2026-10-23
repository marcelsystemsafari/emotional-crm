-- Automatischer Plan-Entzug in Flenski: wann wird entzogen, wann nicht, und keine doppelten Hinweise.
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

create function pg_temp.offen(p_kind text, p_customer uuid) returns int language sql as $$
  select count(*)::int from public.customer_notices where kind = p_kind and customer_id = p_customer and resolved_at is null
$$;
create function pg_temp.liste() returns int language sql as $$
  select count(*)::int from public.flenski_offene_entzuege('00000000-0000-0000-0000-00000000000a')
$$;

insert into public.tenants (id, name, slug, status, settings) values
  ('00000000-0000-0000-0000-00000000000a', 'Test A', 'test-a', 'active', '{"flenski_app_id": "aaaaaaaa-0000-0000-0000-000000000001"}');
insert into public.tenant_secrets (tenant_id, flenski_api_key, last_sync_at) values ('00000000-0000-0000-0000-00000000000a', 'test', now() - interval '20 minutes');
insert into public.customers (id, tenant_id, first_name, email, source, flenski_profile_id) values
  ('c0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'Leer', 'leer@test.local', 'flenski', 'f0000000-0000-0000-0000-000000000001'),
  ('c0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', 'Kauft nach', 'nach@test.local', 'flenski', 'f0000000-0000-0000-0000-000000000002'),
  ('c0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000000a', 'Lana entzieht', 'selbst@test.local', 'flenski', 'f0000000-0000-0000-0000-000000000003');
insert into public.products (id, tenant_id, name, type, credits, flenski_plan_id) values
  ('a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', '4er Paket', 'credits', 4, 'b0000000-0000-0000-0000-000000000001');
insert into public.entitlements (id, tenant_id, customer_id, product_id) values
  ('e0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001'),
  ('e0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001'),
  ('e0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001');
insert into public.ledger_entries (tenant_id, entitlement_id, customer_id, delta, reason)
select '00000000-0000-0000-0000-00000000000a', e, c, 4, 'purchase'
from (values ('e0000000-0000-0000-0000-000000000001'::uuid, 'c0000000-0000-0000-0000-000000000001'::uuid),
             ('e0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000002'),
             ('e0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000003')) v (e, c);
-- alle drei Karten leer
select public.correct(e, -4, 'Test') from unnest(array['e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002',
  'e0000000-0000-0000-0000-000000000003']::uuid[]) e;

select is(pg_temp.liste(), 0, 'Ausgeschaltet: nichts wird automatisch entzogen');
select is((select count(*)::int from public.flenski_faellige_mandanten() x where x = '00000000-0000-0000-0000-00000000000a'), 0,
  'Ausgeschaltet: offene Entzüge machen nicht fällig');

update public.tenants set settings = settings || '{"plan_entzug_automatisch": true}' where id = '00000000-0000-0000-0000-00000000000a';
select is(pg_temp.liste(), 3, 'Eingeschaltet: leere Karten mit Plan stehen zum Entzug an');
select is((select count(*)::int from public.flenski_faellige_mandanten() x where x = '00000000-0000-0000-0000-00000000000a'), 1,
  'Eingeschaltet: offene Entzüge machen fällig (nach 10 Minuten)');
select is((select email from public.flenski_offene_entzuege('00000000-0000-0000-0000-00000000000a') where email like 'leer%'), 'leer@test.local',
  'Entzug kennt die E-Mail der Person');

-- "Kauft nach": neue Karte desselben Angebots → kein Entzug
insert into public.entitlements (tenant_id, customer_id, product_id) values
  ('00000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001');
select is(pg_temp.offen('plan_entziehen', 'c0000000-0000-0000-0000-000000000002'), 0, 'Neue Karte gekauft: Hinweis erledigt, kein Entzug');

-- "Lana entzieht" selbst in der App → Rückmeldung erledigt ihren Hinweis
insert into public.customer_notices (tenant_id, customer_id, kind, detail) values
  ('00000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-000000000003', 'plan_entzogen', '{"plan": "4er Paket"}');
select is(pg_temp.offen('plan_entziehen', 'c0000000-0000-0000-0000-000000000003'), 0, 'Lehrerin entzieht selbst: Hinweis erledigt sich');
select is(pg_temp.liste(), 1, 'Danach steht nur noch eine Person zum Entzug an');

-- Fehlschlag: bleibt stehen, nach 3 Versuchen nicht mehr automatisch
select public.flenski_entzug_ergebnis(n.id, false, 'Flenski 500') from public.customer_notices n
where n.kind = 'plan_entziehen' and n.customer_id = 'c0000000-0000-0000-0000-000000000001';
select is(pg_temp.offen('plan_entziehen', 'c0000000-0000-0000-0000-000000000001'), 1, 'Fehlschlag: Hinweis bleibt für die Lehrerin');
select is(pg_temp.liste(), 1, 'Nach einem Fehlschlag wird es erneut versucht');

-- Erfolg
select public.flenski_entzug_ergebnis(n.id, true, null) from public.customer_notices n
where n.kind = 'plan_entziehen' and n.customer_id = 'c0000000-0000-0000-0000-000000000001' and n.resolved_at is null;
select is(pg_temp.offen('plan_entziehen', 'c0000000-0000-0000-0000-000000000001'), 0, 'Erfolg: Hinweis erledigt');
select ok((select flenski_plan_revoked_at is not null from public.entitlements where id = 'e0000000-0000-0000-0000-000000000001'),
  'Erfolg: Karte merkt sich "Plan entzogen"');
select is(pg_temp.liste(), 0, 'Nichts doppelt entziehen');
-- Rückmeldung aus Flenski nach unserem Entzug: kein neuer offener Hinweis
insert into public.customer_notices (tenant_id, customer_id, kind, detail) values
  ('00000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-000000000001', 'plan_entzogen', '{"plan": "4er Paket"}');
select is(pg_temp.offen('plan_entzogen', 'c0000000-0000-0000-0000-000000000001'), 0, 'Rückmeldung nach eigenem Entzug: kein doppelter Hinweis');

-- ===== Zurückgeben: Karte wird wieder aufgefüllt (+1 statt 0) =====
select public.correct('e0000000-0000-0000-0000-000000000001', 1, 'Kulanz');
select is(pg_temp.offen('plan_zurueckgeben', 'c0000000-0000-0000-0000-000000000001'), 1, '+1 nach Entzug: Plan soll zurück');
select is((select count(*)::int from public.flenski_offene_rueckgaben('00000000-0000-0000-0000-00000000000a')), 1, 'Rückgabe steht an');
select ok(not exists (select 1 from public.care_list('00000000-0000-0000-0000-00000000000a') x
                      where x.customer_id = 'c0000000-0000-0000-0000-000000000001' and x.gruende::text like '%plan_zurueckgeben%'),
  'Läuft automatisch: nicht in "Heute für dich"');
select public.flenski_rueckgabe_ergebnis(n.id, true, null) from public.customer_notices n
where n.kind = 'plan_zurueckgeben' and n.customer_id = 'c0000000-0000-0000-0000-000000000001' and n.resolved_at is null;
select ok((select flenski_plan_revoked_at is null and flenski_plan_restored_at is not null from public.entitlements
           where id = 'e0000000-0000-0000-0000-000000000001'), 'Rückgabe gemerkt: Plan wieder da');
-- Flenski meldet danach "Plan zugewiesen": keine neue Karte
create temp table vorher as select count(*) as n from public.entitlements where customer_id = 'c0000000-0000-0000-0000-000000000001';
select is(public._app_entitlement('c0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', now(), 'flenski_plan', null, null),
  'e0000000-0000-0000-0000-000000000001'::uuid, 'Rückmeldung "Plan zugewiesen" nach Rückgabe: dieselbe Karte');
select is((select count(*) from public.entitlements where customer_id = 'c0000000-0000-0000-0000-000000000001'), (select n from vorher),
  'Keine zweite Karte durch die Rückgabe');
-- Echter Kauf in der App legt weiterhin eine neue Karte an
select isnt(public._app_entitlement('c0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', now(), 'flenski_order', 4000, 'ORDER-1'),
  'e0000000-0000-0000-0000-000000000001'::uuid, 'Kauf in der App: neue Karte wie bisher');
-- Wieder leer: Entzug erneut fällig
select public.correct('e0000000-0000-0000-0000-000000000001', -1, 'Besuch');
select is(pg_temp.offen('plan_entziehen', 'c0000000-0000-0000-0000-000000000001'), 0,
  'Wieder leer, aber neue Karte vorhanden: kein Entzug');

set local role authenticated;
select throws_ok($$select * from public.flenski_offene_entzuege('00000000-0000-0000-0000-00000000000a')$$, '42501', null,
  'Nutzerinnen sehen die Entzugsliste nicht');
reset role;

select * from finish();
rollback;
