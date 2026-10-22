-- Flenski-Schlüssel sind nur für den Server lesbar, je Mandantin und Trigger eindeutig.
begin;
create extension if not exists pgtap with schema extensions;
select plan(5);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.webhook_trigger_secrets'::regclass),
  'webhook_trigger_secrets: Row Level Security ist eingeschaltet'
);

insert into public.tenants (id, name, slug) values
  ('00000000-0000-0000-0000-00000000000a', 'Test A', 'test-a'),
  ('00000000-0000-0000-0000-00000000000b', 'Test B', 'test-b');

insert into public.webhook_trigger_secrets (tenant_id, trigger, secret) values
  ('00000000-0000-0000-0000-00000000000a', 'artikel-gelesen', 'geheim-a'),
  ('00000000-0000-0000-0000-00000000000b', 'artikel-gelesen', 'geheim-b');

select throws_ok(
  $$insert into public.webhook_trigger_secrets (tenant_id, trigger, secret)
    values ('00000000-0000-0000-0000-00000000000a', 'artikel-gelesen', 'nochmal')$$,
  '23505', null,
  'Pro Mandantin und Trigger gibt es genau einen Schlüssel'
);

select is(
  (select secret from public.webhook_trigger_secrets
    where tenant_id = '00000000-0000-0000-0000-00000000000b' and trigger = 'artikel-gelesen'),
  'geheim-b',
  'Gleicher Trigger bei zwei Mandantinnen hat getrennte Schlüssel'
);

set local role anon;
select throws_ok('select secret from public.webhook_trigger_secrets', '42501', null, 'anon sieht keine Schlüssel');
reset role;

set local role authenticated;
select throws_ok('select secret from public.webhook_trigger_secrets', '42501', null, 'eingeloggte Nutzer sehen keine Schlüssel');
reset role;

select * from finish();
rollback;
