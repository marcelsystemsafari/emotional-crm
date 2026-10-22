-- Phase 1, Schritt 2: Kundinnen, Produkte, Stunden, Aktivität, Protokoll – getrennt je Mandantin, Rechte je Rolle.
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;
create function pg_temp.logout() returns void language sql as $$
  select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
$$;

insert into auth.users (id, email) values
  ('10000000-0000-0000-0000-00000000000a', 'owner-a@test.local'),
  ('20000000-0000-0000-0000-00000000000a', 'staff-a@test.local'),
  ('10000000-0000-0000-0000-00000000000b', 'owner-b@test.local');
insert into public.tenants (id, name, slug, status) values
  ('00000000-0000-0000-0000-00000000000a', 'Test A', 'test-a', 'active'),
  ('00000000-0000-0000-0000-00000000000b', 'Test B', 'test-b', 'active');
insert into public.tenant_members (tenant_id, user_id, role) values
  ('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-00000000000a', 'owner'),
  ('00000000-0000-0000-0000-00000000000a', '20000000-0000-0000-0000-00000000000a', 'staff'),
  ('00000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-00000000000b', 'owner');

-- Je Mandantin ein Datensatz in jeder Tabelle (als System angelegt)
insert into public.customers (id, tenant_id, first_name, last_name, email, source, flenski_profile_id) values
  ('c0000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000a', 'Anna', 'A', 'anna@test.local', 'flenski', 'f0000000-0000-0000-0000-00000000000a'),
  ('c0000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000b', 'Berta', 'B', 'berta@test.local', 'extern', null);
insert into public.products (tenant_id, name, type, credits) values
  ('00000000-0000-0000-0000-00000000000a', '4er A', 'credits', 4),
  ('00000000-0000-0000-0000-00000000000b', '4er B', 'credits', 4);
insert into public.sessions (tenant_id, title, starts_at) values
  ('00000000-0000-0000-0000-00000000000a', 'Stunde A', now()),
  ('00000000-0000-0000-0000-00000000000b', 'Stunde B', now());
insert into public.activity_events (tenant_id, customer_id, flenski_profile_id, type, title, occurred_at, dedupe_key) values
  ('00000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-00000000000a', 'f0000000-0000-0000-0000-00000000000a', 'article_read', 'Artikel A', now(), 'a1'),
  ('00000000-0000-0000-0000-00000000000b', null, 'f0000000-0000-0000-0000-00000000000b', 'article_read', 'Artikel B', now(), 'b1');

-- Owner A sieht in keiner Tabelle etwas von B
select pg_temp.login('10000000-0000-0000-0000-00000000000a');
select results_eq('select first_name from public.customers', array['Anna'], 'Kundinnen: nur eigene');
select results_eq('select name from public.products', array['4er A'], 'Produkte: nur eigene');
select results_eq('select title from public.sessions', array['Stunde A'], 'Stunden: nur eigene');
select results_eq('select title from public.activity_events', array['Artikel A'], 'Aktivität: nur eigene');
select ok((select count(*) from public.audit_log where tenant_id <> '00000000-0000-0000-0000-00000000000a') = 0, 'Protokoll: nur eigenes');

select throws_ok(
  $$insert into public.customers (tenant_id, first_name) values ('00000000-0000-0000-0000-00000000000b', 'Eindringling')$$,
  '42501', null, 'Keine Kundin bei fremder Mandantin anlegen');
select lives_ok(
  $$insert into public.products (tenant_id, name, type, credits) values ('00000000-0000-0000-0000-00000000000a', '10er A', 'credits', 10)$$,
  'Owner darf Produkte anlegen');
select throws_ok(
  $$insert into public.activity_events (tenant_id, flenski_profile_id, type, occurred_at, dedupe_key)
    values ('00000000-0000-0000-0000-00000000000a', gen_random_uuid(), 'other', now(), 'x')$$,
  '42501', null, 'Aktivität schreibt nur der Server');

-- Änderung einer Kundin: Protokoll enthält Feldnamen, aber keine Werte
update public.customers set last_name = 'Neu-Nachname' where id = 'c0000000-0000-0000-0000-00000000000a';
select ok(
  (select diff::text from public.audit_log where entity = 'customers' and action = 'update' order by created_at desc limit 1) = '["last_name"]',
  'Protokoll speichert bei Kundinnen nur, welches Feld geändert wurde');
select ok(
  not exists (select 1 from public.audit_log where diff::text like '%Neu-Nachname%' or diff::text like '%anna@test.local%'),
  'Keine Namen oder E-Mails im Protokoll');
select pg_temp.logout();

-- Staff A: Kundinnen ja, Produkte nein, Protokoll nein
select pg_temp.login('20000000-0000-0000-0000-00000000000a');
select lives_ok(
  $$insert into public.customers (tenant_id, first_name) values ('00000000-0000-0000-0000-00000000000a', 'Neue Kundin')$$,
  'Staff darf Kundinnen anlegen');
select throws_ok(
  $$insert into public.products (tenant_id, name, type, credits) values ('00000000-0000-0000-0000-00000000000a', 'Staff-Karte', 'credits', 5)$$,
  '42501', null, 'Staff darf keine Produkte anlegen');
select is((select count(*)::int from public.audit_log), 0, 'Staff sieht das Protokoll nicht');
select pg_temp.logout();

-- Produktregeln
select throws_ok(
  $$insert into public.products (tenant_id, name, type) values ('00000000-0000-0000-0000-00000000000a', 'Karte ohne Einheiten', 'credits')$$,
  '23514', null, 'Karte ohne Anzahl Einheiten wird abgelehnt');

select * from finish();
rollback;
