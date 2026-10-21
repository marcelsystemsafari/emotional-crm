-- Phase 0: Webhook-Rohdaten sind vor dem Browser geschützt und werden nicht doppelt gespeichert.
begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.tenants'::regclass),
  'tenants: Row Level Security ist eingeschaltet'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.webhook_events'::regclass),
  'webhook_events: Row Level Security ist eingeschaltet'
);

-- Testdaten: zwei Mandanten
insert into public.tenants (id, name, slug) values
  ('00000000-0000-0000-0000-00000000000a', 'Test A', 'test-a'),
  ('00000000-0000-0000-0000-00000000000b', 'Test B', 'test-b');

-- Dasselbe Ereignis zweimal → genau ein Eintrag
insert into public.webhook_events (tenant_id, raw_body, dedupe_key)
values ('00000000-0000-0000-0000-00000000000a', '{"x":1}', 'abc')
on conflict (tenant_id, dedupe_key) do nothing;
insert into public.webhook_events (tenant_id, raw_body, dedupe_key)
values ('00000000-0000-0000-0000-00000000000a', '{"x":1}', 'abc')
on conflict (tenant_id, dedupe_key) do nothing;
select is(
  (select count(*)::int from public.webhook_events where tenant_id = '00000000-0000-0000-0000-00000000000a'),
  1,
  'Doppelt zugestelltes Ereignis wird nur einmal gespeichert'
);

-- Gleicher Inhalt bei anderem Mandanten ist ein eigenes Ereignis
insert into public.webhook_events (tenant_id, raw_body, dedupe_key)
values ('00000000-0000-0000-0000-00000000000b', '{"x":1}', 'abc')
on conflict (tenant_id, dedupe_key) do nothing;
select is(
  (select count(*)::int from public.webhook_events where dedupe_key = 'abc'),
  2,
  'Gleiches Ereignis bei zwei Mandanten bleibt getrennt'
);

-- Browser ohne Login (anon) und eingeloggte Nutzer (authenticated) kommen nicht an die Daten
set local role anon;
select throws_ok('select * from public.webhook_events', '42501', null, 'anon sieht keine Webhook-Rohdaten');
select throws_ok('select webhook_secret from public.tenants', '42501', null, 'anon sieht kein Webhook-Secret');
reset role;

set local role authenticated;
select throws_ok('select * from public.webhook_events', '42501', null, 'eingeloggte Nutzer sehen keine Webhook-Rohdaten');
reset role;

select * from finish();
rollback;
