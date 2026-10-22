-- Phase 2, Schritt 1: Helfer für die Oberfläche – Teilnehmerliste, Verlauf, Vorschläge, Rechte.
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
insert into public.customers (id, tenant_id, first_name) values
  ('c0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'Anna'),
  ('c0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', 'Bea');
insert into public.products (id, tenant_id, name, type, credits) values
  ('d0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', '4er-Karte', 'credits', 4);
-- Stunde letzte Woche am heutigen Wochentag
insert into public.sessions (id, tenant_id, title, starts_at, ends_at) values
  ('50000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'Yoga am Abend',
   ((current_date - 7) + time '18:30') at time zone 'Europe/Berlin', ((current_date - 7) + time '19:45') at time zone 'Europe/Berlin');

select pg_temp.login('20000000-0000-0000-0000-00000000000a');
select public.sell('c0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'bar', null, now() - interval '10 days');
select public.checkin('50000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001');
select public.checkin('50000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002');

-- Teilnehmerliste
select is((select count(*)::int from public.session_roster('50000000-0000-0000-0000-000000000001')), 2, 'Teilnehmerliste: 2 Personen');
select is((select rest from public.session_roster('50000000-0000-0000-0000-000000000001') where first_name = 'Anna'), 3,
  'Teilnehmerliste zeigt Restguthaben der belasteten Karte');
select ok((select abgebucht from public.session_roster('50000000-0000-0000-0000-000000000001') where first_name = 'Anna'),
  'Teilnehmerliste: Anna wurde abgebucht');
select ok((select entitlement_id is null from public.session_roster('50000000-0000-0000-0000-000000000001') where first_name = 'Bea'),
  'Teilnehmerliste: Bea ohne Karte');

-- Verlauf
select is((select count(*)::int from public.v_customer_history where customer_id = 'c0000000-0000-0000-0000-000000000001'), 2,
  'Verlauf: Kauf + Besuch');
select is((select session_title from public.v_customer_history where customer_id = 'c0000000-0000-0000-0000-000000000001' and reason = 'visit'),
  'Yoga am Abend', 'Verlauf nennt die Stunde');

-- Vorschlag aus der Vorwoche + übernehmen
select is((select title from public.session_suggestions('00000000-0000-0000-0000-00000000000a', current_date)), 'Yoga am Abend',
  'Vorschlag: Stunde der Vorwoche');
select ok((select ((starts_at at time zone 'Europe/Berlin')::time = time '18:30')
           from public.session_suggestions('00000000-0000-0000-0000-00000000000a', current_date)),
  'Vorschlag: gleiche Uhrzeit');
select public.copy_session('50000000-0000-0000-0000-000000000001');
select is((select count(*)::int from public.session_suggestions('00000000-0000-0000-0000-00000000000a', current_date)), 0,
  'Nach dem Übernehmen kein doppelter Vorschlag');
select is((select count(*)::int from public.attendances a join public.sessions s on s.id = a.session_id
           where s.title = 'Yoga am Abend' and s.id <> '50000000-0000-0000-0000-000000000001' and a.status = 'registered'), 2,
  'Wer letzte Woche da war, steht schon auf der neuen Liste');

-- Rechte: Staff korrigiert nicht
select throws_ok(
  $$select public.correct((select id from public.entitlements limit 1), 1, 'Test')$$,
  '42501', null, 'Staff darf nicht korrigieren');
select is((select count(*)::int from public.team_members('00000000-0000-0000-0000-00000000000a')), 2, 'Team: 2 Personen sichtbar');
select pg_temp.logout();

select pg_temp.login('10000000-0000-0000-0000-00000000000a');
select is(public.correct((select id from public.entitlements limit 1), 1, 'Kulanz'), 4, 'Owner darf korrigieren');
select pg_temp.logout();

select pg_temp.login('10000000-0000-0000-0000-00000000000b');
select throws_ok($$select * from public.session_roster('50000000-0000-0000-0000-000000000001')$$, 'P0002', null,
  'Fremde Mandantin sieht die Teilnehmerliste nicht');
select throws_ok($$select * from public.team_members('00000000-0000-0000-0000-00000000000a')$$, '42501', null,
  'Fremde Mandantin sieht das Team nicht');
select throws_ok($$select public.copy_session('50000000-0000-0000-0000-000000000001')$$, '42501', null,
  'Fremde Mandantin kann keine Stunde übernehmen');
select is((select count(*)::int from public.v_customer_history), 0, 'Fremde Mandantin sieht keinen Verlauf');
select pg_temp.logout();

select * from finish();
rollback;
