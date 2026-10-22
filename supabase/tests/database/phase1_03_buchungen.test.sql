-- Phase 1, Schritt 3: Buchungsprotokoll unveränderlich, Guthaben = Summe, Trennung je Mandantin.
begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;
create function pg_temp.logout() returns void language sql as $$
  select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
$$;

insert into auth.users (id, email) values
  ('10000000-0000-0000-0000-00000000000a', 'owner-a@test.local'),
  ('10000000-0000-0000-0000-00000000000b', 'owner-b@test.local');
insert into public.tenants (id, name, slug, status) values
  ('00000000-0000-0000-0000-00000000000a', 'Test A', 'test-a', 'active'),
  ('00000000-0000-0000-0000-00000000000b', 'Test B', 'test-b', 'active');
insert into public.tenant_members (tenant_id, user_id, role) values
  ('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-00000000000a', 'owner'),
  ('00000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-00000000000b', 'owner');
insert into public.customers (id, tenant_id, first_name) values
  ('c0000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000a', 'Anna'),
  ('c0000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-00000000000a', 'Andrea'),
  ('c0000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000b', 'Berta');
insert into public.products (id, tenant_id, name, type, credits) values
  ('d0000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000a', '4er A', 'credits', 4),
  ('d0000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000b', '4er B', 'credits', 4);
insert into public.entitlements (id, tenant_id, customer_id, product_id) values
  ('e0000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-00000000000a', 'd0000000-0000-0000-0000-00000000000a'),
  ('e0000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000b', 'c0000000-0000-0000-0000-00000000000b', 'd0000000-0000-0000-0000-00000000000b');
insert into public.ledger_entries (tenant_id, entitlement_id, customer_id, delta, reason) values
  ('00000000-0000-0000-0000-00000000000a', 'e0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-00000000000a', 4, 'purchase'),
  ('00000000-0000-0000-0000-00000000000a', 'e0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-00000000000a', -1, 'visit'),
  ('00000000-0000-0000-0000-00000000000b', 'e0000000-0000-0000-0000-00000000000b', 'c0000000-0000-0000-0000-00000000000b', 4, 'purchase');

-- Unveränderlich, auch für die Datenbank selbst
select throws_ok('update public.ledger_entries set delta = 10', 'P0001', null, 'Buchungen lassen sich nicht ändern');
select throws_ok('delete from public.ledger_entries', 'P0001', null, 'Buchungen lassen sich nicht löschen');
select throws_ok('truncate public.ledger_entries', 'P0001', null, 'Buchungen lassen sich nicht leeren');

-- Regeln beim Buchen
select throws_ok(
  $$insert into public.ledger_entries (tenant_id, entitlement_id, customer_id, delta, reason)
    values ('00000000-0000-0000-0000-00000000000a', 'e0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-00000000000a', 1, 'correction')$$,
  '23514', null, 'Korrektur ohne Kommentar wird abgelehnt');
select throws_ok(
  $$insert into public.ledger_entries (tenant_id, entitlement_id, customer_id, delta, reason)
    values ('00000000-0000-0000-0000-00000000000a', 'e0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-0000000000a2', -1, 'visit')$$,
  '23503', null, 'Buchung muss zur Kundin der Karte gehören');
select throws_ok(
  $$insert into public.entitlements (tenant_id, customer_id, product_id)
    values ('00000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-00000000000a', 'd0000000-0000-0000-0000-00000000000b')$$,
  '23503', null, 'Karte kann kein Produkt einer fremden Mandantin haben');

-- Guthaben und Status
select is((select balance from public.v_entitlement_balance where entitlement_id = 'e0000000-0000-0000-0000-00000000000a'), 3,
  'Guthaben = Summe der Buchungen (4 − 1 = 3)');
insert into public.ledger_entries (tenant_id, entitlement_id, customer_id, delta, reason, comment) values
  ('00000000-0000-0000-0000-00000000000a', 'e0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-00000000000a', -3, 'correction', 'Test: aufgebraucht');
select is((select status::text from public.entitlements where id = 'e0000000-0000-0000-0000-00000000000a'), 'used_up',
  'Karte bei 0 ist „aufgebraucht“');
insert into public.ledger_entries (tenant_id, entitlement_id, customer_id, delta, reason, comment) values
  ('00000000-0000-0000-0000-00000000000a', 'e0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-00000000000a', 1, 'correction', 'Test: wieder 1');
select is((select status::text from public.entitlements where id = 'e0000000-0000-0000-0000-00000000000a'), 'active',
  'Gegenbuchung macht die Karte wieder aktiv');

-- Trennung und Schreibschutz für Nutzerinnen
select pg_temp.login('10000000-0000-0000-0000-00000000000a');
select is((select count(*)::int from public.ledger_entries where tenant_id <> '00000000-0000-0000-0000-00000000000a'), 0,
  'Owner A sieht keine Buchungen von B');
select results_eq('select first_name from public.v_customer_overview order by first_name', array['Andrea', 'Anna'],
  'Überblick zeigt nur Kundinnen von A');
select throws_ok(
  $$insert into public.ledger_entries (tenant_id, entitlement_id, customer_id, delta, reason)
    values ('00000000-0000-0000-0000-00000000000a', 'e0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-00000000000a', 10, 'purchase')$$,
  '42501', null, 'Nutzerinnen buchen nie direkt, nur über die Fachfunktionen');
select throws_ok(
  $$insert into public.entitlements (tenant_id, customer_id, product_id)
    values ('00000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-00000000000a', 'd0000000-0000-0000-0000-00000000000a')$$,
  '42501', null, 'Karten entstehen nur über die Fachfunktion „Verkauf“');
select pg_temp.logout();

select * from finish();
rollback;
