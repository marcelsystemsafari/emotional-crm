-- Extern gezählte Pläne (z. B. Ninas 8er-Karte in Make): kein Abzug im CRM, nicht als Karte verbindbar.
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into public.tenants (id, name, slug, status, settings) values
  ('00000000-0000-0000-0000-00000000000a', 'Test A', 'test-a', 'active', '{"extern_plaene": ["b0000000-0000-0000-0000-000000000008"]}');
insert into public.customers (id, tenant_id, first_name, source) values
  ('c0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'Kundin', 'flenski');
insert into public.sessions (id, tenant_id, title, starts_at) values
  ('50000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'Online-Yoga', now() - interval '1 hour');

-- Plan kommt aus der App (wie beim Webhook "Plan zugewiesen")
select public._product_for_plan('00000000-0000-0000-0000-00000000000a', '{"id": "b0000000-0000-0000-0000-000000000008", "name": "YN 8er Karte"}');
select public._product_for_plan('00000000-0000-0000-0000-00000000000a', '{"id": "b0000000-0000-0000-0000-000000000009", "name": "Mitgliedschaft"}');

select is((select extern_gezaehlt from public.products where flenski_plan_id = 'b0000000-0000-0000-0000-000000000008'), true,
  '8er-Karte wird als extern gezählt markiert');
select is((select needs_setup from public.products where flenski_plan_id = 'b0000000-0000-0000-0000-000000000008'), false,
  'Extern gezählt: steht nicht unter "noch nicht verbunden"');
select is((select needs_setup from public.products where flenski_plan_id = 'b0000000-0000-0000-0000-000000000009'), true,
  'Andere Pläne bleiben normal zu verbinden');
select throws_ok($$select public.setup_product((select id from public.products where flenski_plan_id = 'b0000000-0000-0000-0000-000000000008'),
  'credits', 8, null, null, null)$$, 'P0001', null, 'Extern gezählter Plan lässt sich nicht als 8 Besuche verbinden');

-- Kundin hat die 8er-Karte, nimmt teil: kein Abzug im CRM
select public.sell('c0000000-0000-0000-0000-000000000001', (select id from public.products where flenski_plan_id = 'b0000000-0000-0000-0000-000000000008'),
  'app', null, now() - interval '1 day', 'flenski_plan', null);
select public.checkin('50000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001');
select is((select count(*)::int from public.ledger_entries where customer_id = 'c0000000-0000-0000-0000-000000000001'), 0,
  'Extern gezählt: das CRM bucht keinen Besuch ab');

select * from finish();
rollback;
