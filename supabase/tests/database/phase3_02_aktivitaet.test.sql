-- Phase 3, Schritt 3: Aktivitätsstatus, Zeitleiste, Kümmern-Liste (Abnahmekriterien aus 08-aktivitaet.md, Abschnitt 8).
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;
create function pg_temp.logout() returns void language sql as $$
  select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
$$;
create function pg_temp.status(p_customer uuid) returns text language sql as $$
  select status from public.v_customer_engagement where customer_id = p_customer
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

-- alle seit 100 Tagen dabei, außer "Neu"
insert into public.customers (id, tenant_id, first_name, source, joined_at, flenski_profile_id) values
  ('c0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'Studio-gestern', 'extern', now() - interval '100 days', null),
  ('c0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', 'Studio-vor-20', 'extern', now() - interval '100 days', null),
  ('c0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000000a', 'App-aktiv', 'flenski', now() - interval '100 days', 'f0000000-0000-0000-0000-000000000003'),
  ('c0000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-00000000000a', 'Eingeschlafen', 'flenski', now() - interval '100 days', 'f0000000-0000-0000-0000-000000000004'),
  ('c0000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-00000000000a', 'Neu', 'flenski', now() - interval '5 days', 'f0000000-0000-0000-0000-000000000005'),
  ('c0000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000000b', 'Fremd', 'extern', now() - interval '100 days', null);
insert into public.sessions (id, tenant_id, title, starts_at) values
  ('50000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'Yoga gestern', now() - interval '1 day'),
  ('50000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', 'Yoga vor 20 Tagen', now() - interval '20 days');
select public.checkin('50000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001');
select public.checkin('50000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000002');
insert into public.activity_events (tenant_id, customer_id, flenski_profile_id, type, title, occurred_at, dedupe_key) values
  ('00000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-000000000003', 'f0000000-0000-0000-0000-000000000003', 'course_completed', 'Grundlagen', now() - interval '2 days', 't1'),
  ('00000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-000000000003', 'f0000000-0000-0000-0000-000000000003', 'article_read', 'Atmung', now() - interval '3 days', 't2'),
  ('00000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-000000000004', 'f0000000-0000-0000-0000-000000000004', 'article_read', 'Alt', now() - interval '40 days', 't3');
update public.customers set last_app_activity_at = now() - interval '2 days' where id = 'c0000000-0000-0000-0000-000000000003';
update public.customers set last_app_activity_at = now() - interval '40 days' where id = 'c0000000-0000-0000-0000-000000000004';
insert into public.customer_notices (tenant_id, customer_id, kind, detail) values
  ('00000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-000000000004', 'zahlung_fehlgeschlagen', '{}');

-- Status (08, Abschnitt 8)
select is(pg_temp.status('c0000000-0000-0000-0000-000000000001'), 'dabei', 'ABNAHME 08: Besuch gestern, keine App-Aktivität = dabei');
select is(pg_temp.status('c0000000-0000-0000-0000-000000000002'), 'kuehlt_ab', 'ABNAHME 08: externe Kundin, Besuch vor 20 Tagen = kühlt ab');
select is(pg_temp.status('c0000000-0000-0000-0000-000000000003'), 'dabei', 'Nur App-Aktivität vor 2 Tagen = dabei');
select is(pg_temp.status('c0000000-0000-0000-0000-000000000004'), 'eingeschlafen', 'Letzte Aktivität vor 40 Tagen = eingeschlafen');
select is(pg_temp.status('c0000000-0000-0000-0000-000000000005'), 'neu', 'Seit 5 Tagen in der App = neu');

-- Wert und Verlauf
select is((select score_30d from public.v_customer_engagement where customer_id = 'c0000000-0000-0000-0000-000000000003'), 3,
  '30-Tage-Wert: Kurs abgeschlossen (2) + Artikel gelesen (1) = 3');
select is((select score_30d from public.v_customer_engagement where customer_id = 'c0000000-0000-0000-0000-000000000001'), 3,
  '30-Tage-Wert: ein Besuch = 3');
select is((select array_length(events_8w, 1) from public.v_customer_engagement where customer_id = 'c0000000-0000-0000-0000-000000000001'), 8,
  'Verlauf hat 8 Wochen');
select is((select events_8w[8] from public.v_customer_engagement where customer_id = 'c0000000-0000-0000-0000-000000000001'), 1,
  'Besuch gestern steht in der letzten Woche');

-- Zeitleiste und Kümmern-Liste
select is((select count(*)::int from public.activity_feed('00000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-000000000003')), 2,
  'Zeitleiste einer Person: 2 App-Ereignisse');
select is((select art from public.activity_feed('00000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-000000000001') limit 1), 'besuch',
  'Zeitleiste zeigt Studio-Besuche');
select ok(exists (select 1 from public.care_list('00000000-0000-0000-0000-00000000000a') where customer_id = 'c0000000-0000-0000-0000-000000000002'),
  'Kümmern-Liste: Wer abkühlt, steht drauf');
select is((select prio from public.care_list('00000000-0000-0000-0000-00000000000a') where customer_id = 'c0000000-0000-0000-0000-000000000004'), 1,
  'Kümmern-Liste: Zahlung fehlgeschlagen ist am dringendsten');
select ok(not exists (select 1 from public.care_list('00000000-0000-0000-0000-00000000000a') where customer_id = 'c0000000-0000-0000-0000-000000000003'),
  'Kümmern-Liste: Wer dabei ist, steht nicht drauf');

-- Rechte (08: Mandant A sieht keine Aktivität von B)
select pg_temp.login('10000000-0000-0000-0000-00000000000b');
select is((select count(*)::int from public.v_customer_engagement where tenant_id = '00000000-0000-0000-0000-00000000000a'), 0,
  'ABNAHME 08: Mandantin B sieht keinen Status von A');
select throws_ok($$select * from public.activity_feed('00000000-0000-0000-0000-00000000000a')$$, '42501', null, 'B sieht keine Zeitleiste von A');
select throws_ok($$select * from public.care_list('00000000-0000-0000-0000-00000000000a')$$, '42501', null, 'B sieht keine Kümmern-Liste von A');
select pg_temp.logout();
set local role anon;
select throws_ok($$select * from public.v_customer_engagement$$, '42501', null, 'Ohne Login kein Aktivitätsstatus');
reset role;

select * from finish();
rollback;
