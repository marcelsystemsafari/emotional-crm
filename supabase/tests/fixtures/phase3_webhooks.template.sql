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

-- ===== Teilnahme an einem Event =====
select pg_temp.empfang('e1000000-0000-0000-0000-000000000020', '00000000-0000-0000-0000-00000000000a', 'am-event-teilgenommen',
  pg_temp.als({{am-event-teilgenommen}}, 'f1000000-0000-0000-0000-000000000001'));
select is(pg_temp.verarbeite('e1000000-0000-0000-0000-000000000020'), 'ok', 'Event-Teilnahme wird verarbeitet');
select is((select a.status::text || ':' || s.title from public.attendances a join public.sessions s on s.id = a.session_id
           join public.customers c on c.id = a.customer_id where c.flenski_profile_id = 'f1000000-0000-0000-0000-000000000001'),
  'present:' || ({{am-event-teilgenommen}} -> 'event' ->> 'title'), 'Teilnahme = anwesend in der Stunde aus der App');
select is((select category from public.sessions where flenski_event_id = ({{am-event-teilgenommen}} -> 'event' ->> 'id')::uuid),
  {{am-event-teilgenommen}} -> 'category' ->> 'name', 'Stunde übernimmt die Event-Kategorie');
select is((select count(*)::int from public.activity_events where type = 'event_attended'), 1, 'Teilnahme steht auch im Aktivitätsverlauf');

-- ===== Produkt einrichten: Teilnahme wird nachträglich abgebucht =====
select pg_temp.login('20000000-0000-0000-0000-00000000000a');
select throws_ok($$select public.setup_product((select id from public.products where needs_setup limit 1), 'credits', 10, 70, null, null)$$,
  '42501', null, 'Staff richtet keine Produkte ein');
select pg_temp.logout();
select pg_temp.login('10000000-0000-0000-0000-00000000000a');
select is(public.setup_product((select id from public.products where needs_setup limit 1), 'credits', 10, 120, null, null), 1,
  'Owner richtet das Produkt ein (eine bestehende Karte)');
select is((select credits_balance from public.v_customer_overview o join public.customers c on c.id = o.customer_id
           where c.flenski_profile_id = 'f1000000-0000-0000-0000-000000000001'), 9,
  'Nach dem Einrichten: 10 gekauft, 1 Teilnahme nachträglich abgebucht = 9');
select pg_temp.logout();

-- ===== Aktivität =====
select pg_temp.empfang('e1000000-0000-0000-0000-000000000030', '00000000-0000-0000-0000-00000000000a', 'artikel-gelesen',
  pg_temp.als({{artikel-gelesen}}, 'f1000000-0000-0000-0000-000000000001'));
select pg_temp.verarbeite('e1000000-0000-0000-0000-000000000030');
select is((select title from public.activity_events where type = 'article_read'), {{artikel-gelesen}} -> 'article' ->> 'title',
  'Artikel gelesen: Titel steht im Verlauf');
select ok((select last_app_activity_at is not null from public.customers where flenski_profile_id = 'f1000000-0000-0000-0000-000000000001'),
  'Letzte App-Aktivität wird mitgeführt');

select pg_temp.empfang('e1000000-0000-0000-0000-000000000031', '00000000-0000-0000-0000-00000000000a', 'kommentar-erstellt',
  pg_temp.als({{kommentar-erstellt}}, 'f1000000-0000-0000-0000-000000000001'));
select pg_temp.verarbeite('e1000000-0000-0000-0000-000000000031');
select ok((select title is null from public.activity_events where type = 'comment_created'), 'Kommentar: kein Inhalt im Verlauf');
select ok((select payload #> '{comment,text}' is null and payload -> 'targetAuthor' is null and raw_body not like '%text%'
           from public.webhook_events where id = 'e1000000-0000-0000-0000-000000000031'),
  'Kommentartext und zweite Person werden nach der Prüfung aus dem Rohspeicher entfernt');

select pg_temp.empfang('e1000000-0000-0000-0000-000000000032', '00000000-0000-0000-0000-00000000000a', 'sperrbildschirm-cta-geklickt',
  pg_temp.als({{sperrbildschirm-cta-geklickt}}, 'f1000000-0000-0000-0000-000000000001'));
select is(pg_temp.verarbeite('e1000000-0000-0000-0000-000000000032'), 'ok', 'Sperrbildschirm-Klick wird verarbeitet');
select is((select title from public.activity_events where type = 'lockscreen_cta'),
  {{sperrbildschirm-cta-geklickt}} -> 'lockScreen' ->> 'name', 'Sperrbildschirm: Name des Angebots im Verlauf');

select pg_temp.empfang('e1000000-0000-0000-0000-000000000033', '00000000-0000-0000-0000-00000000000a', 'zum-kurs-angemeldet',
  pg_temp.als({{zum-kurs-angemeldet}}, 'f1000000-0000-0000-0000-000000000001'));
select pg_temp.verarbeite('e1000000-0000-0000-0000-000000000033');
select is((select title from public.activity_events where type = 'course_enrolled'), {{zum-kurs-angemeldet}} -> 'course' ->> 'title',
  'Kursanmeldung im Verlauf');

-- ===== Hinweise, Löschen, Kontakt =====
select pg_temp.empfang('e1000000-0000-0000-0000-000000000040', '00000000-0000-0000-0000-00000000000a', 'plan-entzogen',
  pg_temp.als({{plan-entzogen}}, 'f1000000-0000-0000-0000-000000000001'));
select pg_temp.verarbeite('e1000000-0000-0000-0000-000000000040');
select is((select kind from public.customer_notices where kind = 'plan_entzogen'), 'plan_entzogen', 'Plan entzogen: Hinweis an der Person');
select is((select count(*)::int from public.entitlements e join public.customers c on c.id = e.customer_id
           where c.flenski_profile_id = 'f1000000-0000-0000-0000-000000000001' and e.status = 'active'), 1,
  'Plan entzogen löscht keine Karte (Guthaben bleibt sichtbar)');

select pg_temp.empfang('e1000000-0000-0000-0000-000000000041', '00000000-0000-0000-0000-00000000000a', 'zahlung-fehlgeschlagen',
  pg_temp.als({{zahlung-fehlgeschlagen}}, 'f1000000-0000-0000-0000-000000000001'));
select pg_temp.verarbeite('e1000000-0000-0000-0000-000000000041');
select ok(exists (select 1 from public.customer_notices where kind = 'zahlung_fehlgeschlagen'), 'Zahlung fehlgeschlagen: Hinweis');

select pg_temp.empfang('e1000000-0000-0000-0000-000000000042', '00000000-0000-0000-0000-00000000000a', 'neuer-kontakt',
  {{neuer-kontakt}});
select pg_temp.verarbeite('e1000000-0000-0000-0000-000000000042');
select is((select source::text from public.customers where email = lower({{neuer-kontakt}} ->> 'email')), 'extern',
  'Neuer Kontakt ohne App-Konto wird externe Person');

select pg_temp.empfang('e1000000-0000-0000-0000-000000000043', '00000000-0000-0000-0000-00000000000a', 'mitglied-geloescht',
  pg_temp.als({{mitglied-geloescht}}, 'f1000000-0000-0000-0000-000000000001'));
select pg_temp.verarbeite('e1000000-0000-0000-0000-000000000043');
select ok((select archived_at is not null from public.customers where flenski_profile_id = 'f1000000-0000-0000-0000-000000000001'),
  'Mitglied gelöscht: Person archiviert, Buchungen bleiben');

-- ===== Rechte =====
select pg_temp.login('10000000-0000-0000-0000-00000000000b');
select is((select count(*)::int from public.customer_notices), 0, 'Mandantin B sieht keine Hinweise von A');
select throws_ok($$select public.process_pending_webhooks()$$, '42501', null, 'Nutzerinnen starten keine Verarbeitung');
select pg_temp.logout();

select * from finish();
rollback;
