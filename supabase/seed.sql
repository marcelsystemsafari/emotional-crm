-- Demo-Mandantin "Yoga by Lana (Demo)" mit erfundenen Kundinnen. Alle Namen sind ausgedacht.
-- Daten relativ zu heute, damit jedes Signal vorkommt. Läuft nur einmal (bricht ab, wenn die Demo schon existiert).
-- Ausführen: node scripts/sql.mjs -f supabase/seed.sql
do $$
declare
  v_t uuid;
  p_kinder uuid;
  p_zehner uuid;
  v_heute date := (now() at time zone 'Europe/Berlin')::date;
  -- Wochentage: Erwachsene dienstags 18:30, Kinderyoga donnerstags 16:00
  v_di date := v_heute - ((extract(isodow from v_heute)::int - 2 + 7) % 7);
  v_do date := v_heute - ((extract(isodow from v_heute)::int - 4 + 7) % 7);
  v_erw uuid[] := '{}';
  v_kid uuid[] := '{}';
  v_id uuid;
  k record;
  i int;
begin
  if exists (select 1 from public.tenants where slug = 'yoga-by-lana-demo') then
    raise notice 'Demo existiert bereits – nichts zu tun.';
    return;
  end if;

  insert into public.tenants (name, slug, status, flenski_app_url, settings)
  values ('Yoga by Lana (Demo)', 'yoga-by-lana-demo', 'active', 'https://appdemo.systemsafari.de/yoga-by-lana',
    '{"storno_frist_stunden": 12, "abzug_bei_spaeter_absage": true, "abzug_bei_no_show": true,
      "signal_inaktiv_tage": 21, "signal_ablauf_tage": 14, "signal_fast_leer_ab": 1, "signal_neu_tage": 14,
      "engagement_neu_tage": 14, "engagement_aktiv_tage": 14, "engagement_abkuehlt_tage": 30}')
  returning id into v_t;

  insert into public.products (tenant_id, name, type, credits, validity_days, price_cents, category)
  values (v_t, 'Kinderyoga 4er-Paket', 'credits', 4, 90, 6000, 'Kinderyoga') returning id into p_kinder;
  insert into public.products (tenant_id, name, type, credits, validity_days, price_cents, category)
  values (v_t, 'Kursblock Erwachsene (10er-Karte)', 'credits', 10, 70, 15000, 'Erwachsene') returning id into p_zehner;

  -- Stunden: letzte 9 Wochen + nächste Woche
  for i in -9..1 loop
    insert into public.sessions (tenant_id, title, starts_at, ends_at, category)
    values (v_t, 'Yoga am Dienstag', ((v_di + i * 7) + time '18:30') at time zone 'Europe/Berlin',
            ((v_di + i * 7) + time '19:45') at time zone 'Europe/Berlin', 'Erwachsene')
    returning id into v_id;
    v_erw := v_erw || v_id;
    insert into public.sessions (tenant_id, title, starts_at, ends_at, category)
    values (v_t, 'Kinderyoga', ((v_do + i * 7) + time '16:00') at time zone 'Europe/Berlin',
            ((v_do + i * 7) + time '16:45') at time zone 'Europe/Berlin', 'Kinderyoga')
    returning id into v_id;
    v_kid := v_kid || v_id;
  end loop;
  -- v_erw[1] = vor 9 Wochen … v_erw[10] = diese Woche, v_erw[11] = nächste Woche

  -- Kundinnen: kauf_vor = Tage seit Kauf (null = keine Karte), besuche = Indizes in v_erw/v_kid
  for k in
    select * from (values
      ('Sabine',   'Krüger',    'sabine.krueger@example.com',  'flenski', false, null::text,     'z',  28, '{6,7,8,9,10}'::int[]),
      ('Melanie',  'Hoffmann',  'melanie.h@example.com',       'flenski', false, null,           'z',  35, '{5,6,7,8,9,10}'),
      ('Katrin',   'Wagner',    null,                          'extern',  false, null,           'z',  30, '{6,7,9,10}'),
      ('Julia',    'Schmitt',   'julia.schmitt@example.com',   'flenski', false, null,           'z',  21, '{8,9,10}'),
      ('Nicole',   'Becker',    null,                          'extern',  false, null,           'z',  40, '{4,5,6,8,9}'),
      ('Petra',    'Neumann',   'petra.neumann@example.com',   'flenski', false, null,           'z',  45, '{4,5}'),
      ('Andrea',   'Wolf',      'andrea.wolf@example.com',     'flenski', false, null,           'z',  62, '{2,3,4,5,6,7,8,9,10}'),
      ('Stefanie', 'Schröder',  null,                          'extern',  false, null,           'z',  63, '{2,3,6,8,10}'),
      ('Lisa',     'Fischer',   'lisa.fischer@example.com',    'flenski', false, null,           'z',   8, '{10}'),
      ('Martina',  'Weber',     null,                          'extern',  false, null,           null, null, '{10}'),
      ('Claudia',  'Meyer',     'claudia.meyer@example.com',   'flenski', false, null,           null, null, '{}'),
      ('Mia',      'Becker',    null,                          'extern',  true,  'Jana Becker',  'k',  20, '{8,9,10}'),
      ('Ben',      'Schulz',    null,                          'extern',  true,  'Tom Schulz',   'k',  50, '{3,4,5,6}'),
      ('Emma',     'Richter',   null,                          'flenski', true,  'Sandra Richter','k', 15, '{9,10}'),
      ('Paul',     'Klein',     null,                          'extern',  true,  'Nina Klein',   'k',  60, '{2,3,4,5,8,10}')
    ) as t(vorname, nachname, email, quelle, kind, eltern, karte, kauf_vor, besuche)
  loop
    insert into public.customers (tenant_id, first_name, last_name, email, source, flenski_profile_id,
                                  is_child, guardian_name, guardian_email, tags, archived_at)
    values (v_t, k.vorname, k.nachname, k.email, k.quelle::public.customer_source,
            case when k.quelle = 'flenski' then gen_random_uuid() end,
            k.kind, k.eltern,
            case when k.eltern is not null then lower(split_part(k.eltern, ' ', 1)) || '@example.com' end,
            case when k.kind then '{Kinderyoga}' else '{Erwachsene}' end::text[],
            case when k.vorname = 'Claudia' then now() - interval '20 days' end)
    returning id into v_id;

    if k.karte is not null then
      perform public.sell(v_id, case k.karte when 'z' then p_zehner else p_kinder end,
                          case when k.quelle = 'flenski' then 'app' else 'bar' end::public.paid_via,
                          null, now() - make_interval(days => k.kauf_vor),
                          case when k.quelle = 'flenski' then 'flenski_order' else 'manual' end::public.entitlement_source);
    end if;
    for i in select unnest(k.besuche) loop
      perform public.checkin(case when k.kind then v_kid[i] else v_erw[i] end, v_id);
    end loop;
  end loop;

  -- Nächste Woche schon angemeldet (Check-in vorbefüllt)
  insert into public.attendances (tenant_id, session_id, customer_id)
  select v_t, v_erw[11], c.id from public.customers c
  where c.tenant_id = v_t and c.first_name in ('Sabine', 'Melanie', 'Julia', 'Lisa');

  -- Eine verpasste Stunde ohne Absage
  perform public.cancel_attendance(v_erw[9], (select id from public.customers where tenant_id = v_t and first_name = 'Katrin'), true);

  raise notice 'Demo angelegt: %', v_t;
end $$;
