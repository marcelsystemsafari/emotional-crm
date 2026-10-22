-- Automatischer Teilnehmer-Abgleich mit Flenski (Entscheidung 0006)
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

create function pg_temp.st(p_session uuid, p_customer uuid) returns text language sql as $$
  select status::text from public.attendances where session_id = p_session and customer_id = p_customer
$$;
create function pg_temp.saldo(p_customer uuid) returns bigint language sql as $$
  select coalesce(sum(delta), 0) from public.ledger_entries where customer_id = p_customer
$$;
create function pg_temp.ev(p_id text, p_start timestamptz, p_count int, p_ids text[]) returns jsonb language sql as $$
  select jsonb_build_object('id', p_id, 'title', 'Yoga', 'startsAt', p_start, 'attendedCount', p_count,
    'lastAttended', coalesce((select jsonb_agg(jsonb_build_object('id', x)) from unnest(p_ids) x), '[]'::jsonb))
$$;

insert into public.tenants (id, name, slug, status, settings) values
  ('00000000-0000-0000-0000-00000000000a', 'Test A', 'test-a', 'active', '{"flenski_app_id": "aaaaaaaa-0000-0000-0000-000000000001"}'),
  ('00000000-0000-0000-0000-00000000000b', 'Test B', 'test-b', 'active', '{}');
insert into public.tenant_secrets (tenant_id, flenski_api_key) values ('00000000-0000-0000-0000-00000000000a', 'test-schluessel');
insert into public.customers (id, tenant_id, first_name, source, flenski_profile_id) values
  ('c0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'Bleibt', 'flenski', 'f0000000-0000-0000-0000-000000000001'),
  ('c0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', 'Meldet ab', 'flenski', 'f0000000-0000-0000-0000-000000000002'),
  ('c0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000000a', 'Webhook verpasst', 'flenski', 'f0000000-0000-0000-0000-000000000003'),
  ('c0000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-00000000000a', 'Im CRM abgesagt', 'flenski', 'f0000000-0000-0000-0000-000000000004');
insert into public.products (id, tenant_id, name, type, credits) values
  ('a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', '10er', 'credits', 10);
select public.sell(c, 'a0000000-0000-0000-0000-000000000001', 'app', null, now() - interval '1 day', 'manual', 'Test')
from unnest(array['c0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002',
                  'c0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000004']::uuid[]) c;

-- ===== Fall 1: vollständige Liste =====
-- Vor dem Termin: Bleibt, Meldet ab, Im CRM abgesagt sind in Flenski angemeldet
select public.sync_flenski_events('00000000-0000-0000-0000-00000000000a', jsonb_build_array(
  pg_temp.ev('e0000000-0000-0000-0000-000000000001', now() + interval '1 hour', 3,
             array['f0000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-000000000004'])));
select ok(exists (select 1 from public.sessions where flenski_event_id = 'e0000000-0000-0000-0000-000000000001'), 'Neuer Termin aus Flenski wird angelegt');
create temp table t1 as select id from public.sessions where flenski_event_id = 'e0000000-0000-0000-0000-000000000001';
select is(pg_temp.st((select id from t1), 'c0000000-0000-0000-0000-000000000002'), 'registered', 'Angemeldete aus Flenski stehen im CRM');

-- Lehrerin sagt im CRM für "Im CRM abgesagt" ab (rechtzeitig) – Flenski zeigt sie aber weiter: Flenski gewinnt
update public.attendances set status = 'cancelled_in_time' where session_id = (select id from t1) and customer_id = 'c0000000-0000-0000-0000-000000000004';
-- Kurz vor Beginn: "Meldet ab" hat sich abgemeldet, "Webhook verpasst" neu angemeldet
select public.sync_flenski_events('00000000-0000-0000-0000-00000000000a', jsonb_build_array(
  pg_temp.ev('e0000000-0000-0000-0000-000000000001', now() + interval '1 hour', 3,
             array['f0000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000003', 'f0000000-0000-0000-0000-000000000004'])));
select is(pg_temp.st((select id from t1), 'c0000000-0000-0000-0000-000000000002'), 'cancelled_in_time', 'Abgemeldet in Flenski = abgesagt im CRM');
select is(pg_temp.st((select id from t1), 'c0000000-0000-0000-0000-000000000003'), 'registered', 'In Flenski angemeldet, Webhook verpasst = nachgetragen');
select is(pg_temp.st((select id from t1), 'c0000000-0000-0000-0000-000000000004'), 'registered', 'Flenski ist die Wahrheit: CRM-Absage wird zurückgesetzt');

-- Termin hat vor 6 Minuten begonnen, letzter Stand von kurz vor Beginn
update public.sessions set starts_at = now() - interval '6 minutes', flenski_seen_at = now() - interval '8 minutes' where id = (select id from t1);
select is((public.sync_flenski_events('00000000-0000-0000-0000-00000000000a', '[]') ->> 'abgeschlossen')::int, 1, 'Fälliger Termin wird abgeschlossen');
select is(pg_temp.st((select id from t1), 'c0000000-0000-0000-0000-000000000001'), 'present', 'Auf der Liste = war da');
select is(pg_temp.saldo('c0000000-0000-0000-0000-000000000001'), 9::bigint, 'War da = ein Besuch abgezogen');
select is(pg_temp.saldo('c0000000-0000-0000-0000-000000000002'), 10::bigint, 'Abgemeldet = kein Abzug');
select is(pg_temp.saldo('c0000000-0000-0000-0000-000000000003'), 9::bigint, 'Nachgetragen und da = Abzug');

-- Nochmal laufen lassen: nichts doppelt
select public.sync_flenski_events('00000000-0000-0000-0000-00000000000a', '[]');
select public.sync_flenski_events('00000000-0000-0000-0000-00000000000a', jsonb_build_array(
  pg_temp.ev('e0000000-0000-0000-0000-000000000001', now() - interval '6 minutes', 0, array[]::text[])));
select is(pg_temp.saldo('c0000000-0000-0000-0000-000000000001'), 9::bigint, 'Zweiter Lauf bucht nicht doppelt');
select is(pg_temp.st((select id from t1), 'c0000000-0000-0000-0000-000000000001'), 'present', 'Abgeschlossener Termin bleibt, wie er ist');

-- ===== Fall 2: Namensliste gekürzt (Flenski zeigt nur die letzten) =====
select public.sync_flenski_events('00000000-0000-0000-0000-00000000000a', jsonb_build_array(
  pg_temp.ev('e0000000-0000-0000-0000-000000000002', now() + interval '1 hour', 2,
             array['f0000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000002'])));
create temp table t2 as select id from public.sessions where flenski_event_id = 'e0000000-0000-0000-0000-000000000002';
-- jetzt 3 angemeldet, Flenski zeigt aber nur einen Namen
select public.sync_flenski_events('00000000-0000-0000-0000-00000000000a', jsonb_build_array(
  pg_temp.ev('e0000000-0000-0000-0000-000000000002', now() + interval '1 hour', 3, array['f0000000-0000-0000-0000-000000000003'])));
select is(pg_temp.st((select id from t2), 'c0000000-0000-0000-0000-000000000002'), 'registered', 'Gekürzte Liste: niemand wird voreilig abgemeldet');
update public.sessions set starts_at = now() - interval '6 minutes', flenski_seen_at = now() - interval '8 minutes' where id = (select id from t2);
select public.sync_flenski_events('00000000-0000-0000-0000-00000000000a', '[]');
select is(pg_temp.st((select id from t2), 'c0000000-0000-0000-0000-000000000003'), 'present', 'Gekürzte Liste: sichtbare Namen = war da');
select is(pg_temp.st((select id from t2), 'c0000000-0000-0000-0000-000000000002'), 'registered', 'Gekürzte Liste: Unsichere bleiben angemeldet, ohne Abzug');
select is((select count(*) from public.customer_notices where kind = 'teilnahme_unklar' and resolved_at is null)::int, 2,
  'Gekürzte Liste: Hinweis "Teilnahme unklar" für die Unsicheren');
select public.set_attendance((select id from t2), 'c0000000-0000-0000-0000-000000000002', 'nicht_da');
select is((select count(*) from public.customer_notices where kind = 'teilnahme_unklar' and resolved_at is null
           and customer_id = 'c0000000-0000-0000-0000-000000000002')::int, 0, '"War nicht da" erledigt den Hinweis');
select public.set_attendance((select id from t2), 'c0000000-0000-0000-0000-000000000001', 'war_da');
select is(pg_temp.st((select id from t2), 'c0000000-0000-0000-0000-000000000001'), 'present', '"War da" bucht ab');

-- ===== Kulanz =====
select public.set_attendance((select id from t1), 'c0000000-0000-0000-0000-000000000001', 'kulanz');
select is(pg_temp.saldo('c0000000-0000-0000-0000-000000000001'), 9::bigint, 'Kulanz gibt den Besuch zurück (10 − 2 + 1)');

-- ===== Kein Stand vom Beginn: nichts raten =====
insert into public.sessions (id, tenant_id, title, starts_at, flenski_event_id) values
  ('50000000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-00000000000a', 'Ohne Stand', now() - interval '2 days', 'e0000000-0000-0000-0000-000000000009');
insert into public.attendances (tenant_id, session_id, customer_id) values
  ('00000000-0000-0000-0000-00000000000a', '50000000-0000-0000-0000-000000000009', 'c0000000-0000-0000-0000-000000000004');
select public.sync_flenski_events('00000000-0000-0000-0000-00000000000a', '[]');
select public.finalize_past_sessions();
select is(pg_temp.st('50000000-0000-0000-0000-000000000009', 'c0000000-0000-0000-0000-000000000004'), 'registered',
  'Ohne Stand aus Flenski wird nicht blind abgebucht');
select is((select abgleich_info ->> 'fehlt' from public.sessions where id = '50000000-0000-0000-0000-000000000009'), 'true',
  'Nach 24 Stunden ohne Stand: Termin als "Abgleich fehlt" markiert');

-- ===== Sicherheit =====
set local role authenticated;
select throws_ok($$select * from public.tenant_secrets$$, '42501', null, 'Flenski-Schlüssel sind für Nutzerinnen unsichtbar');
select throws_ok($$select public.sync_flenski_events('00000000-0000-0000-0000-00000000000a', '[]')$$, '42501', null,
  'Nutzerinnen starten keinen Abgleich');
reset role;

select * from finish();
rollback;
