-- Phase 1, Schritt 4: Fachlogik – Verkauf, Check-in (FEFO), Rückgängig, Absage, Korrektur, Verfall, Signale, Löschen.
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
create function pg_temp.guthaben(p_customer uuid) returns int language sql as $$
  select credits_balance from public.v_customer_overview where customer_id = p_customer
$$;
create function pg_temp.hat_signal(p_customer uuid, p_signal text) returns boolean language sql as $$
  select exists (select 1 from public.customer_signals('00000000-0000-0000-0000-00000000000a')
                 where customer_id = p_customer and signal = p_signal)
$$;

-- ===== Testdaten (als System) =====
insert into auth.users (id, email) values
  ('10000000-0000-0000-0000-00000000000a', 'owner-a@test.local'),
  ('20000000-0000-0000-0000-00000000000a', 'staff-a@test.local'),
  ('10000000-0000-0000-0000-00000000000b', 'owner-b@test.local');
insert into public.tenants (id, name, slug, status, settings) values
  ('00000000-0000-0000-0000-00000000000a', 'Test A', 'test-a', 'active',
   '{"storno_frist_stunden": 12, "abzug_bei_spaeter_absage": true, "abzug_bei_no_show": true,
     "signal_inaktiv_tage": 21, "signal_ablauf_tage": 14, "signal_fast_leer_ab": 1, "signal_neu_tage": 14}'),
  ('00000000-0000-0000-0000-00000000000b', 'Test B', 'test-b', 'active', '{}');
insert into public.tenant_members (tenant_id, user_id, role) values
  ('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-00000000000a', 'owner'),
  ('00000000-0000-0000-0000-00000000000a', '20000000-0000-0000-0000-00000000000a', 'staff'),
  ('00000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-00000000000b', 'owner');

insert into public.customers (id, tenant_id, first_name, email) values
  ('c0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'Anna', null),
  ('c0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', 'Bea', null),
  ('c0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000000a', 'Clara', null),
  ('c0000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-00000000000a', 'Doris', null),
  ('c0000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-00000000000a', 'Eva', null),
  ('c0000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-00000000000a', 'Frida', null),
  ('c0000000-0000-0000-0000-000000000007', '00000000-0000-0000-0000-00000000000a', 'Gina', null),
  ('c0000000-0000-0000-0000-000000000008', '00000000-0000-0000-0000-00000000000a', 'Hanna', null),
  ('c0000000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-00000000000a', 'Ida', 'ida@test.local'),
  ('c0000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-00000000000a', 'Jule', null),
  ('c0000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000000b', 'Berta', null);

insert into public.products (id, tenant_id, name, type, credits, validity_days, category) values
  ('d0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', '4er-Karte', 'credits', 4, null, null),
  ('d0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', '4er 30 Tage', 'credits', 4, 30, null),
  ('d0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000000a', 'Kinderyoga 4er', 'credits', 4, null, 'Kinderyoga'),
  ('d0000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-00000000000a', 'Kursblock', 'period', null, 70, null);

insert into public.sessions (id, tenant_id, title, starts_at, category) values
  ('50000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'Yoga +2 Tage', now() + interval '2 days', null),
  ('50000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', 'Yoga +3 Tage', now() + interval '3 days', null),
  ('50000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000000a', 'Yoga +4 Tage', now() + interval '4 days', null),
  ('50000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-00000000000a', 'Yoga in 2 Std.', now() + interval '2 hours', null),
  ('50000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-00000000000a', 'Erwachsene +1 Tag', now() + interval '1 day', 'Erwachsene'),
  ('50000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-00000000000a', 'Yoga vor 25 Tagen', now() - interval '25 days', null),
  ('50000000-0000-0000-0000-000000000007', '00000000-0000-0000-0000-00000000000a', 'Yoga vor 3 Tagen', now() - interval '3 days', null);

-- ===== Als Owner A =====
select pg_temp.login('10000000-0000-0000-0000-00000000000a');

-- Abnahme-Kriterium aus 05: Guthaben 4 → drei Besuche → ein Storno → Stand 2, Verlauf zeigt 5 Buchungen
select public.sell('c0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'bar');
select is(pg_temp.guthaben('c0000000-0000-0000-0000-000000000001'), 4, 'Verkauf: 4er-Karte hat 4 Einheiten');
select public.checkin('50000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001');
select public.checkin('50000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000001');
select public.checkin('50000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000001');
select is(pg_temp.guthaben('c0000000-0000-0000-0000-000000000001'), 1, 'Drei Besuche: Stand 1');
select is(public.cancel_attendance('50000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000001') ->> 'status',
  'cancelled_in_time', 'Absage 4 Tage vorher ist rechtzeitig');
select is(pg_temp.guthaben('c0000000-0000-0000-0000-000000000001'), 2, 'ABNAHME: nach Storno Stand 2');
select is((select count(*)::int from public.ledger_entries where customer_id = 'c0000000-0000-0000-0000-000000000001'), 5,
  'ABNAHME: Verlauf zeigt 5 Buchungen');
select public.checkin('50000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001');
select is(pg_temp.guthaben('c0000000-0000-0000-0000-000000000001'), 2, 'Doppeltes Antippen bucht nicht doppelt ab');
select ok((select last_visit_at from public.customers where id = 'c0000000-0000-0000-0000-000000000001') is not null,
  'Letzter Besuch wird mitgeführt');

-- FEFO: von zwei Karten wird die zuerst ablaufende belastet
select public.sell('c0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000002', 'bar', null, now());
select public.sell('c0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000002', 'bar', null, now() - interval '20 days');
select is(
  (public.checkin('50000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002') ->> 'entitlement_id')::uuid,
  (select id from public.entitlements where customer_id = 'c0000000-0000-0000-0000-000000000002' order by expires_at limit 1),
  'FEFO: die Karte, die zuerst abläuft, wird belastet');
select is(pg_temp.guthaben('c0000000-0000-0000-0000-000000000002'), 7, 'FEFO: insgesamt 8 − 1 = 7');

-- Rückgängig
select is(public.undo_checkin('50000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002') ->> 'status',
  'registered', 'Rückgängig: wieder nur angemeldet');
select is(pg_temp.guthaben('c0000000-0000-0000-0000-000000000002'), 8, 'Rückgängig: Guthaben wieder voll');

-- Kategorie: Kinderyoga-Karte gilt nicht für Erwachsenen-Stunde
select public.sell('c0000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-000000000003', 'bar');
select ok((public.checkin('50000000-0000-0000-0000-000000000005', 'c0000000-0000-0000-0000-000000000003') ->> 'ohne_karte')::boolean,
  'Kinderyoga-Karte passt nicht zur Erwachsenen-Stunde: Check-in „ohne Karte“');
select is(pg_temp.guthaben('c0000000-0000-0000-0000-000000000003'), 4, 'Kinderyoga-Karte bleibt unberührt');

-- Kursblock (Zeitraum): Teilnahme ohne Abzug
select public.sell('c0000000-0000-0000-0000-000000000004', 'd0000000-0000-0000-0000-000000000004', 'ueberweisung');
select ok((public.checkin('50000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000004') ->> 'unbegrenzt')::boolean,
  'Kursblock: Teilnahme läuft über den Block');
select is((select count(*)::int from public.ledger_entries where customer_id = 'c0000000-0000-0000-0000-000000000004'), 0,
  'Kursblock: keine Abbuchung');

-- Ohne Karte: Check-in klappt trotzdem
select ok((public.checkin('50000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000005') ->> 'ohne_karte')::boolean,
  'Ohne Karte: trotzdem anwesend, als „offen“ markiert');
select is((select status::text from public.attendances where customer_id = 'c0000000-0000-0000-0000-000000000005'), 'present',
  'Ohne Karte: Status anwesend');

-- Späte Absage und nicht erschienen
select public.sell('c0000000-0000-0000-0000-000000000006', 'd0000000-0000-0000-0000-000000000001', 'bar');
select is(public.cancel_attendance('50000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-000000000006') ->> 'status',
  'cancelled_late', 'Absage 2 Std. vorher ist zu spät (Frist 12 Std.)');
select is(pg_temp.guthaben('c0000000-0000-0000-0000-000000000006'), 3, 'Späte Absage: Abzug');
select public.cancel_attendance('50000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000006', true);
select is(pg_temp.guthaben('c0000000-0000-0000-0000-000000000006'), 2, 'Nicht erschienen: Abzug');
select pg_temp.logout();
update public.tenants set settings = settings || '{"abzug_bei_no_show": false}' where id = '00000000-0000-0000-0000-00000000000a';
select pg_temp.login('10000000-0000-0000-0000-00000000000a');
select public.cancel_attendance('50000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000006', true);
select is(pg_temp.guthaben('c0000000-0000-0000-0000-000000000006'), 2, 'Nicht erschienen ohne Abzug, wenn so eingestellt');

-- Korrektur
select throws_ok(
  $$select public.correct((select id from public.entitlements where customer_id = 'c0000000-0000-0000-0000-000000000006'), 1, '  ')$$,
  '23514', null, 'Korrektur ohne Grund wird abgelehnt');
select is(public.correct((select id from public.entitlements where customer_id = 'c0000000-0000-0000-0000-000000000006'), 1, 'Kulanz'),
  3, 'Korrektur +1 mit Grund: neues Guthaben 3');

-- Verfall: Karte vor 40 Tagen gekauft, 30 Tage gültig
select public.sell('c0000000-0000-0000-0000-000000000007', 'd0000000-0000-0000-0000-000000000002', 'bar', null, now() - interval '40 days');
select throws_ok('select public.expire_entitlements()', '42501', null, 'Verfall startet nur das System, nicht die Lehrerin');
select pg_temp.logout();
select ok(public.expire_entitlements() >= 1, 'Nächtlicher Verfall läuft');
select is((select balance from public.v_entitlement_balance where customer_id = 'c0000000-0000-0000-0000-000000000007'), 0,
  'Verfall: Restguthaben ausgebucht');
select is((select status::text from public.entitlements where customer_id = 'c0000000-0000-0000-0000-000000000007'), 'expired',
  'Verfall: Karte abgelaufen');
select is((select delta from public.ledger_entries where customer_id = 'c0000000-0000-0000-0000-000000000007' and reason = 'expiry'), -4,
  'Verfall steht als eigene Buchung im Verlauf');
select is(public.expire_entitlements(), 0, 'Verfall zweimal ausgeführt bucht nicht doppelt');
select pg_temp.login('10000000-0000-0000-0000-00000000000a');

-- Signale
select public.sell('c0000000-0000-0000-0000-000000000008', 'd0000000-0000-0000-0000-000000000001', 'bar', null, now() - interval '30 days');
select public.checkin('50000000-0000-0000-0000-000000000006', 'c0000000-0000-0000-0000-000000000008');
select ok(pg_temp.hat_signal('c0000000-0000-0000-0000-000000000008', 'droht_abzuspringen'),
  'Signal „droht abzuspringen“: Guthaben 3, letzter Besuch vor 25 Tagen');
select public.sell('c0000000-0000-0000-0000-000000000010', 'd0000000-0000-0000-0000-000000000001', 'bar', null, now() - interval '10 days');
select public.correct((select id from public.entitlements where customer_id = 'c0000000-0000-0000-0000-000000000010'), -3, 'Übernahme alte Karte');
select public.checkin('50000000-0000-0000-0000-000000000007', 'c0000000-0000-0000-0000-000000000010');
select ok(pg_temp.hat_signal('c0000000-0000-0000-0000-000000000010', 'karte_fast_leer'), 'Signal „Karte fast leer“');
select ok(pg_temp.hat_signal('c0000000-0000-0000-0000-000000000010', 'neu_dabei'), 'Signal „neu dabei“: erster Besuch vor 3 Tagen');
select ok(pg_temp.hat_signal('c0000000-0000-0000-0000-000000000002', 'laeuft_bald_ab'), 'Signal „läuft bald ab“: Karte endet in 10 Tagen');
select ok(not pg_temp.hat_signal('c0000000-0000-0000-0000-000000000001', 'droht_abzuspringen'), 'Kein Fehlalarm bei aktiver Kundin');
select pg_temp.logout();

-- Rechte
select pg_temp.login('20000000-0000-0000-0000-00000000000a');
select lives_ok($$select public.checkin('50000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000002')$$,
  'Staff darf einchecken');
select throws_ok($$select public.anonymize_customer('c0000000-0000-0000-0000-000000000009')$$, '42501', null,
  'Staff darf keine Kundin löschen');
select pg_temp.logout();
select pg_temp.login('10000000-0000-0000-0000-00000000000b');
select throws_ok($$select public.checkin('50000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000002')$$,
  '42501', null, 'Owner B kann nicht bei A einchecken');
select throws_ok($$select * from public.customer_signals('00000000-0000-0000-0000-00000000000a')$$,
  '42501', null, 'Owner B sieht keine Signale von A');
select pg_temp.logout();

-- Löschen = anonymisieren, Buchungen bleiben
select pg_temp.login('10000000-0000-0000-0000-00000000000a');
select public.sell('c0000000-0000-0000-0000-000000000009', 'd0000000-0000-0000-0000-000000000001', 'bar');
select public.anonymize_customer('c0000000-0000-0000-0000-000000000009');
select is((select first_name || coalesce(email, '') from public.customers where id = 'c0000000-0000-0000-0000-000000000009'),
  'Gelöschte Kundin', 'Löschen entfernt Name und E-Mail');
select is(pg_temp.guthaben('c0000000-0000-0000-0000-000000000009'), 4, 'Löschen lässt die Buchungen stehen');
select throws_ok($$select public.sell('c0000000-0000-0000-0000-000000000009', 'd0000000-0000-0000-0000-000000000001')$$,
  'P0001', null, 'An gelöschte Kundin kann nichts verkauft werden');
select pg_temp.logout();

select * from finish();
rollback;
