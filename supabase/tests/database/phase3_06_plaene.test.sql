-- Neue Pläne aus der App erscheinen unter "Angebote" (über Make), auf Anforderung der Lehrerin sofort.
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;

insert into auth.users (id, email) values ('10000000-0000-0000-0000-00000000000a', 'owner-a@test.local'),
                                          ('10000000-0000-0000-0000-00000000000b', 'owner-b@test.local');
insert into public.tenants (id, name, slug, status, settings) values
  ('00000000-0000-0000-0000-00000000000a', 'Test A', 'test-a', 'active', '{"flenski_app_id": "aaaaaaaa-0000-0000-0000-000000000001"}'),
  ('00000000-0000-0000-0000-00000000000b', 'Test B', 'test-b', 'active', '{}');
insert into public.tenant_members (tenant_id, user_id, role) values
  ('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-00000000000a', 'owner'),
  ('00000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-00000000000b', 'owner');
insert into public.tenant_secrets (tenant_id, flenski_api_key, last_sync_at, make_webhook_url) values
  ('00000000-0000-0000-0000-00000000000a', 'test', now(), 'https://hook.example/test');

select ok(public.flenski_plaene_faellig('00000000-0000-0000-0000-00000000000a'), 'Noch nie geholt: fällig');
select is((select count(*)::int from public.flenski_faellige_mandanten() x where x = '00000000-0000-0000-0000-00000000000a'), 1,
  'Planliste fällig macht die Mandantin fällig');

select is(public.sync_flenski_plans('00000000-0000-0000-0000-00000000000a',
  '[{"id": "b0000000-0000-0000-0000-000000000001", "name": "Mitgliedschaft"}, {"id": "b0000000-0000-0000-0000-000000000002", "name": "Abo 2"}]'), 2,
  'Zwei neue Pläne erkannt');
select is((select count(*)::int from public.products where tenant_id = '00000000-0000-0000-0000-00000000000a' and needs_setup), 2,
  'Neue Pläne stehen als "noch nicht verbunden" bereit');
select ok(not public.flenski_plaene_faellig('00000000-0000-0000-0000-00000000000a'), 'Gerade geholt: nicht fällig');

select is(public.sync_flenski_plans('00000000-0000-0000-0000-00000000000a',
  '[{"id": "b0000000-0000-0000-0000-000000000002", "name": "Abo Premium"}]'), 0, 'Bekannter Plan ist nicht neu');
select is((select name from public.products where flenski_plan_id = 'b0000000-0000-0000-0000-000000000002'), 'Abo Premium',
  'Umbenannter Plan bekommt den neuen Namen');

-- Lehrerin fordert an → wieder fällig (letzter Abruf vor einer Minute)
update public.tenant_secrets set plans_synced_at = now() - interval '1 minute' where tenant_id = '00000000-0000-0000-0000-00000000000a';
select pg_temp.login('10000000-0000-0000-0000-00000000000a');
select lives_ok($$select public.request_plan_sync('00000000-0000-0000-0000-00000000000a')$$, 'Inhaberin kann neue Pläne anfordern');
select throws_ok($$select public.request_plan_sync('00000000-0000-0000-0000-00000000000b')$$, '42501', null,
  'Fremde Mandantin: keine Anforderung');
select throws_ok($$select public.sync_flenski_plans('00000000-0000-0000-0000-00000000000a', '[]')$$, '42501', null,
  'Nutzerinnen übernehmen keine Pläne selbst');
reset role;
select set_config('request.jwt.claims', '', true);
select ok(public.flenski_plaene_faellig('00000000-0000-0000-0000-00000000000a'), 'Nach Anforderung: sofort fällig');
select ok(not public.flenski_plaene_faellig('00000000-0000-0000-0000-00000000000b'), 'Ohne Make: nie fällig');

select * from finish();
rollback;
