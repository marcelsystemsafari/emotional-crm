-- Phase 1, Schritt 1: Mandantentrennung, Rollen und Mandantenstatus.
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

-- Anmelden als Nutzerin (simuliert das Supabase-Login-Token) bzw. wieder abmelden
create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;
create function pg_temp.logout() returns void language sql as $$
  select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
$$;
create function pg_temp.update_settings(p_tenant uuid) returns int language plpgsql as $$
declare n int;
begin
  update public.tenants set settings = settings || '{"test": 1}' where id = p_tenant;
  get diagnostics n = row_count;
  return n;
end $$;

insert into auth.users (id, email) values
  ('10000000-0000-0000-0000-00000000000a', 'owner-a@test.local'),
  ('20000000-0000-0000-0000-00000000000a', 'staff-a@test.local'),
  ('10000000-0000-0000-0000-00000000000b', 'owner-b@test.local'),
  ('90000000-0000-0000-0000-000000000000', 'admin@test.local');
insert into public.tenants (id, name, slug, status) values
  ('00000000-0000-0000-0000-00000000000a', 'Test A', 'test-a', 'active'),
  ('00000000-0000-0000-0000-00000000000b', 'Test B', 'test-b', 'active'),
  ('00000000-0000-0000-0000-00000000000c', 'Test ruhend', 'test-c', 'dormant'),
  ('00000000-0000-0000-0000-00000000000d', 'Test gekündigt', 'test-d', 'cancelled');
insert into public.tenant_members (tenant_id, user_id, role) values
  ('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-00000000000a', 'owner'),
  ('00000000-0000-0000-0000-00000000000a', '20000000-0000-0000-0000-00000000000a', 'staff'),
  ('00000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-00000000000b', 'owner'),
  ('00000000-0000-0000-0000-00000000000c', '10000000-0000-0000-0000-00000000000a', 'owner'),
  ('00000000-0000-0000-0000-00000000000d', '10000000-0000-0000-0000-00000000000b', 'owner');
insert into public.platform_admins (user_id) values ('90000000-0000-0000-0000-000000000000');

-- Owner A
select pg_temp.login('10000000-0000-0000-0000-00000000000a');
select results_eq('select slug from public.tenants order by slug', array['test-a'],
  'Owner A sieht nur Mandantin A (nicht B, nicht die ruhende C)');
select throws_ok('select webhook_secret from public.tenants', '42501', null, 'Webhook-Secret ist für Nutzerinnen unsichtbar');
select is(pg_temp.update_settings('00000000-0000-0000-0000-00000000000a'), 1, 'Owner darf Einstellungen ändern');
select is(pg_temp.update_settings('00000000-0000-0000-0000-00000000000b'), 0, 'Owner A kann Einstellungen von B nicht ändern');
select is((select count(*)::int from public.tenant_members), 2, 'Owner A sieht nur das Team von A');
select throws_ok(
  $$insert into public.tenant_members (tenant_id, user_id, role)
    values ('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-00000000000b', 'staff')$$,
  '42501', null, 'Owner kann niemanden selbst ins Team aufnehmen (nur Marcel)');
select pg_temp.logout();

-- Staff A
select pg_temp.login('20000000-0000-0000-0000-00000000000a');
select is(pg_temp.update_settings('00000000-0000-0000-0000-00000000000a'), 0, 'Staff darf Einstellungen nicht ändern');
select pg_temp.logout();

-- Owner B: B aktiv, D gekündigt (lesen ja, schreiben nein)
select pg_temp.login('10000000-0000-0000-0000-00000000000b');
select results_eq('select slug from public.tenants order by slug', array['test-b', 'test-d'],
  'Gekündigte Mandantin bleibt lesbar');
select ok(not public.can_write('00000000-0000-0000-0000-00000000000d'), 'Gekündigte Mandantin: keine Schreibrechte');
select is(pg_temp.update_settings('00000000-0000-0000-0000-00000000000d'), 0, 'Gekündigte Mandantin: Einstellungen gesperrt');
select pg_temp.logout();

-- Marcel als Plattform-Admin sieht alle
select pg_temp.login('90000000-0000-0000-0000-000000000000');
select ok((select count(*) from public.tenants where slug like 'test-%') = 4, 'Plattform-Admin sieht alle Mandantinnen');
select pg_temp.logout();

-- Ohne Login
set local role anon;
select throws_ok('select * from public.tenants', '42501', null, 'Ohne Login keine Mandantendaten');
reset role;

select * from finish();
rollback;
