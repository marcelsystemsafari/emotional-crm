-- Phase 3: Verarbeitung echter Flenski-Payloads (inbox/webhooks/). Vorlage – Platzhalter in doppelten geschweiften Klammern werden durch
-- scripts/build-webhook-tests.mjs mit dem Beispiel-Payload ersetzt. Nicht die erzeugte Datei bearbeiten.
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
-- Beispiel-Payload einer bestimmten Person zuordnen (die Beispiele stammen von einem Team-Profil)
create function pg_temp.als(p jsonb, p_member uuid, p_email text default null) returns jsonb language sql as $$
  select jsonb_set(jsonb_set(jsonb_set(jsonb_set(p, '{member,id}', to_jsonb(p_member::text)),
         '{member,isMemberOfTeam}', 'false'), '{member,isAdmin}', 'false'),
         '{member,email}', coalesce(to_jsonb(p_email), 'null'::jsonb))
$$;
create function pg_temp.empfang(p_id uuid, p_tenant uuid, p_trigger text, p jsonb, p_valid boolean default true) returns uuid language sql as $$
  insert into public.webhook_events (id, tenant_id, trigger, payload, raw_body, dedupe_key, signature_valid)
  values (p_id, p_tenant, p_trigger, p, p::text, p_id::text, p_valid) returning id
$$;
create function pg_temp.verarbeite(p_id uuid) returns text language sql as $$ select public.process_webhook_event(p_id) $$;

insert into auth.users (id, email) values
  ('10000000-0000-0000-0000-00000000000a', 'owner-a@test.local'),
  ('20000000-0000-0000-0000-00000000000a', 'staff-a@test.local'),
  ('10000000-0000-0000-0000-00000000000b', 'owner-b@test.local');
insert into public.tenants (id, name, slug, status) values
  ('00000000-0000-0000-0000-00000000000a', 'Test A', 'test-a', 'active'),
  ('00000000-0000-0000-0000-00000000000b', 'Test B', 'test-b', 'active'),
  ('00000000-0000-0000-0000-00000000000c', 'Test ruhend', 'test-c', 'dormant');
insert into public.tenant_members (tenant_id, user_id, role) values
  ('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-00000000000a', 'owner'),
  ('00000000-0000-0000-0000-00000000000a', '20000000-0000-0000-0000-00000000000a', 'staff'),
  ('00000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-00000000000b', 'owner');

-- ===== Neues Mitglied =====
select pg_temp.empfang('e1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'neues-mitglied',
  pg_temp.als({{neues-mitglied}}, 'f1000000-0000-0000-0000-000000000001', 'erika@test.local'));
select is(pg_temp.verarbeite('e1000000-0000-0000-0000-000000000001'), 'ok', 'Neues Mitglied wird verarbeitet');
select is((select source::text || ':' || first_name from public.customers where flenski_profile_id = 'f1000000-0000-0000-0000-000000000001'),
  'flenski:Erika', 'Neues Mitglied erscheint als App-Person mit Vornamen');
select is(pg_temp.verarbeite('e1000000-0000-0000-0000-000000000001'), 'schon verarbeitet', 'Dieselbe Nachricht wirkt nur einmal');
select is((select count(*)::int from public.customers where flenski_profile_id = 'f1000000-0000-0000-0000-000000000001'), 1,
  'Keine doppelte Person');

-- Team-Profil (die Lehrerin selbst) wird keine Kundin
select pg_temp.empfang('e1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', 'neues-mitglied',
  jsonb_set(jsonb_set({{neues-mitglied}}, '{member,id}', '"f1000000-0000-0000-0000-0000000000ff"'), '{member,isMemberOfTeam}', 'true'));
select pg_temp.verarbeite('e1000000-0000-0000-0000-000000000002');
select is((select count(*)::int from public.customers where flenski_profile_id = 'f1000000-0000-0000-0000-0000000000ff'), 0,
  'Team-/Admin-Profil wird nicht als Kundin geführt');

-- Ungültige Signatur: gespeichert, aber nicht verarbeitet
select pg_temp.empfang('e1000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000000a', 'neues-mitglied',
  pg_temp.als({{neues-mitglied}}, 'f1000000-0000-0000-0000-000000000003'), false);
select is(pg_temp.verarbeite('e1000000-0000-0000-0000-000000000003'), 'übersprungen', 'Ungültige Signatur wird nicht verarbeitet');
select is((select count(*)::int from public.customers where flenski_profile_id = 'f1000000-0000-0000-0000-000000000003'), 0,
  'Ungültige Signatur legt keine Person an');

-- Ruhende Mandantin: angenommen, nicht verarbeitet
select pg_temp.empfang('e1000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-00000000000c', 'neues-mitglied',
  pg_temp.als({{neues-mitglied}}, 'f1000000-0000-0000-0000-000000000004'));
select is(pg_temp.verarbeite('e1000000-0000-0000-0000-000000000004'), 'übersprungen', 'Ruhende Mandantin wird nicht verarbeitet');

-- ===== Plan zugewiesen + Bestellung = ein Kauf =====
select pg_temp.empfang('e1000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-00000000000a', 'plan-zugewiesen',
  pg_temp.als({{plan-zugewiesen}}, 'f1000000-0000-0000-0000-000000000001'));
select is(pg_temp.verarbeite('e1000000-0000-0000-0000-000000000010'), 'ok', 'Plan zugewiesen wird verarbeitet');
select ok((select needs_setup and type = 'period' from public.products
           where flenski_plan_id = ({{plan-zugewiesen}} -> 'plan' ->> 'id')::uuid),
  'Plan wird automatisch zum Produkt (noch einzurichten)');
select pg_temp.empfang('e1000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-00000000000a', 'bestellung-abgeschlossen',
  jsonb_set(jsonb_set(pg_temp.als({{bestellung-abgeschlossen}}, 'f1000000-0000-0000-0000-000000000001'),
    '{plans,0,id}', {{plan-zugewiesen}} -> 'plan' -> 'id'),
    '{envelope,occurredAt}', {{plan-zugewiesen}} -> 'envelope' -> 'occurredAt'));
select is(pg_temp.verarbeite('e1000000-0000-0000-0000-000000000011'), 'ok', 'Bestellung wird verarbeitet');
select is((select count(*)::int from public.entitlements e join public.customers c on c.id = e.customer_id
           where c.flenski_profile_id = 'f1000000-0000-0000-0000-000000000001'), 1,
  'Plan zugewiesen + Bestellung zur selben Zeit = genau eine Karte');
select is((select price_cents from public.entitlements e join public.customers c on c.id = e.customer_id
           where c.flenski_profile_id = 'f1000000-0000-0000-0000-000000000001'),
  round(({{bestellung-abgeschlossen}} -> 'order' ->> 'amount')::numeric * 100)::int, 'Betrag aus der Bestellung steht an der Karte');

-- ===== Anmeldung zu einem Event (Flenski "teilgenommen") =====
select pg_temp.empfang('e1000000-0000-0000-0000-000000000020', '00000000-0000-0000-0000-00000000000a', 'am-event-teilgenommen',
  pg_temp.als({{am-event-teilgenommen}}, 'f1000000-0000-0000-0000-000000000001'));
select is(pg_temp.verarbeite('e1000000-0000-0000-0000-000000000020'), 'ok', 'Event-Teilnahme wird verarbeitet');
select is((select a.status::text || ':' || s.title from public.attendances a join public.sessions s on s.id = a.session_id
           join public.customers c on c.id = a.customer_id where c.flenski_profile_id = 'f1000000-0000-0000-0000-000000000001'),
  'registered:' || ({{am-event-teilgenommen}} -> 'event' ->> 'title'), 'Flenski-"teilgenommen" = angemeldet (noch kein Besuch)');
select is((select category from public.sessions where tenant_id = '00000000-0000-0000-0000-00000000000a' and flenski_event_id = ({{am-event-teilgenommen}} -> 'event' ->> 'id')::uuid),
  {{am-event-teilgenommen}} -> 'category' ->> 'name', 'Stunde übernimmt die Event-Kategorie');
select is((select count(*)::int from public.activity_events where tenant_id = '00000000-0000-0000-0000-00000000000a' and type = 'event_attended'), 1, 'Anmeldung steht auch im Aktivitätsverlauf');

-- ===== Produkt einrichten, dann Termin vorbei: Besuch wird abgebucht =====
select pg_temp.login('20000000-0000-0000-0000-00000000000a');
select throws_ok($$select public.setup_product((select id from public.products where tenant_id = '00000000-0000-0000-0000-00000000000a' and needs_setup limit 1), 'credits', 10, 70, null, null)$$,
  '42501', null, 'Staff richtet keine Produkte ein');
select pg_temp.logout();
select pg_temp.login('10000000-0000-0000-0000-00000000000a');
select is(public.setup_product((select id from public.products where tenant_id = '00000000-0000-0000-0000-00000000000a' and needs_setup limit 1), 'credits', 10, 120, null, null), 1,
  'Owner richtet das Produkt ein (eine bestehende Karte)');
select is((select credits_balance from public.v_customer_overview o join public.customers c on c.id = o.customer_id
           where c.flenski_profile_id = 'f1000000-0000-0000-0000-000000000001'), 10,
  'Nach dem Einrichten: 10 Besuche, Anmeldung bucht noch nichts ab');
select throws_ok($$select public.finalize_past_sessions()$$, '42501', null, 'Termine abschließen macht nur das System');
select pg_temp.logout();
-- Termin in die Vergangenheit legen (= er hat stattgefunden)
update public.sessions set starts_at = now() - interval '1 hour', ends_at = null
where tenant_id = '00000000-0000-0000-0000-00000000000a' and flenski_event_id = ({{am-event-teilgenommen}} -> 'event' ->> 'id')::uuid;
select ok(public.finalize_past_sessions() >= 1, 'Termine abschließen läuft');
select is((select a.status::text from public.attendances a join public.customers c on c.id = a.customer_id
           where c.flenski_profile_id = 'f1000000-0000-0000-0000-000000000001'), 'present', 'Nach Terminbeginn: angemeldet wird „da“');
select is((select credits_balance from public.v_customer_overview o join public.customers c on c.id = o.customer_id
           where c.flenski_profile_id = 'f1000000-0000-0000-0000-000000000001'), 9, 'Besuch wird abgebucht: 10 − 1 = 9');
select is(public.finalize_past_sessions(), 0, 'Zweiter Lauf bucht nicht doppelt ab');

-- ===== Aktivität =====
select pg_temp.empfang('e1000000-0000-0000-0000-000000000030', '00000000-0000-0000-0000-00000000000a', 'artikel-gelesen',
  pg_temp.als({{artikel-gelesen}}, 'f1000000-0000-0000-0000-000000000001'));
select pg_temp.verarbeite('e1000000-0000-0000-0000-000000000030');
select is((select title from public.activity_events where tenant_id = '00000000-0000-0000-0000-00000000000a' and type = 'article_read'), {{artikel-gelesen}} -> 'article' ->> 'title',
  'Artikel gelesen: Titel steht im Verlauf');
select ok((select last_app_activity_at is not null from public.customers where flenski_profile_id = 'f1000000-0000-0000-0000-000000000001'),
  'Letzte App-Aktivität wird mitgeführt');

select pg_temp.empfang('e1000000-0000-0000-0000-000000000031', '00000000-0000-0000-0000-00000000000a', 'kommentar-erstellt',
  pg_temp.als({{kommentar-erstellt}}, 'f1000000-0000-0000-0000-000000000001'));
select pg_temp.verarbeite('e1000000-0000-0000-0000-000000000031');
select ok((select title is null from public.activity_events where tenant_id = '00000000-0000-0000-0000-00000000000a' and type = 'comment_created'), 'Kommentar: kein Inhalt im Verlauf');
select ok((select payload #> '{comment,text}' is null and payload -> 'targetAuthor' is null and raw_body not like '%text%'
           from public.webhook_events where id = 'e1000000-0000-0000-0000-000000000031'),
  'Kommentartext und zweite Person werden nach der Prüfung aus dem Rohspeicher entfernt');

select pg_temp.empfang('e1000000-0000-0000-0000-000000000032', '00000000-0000-0000-0000-00000000000a', 'sperrbildschirm-cta-geklickt',
  pg_temp.als({{sperrbildschirm-cta-geklickt}}, 'f1000000-0000-0000-0000-000000000001'));
select is(pg_temp.verarbeite('e1000000-0000-0000-0000-000000000032'), 'ok', 'Sperrbildschirm-Klick wird verarbeitet');
select is((select title from public.activity_events where tenant_id = '00000000-0000-0000-0000-00000000000a' and type = 'lockscreen_cta'),
  {{sperrbildschirm-cta-geklickt}} -> 'lockScreen' ->> 'name', 'Sperrbildschirm: Name des Angebots im Verlauf');

select pg_temp.empfang('e1000000-0000-0000-0000-000000000033', '00000000-0000-0000-0000-00000000000a', 'zum-kurs-angemeldet',
  pg_temp.als({{zum-kurs-angemeldet}}, 'f1000000-0000-0000-0000-000000000001'));
select pg_temp.verarbeite('e1000000-0000-0000-0000-000000000033');
select is((select title from public.activity_events where tenant_id = '00000000-0000-0000-0000-00000000000a' and type = 'course_enrolled'), {{zum-kurs-angemeldet}} -> 'course' ->> 'title',
  'Kursanmeldung im Verlauf');

-- ===== Hinweise, Löschen, Kontakt =====
select pg_temp.empfang('e1000000-0000-0000-0000-000000000040', '00000000-0000-0000-0000-00000000000a', 'plan-entzogen',
  pg_temp.als({{plan-entzogen}}, 'f1000000-0000-0000-0000-000000000001'));
select pg_temp.verarbeite('e1000000-0000-0000-0000-000000000040');
select is((select kind from public.customer_notices where tenant_id = '00000000-0000-0000-0000-00000000000a' and kind = 'plan_entzogen'), 'plan_entzogen', 'Plan entzogen: Hinweis an der Person');
select is((select count(*)::int from public.entitlements e join public.customers c on c.id = e.customer_id
           where c.flenski_profile_id = 'f1000000-0000-0000-0000-000000000001' and e.status = 'active'), 1,
  'Plan entzogen löscht keine Karte (Guthaben bleibt sichtbar)');

select pg_temp.empfang('e1000000-0000-0000-0000-000000000041', '00000000-0000-0000-0000-00000000000a', 'zahlung-fehlgeschlagen',
  pg_temp.als({{zahlung-fehlgeschlagen}}, 'f1000000-0000-0000-0000-000000000001'));
select pg_temp.verarbeite('e1000000-0000-0000-0000-000000000041');
select ok(exists (select 1 from public.customer_notices where tenant_id = '00000000-0000-0000-0000-00000000000a' and kind = 'zahlung_fehlgeschlagen'), 'Zahlung fehlgeschlagen: Hinweis');

select pg_temp.empfang('e1000000-0000-0000-0000-000000000042', '00000000-0000-0000-0000-00000000000a', 'neuer-kontakt',
  {{neuer-kontakt}});
select pg_temp.verarbeite('e1000000-0000-0000-0000-000000000042');
select is((select source::text from public.customers where tenant_id = '00000000-0000-0000-0000-00000000000a' and email = lower({{neuer-kontakt}} ->> 'email')), 'extern',
  'Neuer Kontakt ohne App-Konto wird externe Person');

select pg_temp.empfang('e1000000-0000-0000-0000-000000000043', '00000000-0000-0000-0000-00000000000a', 'mitglied-geloescht',
  pg_temp.als({{mitglied-geloescht}}, 'f1000000-0000-0000-0000-000000000001'));
select pg_temp.verarbeite('e1000000-0000-0000-0000-000000000043');
select ok((select archived_at is not null from public.customers where flenski_profile_id = 'f1000000-0000-0000-0000-000000000001'),
  'Mitglied gelöscht: Person archiviert, Buchungen bleiben');

-- ===== Ausschluss per Tag (z. B. Lehrerinnen) =====
update public.tenants set settings = settings || '{"ausschluss_tags": ["Yogalehrerin"]}' where id = '00000000-0000-0000-0000-00000000000a';
select pg_temp.empfang('e1000000-0000-0000-0000-000000000050', '00000000-0000-0000-0000-00000000000a', 'neues-mitglied',
  jsonb_set(pg_temp.als({{neues-mitglied}}, 'f1000000-0000-0000-0000-000000000050'), '{member,tags}', '["Yogalehrerin"]'));
select pg_temp.verarbeite('e1000000-0000-0000-0000-000000000050');
select is((select count(*)::int from public.customers where flenski_profile_id = 'f1000000-0000-0000-0000-000000000050'), 0,
  'Profil mit Ausschluss-Tag „Yogalehrerin“ wird keine Kundin');

-- ===== Erstabgleich =====
select is(public.import_flenski_snapshot('00000000-0000-0000-0000-00000000000b', jsonb_build_object(
  'plans', jsonb_build_array(jsonb_build_object('id', 'b0000000-0000-0000-0000-000000000001', 'name', '10er-Karte')),
  'members', jsonb_build_array(
    jsonb_build_object('id', 'b1000000-0000-0000-0000-000000000001', 'fullName', 'Bea Beispiel', 'email', 'bea@test.local',
                       'tags', jsonb_build_array(), 'plans', jsonb_build_array('10er-Karte'), 'isMemberOfTeam', false, 'isAdmin', false),
    jsonb_build_object('id', 'b1000000-0000-0000-0000-000000000002', 'fullName', 'Lehrerin Team', 'isMemberOfTeam', true)),
  'events', jsonb_build_array(jsonb_build_object('id', 'b2000000-0000-0000-0000-000000000001', 'title', 'Yoga am Montag',
    'startsAt', '2027-01-11T19:00:00+01:00', 'endsAt', '2027-01-11T20:00:00+01:00', 'timeZone', 'Europe/Berlin',
    'category', jsonb_build_object('name', 'Yoga für Erwachsene'), 'participantsNumberLimit', 12,
    'recurringEventPattern', jsonb_build_object('frequency', 'weekly', 'repeatEvery', 1, 'totalOccurrences', 10),
    'lastAttended', jsonb_build_array('b1000000-0000-0000-0000-000000000001'))))),
  '{"personen": 1, "produkte": 1, "karten": 1, "serien": 1, "anmeldungen": 1}'::jsonb, 'Erstabgleich übernimmt Person, Plan, Karte, Serie, Anmeldung');
select is((select count(*)::int from public.sessions where tenant_id = '00000000-0000-0000-0000-00000000000b' and flenski_event_id = 'b2000000-0000-0000-0000-000000000001'), 1,
  'Serie: nur der Termin, den Flenski liefert (keine hochgerechneten Folgetermine)');
select ok((select bool_and((starts_at at time zone 'Europe/Berlin')::time = time '19:00') from public.sessions
           where flenski_event_id = 'b2000000-0000-0000-0000-000000000001'), 'Alle Termine um 19:00 Uhr (auch nach der Zeitumstellung)');
select public.import_flenski_snapshot('00000000-0000-0000-0000-00000000000b', jsonb_build_object(
  'members', jsonb_build_array(jsonb_build_object('id', 'b1000000-0000-0000-0000-000000000001', 'fullName', 'Bea Beispiel',
    'plans', jsonb_build_array('10er-Karte')))));
select is((select count(*)::int from public.entitlements e join public.customers c on c.id = e.customer_id
           where c.flenski_profile_id = 'b1000000-0000-0000-0000-000000000001'), 1, 'Erstabgleich zweimal = keine doppelte Karte');

-- ===== Rechte =====
select pg_temp.login('10000000-0000-0000-0000-00000000000b');
select is((select count(*)::int from public.customer_notices), 0, 'Mandantin B sieht keine Hinweise von A');
select throws_ok($$select public.process_pending_webhooks()$$, '42501', null, 'Nutzerinnen starten keine Verarbeitung');
select pg_temp.logout();

select * from finish();
rollback;
