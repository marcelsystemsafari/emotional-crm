-- Phase 3 (neu), Schritt 2: Erstabgleich mit Flenski, Ausschluss per Tag, Anmeldung statt Besuch.
-- Erkenntnis 22.10.2026: Flenskis "Am Event teilgenommen" kommt schon bei der Anmeldung (Lanas Serien starten
-- erst im Januar 2027 und haben trotzdem "Teilnehmende"). Ein Besuch entsteht deshalb erst nach Terminbeginn.

-- Lana: Profile mit Tag "Yogalehrerin" sind Lehrerinnen, keine Kundinnen (Marcel, 22.10.2026)
update public.tenants set settings = settings || '{"ausschluss_tags": ["Yogalehrerin"]}'::jsonb where slug = 'yoga-by-lana';

create or replace function public._upsert_member(p_tenant uuid, p_member jsonb, p_event uuid) returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_profile uuid := nullif(p_member ->> 'id', '')::uuid;
  v_first text := nullif(btrim(p_member ->> 'firstName'), '');
  v_last text := nullif(btrim(p_member ->> 'lastName'), '');
  v_full text := nullif(btrim(p_member ->> 'fullName'), '');
  v_email text := nullif(lower(btrim(p_member ->> 'email')), '');
  v_tags text[] := coalesce(array(select jsonb_array_elements_text(case when jsonb_typeof(p_member -> 'tags') = 'array' then p_member -> 'tags' end)), '{}');
  v_id uuid;
  v_dublette uuid;
  v_ausschluss text[];
begin
  if v_profile is null then return null; end if;
  -- Profile mit Ausschluss-Tag (z. B. "Yogalehrerin") sind keine Kundinnen (tenants.settings.ausschluss_tags)
  select coalesce(array(select jsonb_array_elements_text(settings -> 'ausschluss_tags')), '{}') into v_ausschluss
  from public.tenants where id = p_tenant;
  if v_tags && v_ausschluss then return null; end if;
  if coalesce((p_member ->> 'isMemberOfTeam')::boolean, false) or coalesce((p_member ->> 'isAdmin')::boolean, false) then
    return null;
  end if;
  if v_first is null then
    v_first := coalesce(split_part(v_full, ' ', 1), 'Mitglied');
    v_last := coalesce(v_last, nullif(btrim(substr(v_full, length(split_part(v_full, ' ', 1)) + 1)), ''));
  end if;

  select id into v_id from public.customers where tenant_id = p_tenant and flenski_profile_id = v_profile;
  if v_id is not null then
    update public.customers
    set first_name = v_first, last_name = v_last, email = coalesce(v_email, email),
        tags = (select array(select distinct unnest(tags || v_tags)))
    where id = v_id and anonymized_at is null;
    return v_id;
  end if;

  insert into public.customers (tenant_id, first_name, last_name, email, source, flenski_profile_id, tags)
  values (p_tenant, v_first, v_last, v_email, 'flenski', v_profile, v_tags)
  returning id into v_id;

  -- Mögliche Dublette: gleiche E-Mail bei einer Person ohne App-Verknüpfung – nicht zusammenführen, nur Hinweis
  if v_email is not null then
    select id into v_dublette from public.customers
    where tenant_id = p_tenant and id <> v_id and lower(email) = v_email and anonymized_at is null limit 1;
    if v_dublette is not null then
      insert into public.customer_notices (tenant_id, customer_id, kind, detail, webhook_event_id)
      values (p_tenant, v_id, 'moegliche_dublette', jsonb_build_object('andere_person', v_dublette), p_event);
    end if;
  end if;
  return v_id;
end $$;

create or replace function public.process_webhook_event(p_id uuid) returns text
language plpgsql security definer
set search_path = ''
as $$
declare
  w public.webhook_events;
  t public.tenants;
  p jsonb;
  v_ev text;
  v_at timestamptz;
  v_cust uuid;
  v_profile uuid;
  v_prod uuid;
  v_sess uuid;
  v_plan jsonb;
  v_first boolean := true;
  v_price int;
  v_ergebnis text := 'ok';
begin
  if not (public.is_system() or public.is_platform_admin()) then
    raise exception 'Nur für den Webhook-Empfänger.' using errcode = '42501';
  end if;
  select * into w from public.webhook_events where id = p_id for update;
  if not found or w.processed_at is not null then return 'schon verarbeitet'; end if;
  if w.signature_valid is not true then
    update public.webhook_events set error = 'übersprungen: Signatur ' || coalesce(w.signature_valid::text, 'unbekannt') where id = p_id;
    return 'übersprungen';
  end if;
  select * into t from public.tenants where id = w.tenant_id;
  if t.status not in ('trial', 'active') then
    update public.webhook_events set error = 'übersprungen: Mandantin ' || t.status where id = p_id;
    return 'übersprungen';
  end if;

  p := w.payload;
  v_ev := p -> 'envelope' ->> 'event';
  v_at := coalesce(public._ts(p -> 'envelope' ->> 'occurredAt'), w.received_at);
  v_profile := nullif(p -> 'member' ->> 'id', '')::uuid;

  begin
    if p ? 'member' then
      v_cust := public._upsert_member(w.tenant_id, p -> 'member', w.id);
    end if;

    case v_ev
      when 'new_member' then
        null;  -- Person wurde oben angelegt

      when 'lead_created' then
        -- Kontakt ohne App-Konto (z. B. Anfrage): als externe Person, Dublettenprüfung per E-Mail
        if not exists (select 1 from public.customers where tenant_id = w.tenant_id and lower(email) = lower(p ->> 'email')) then
          insert into public.customers (tenant_id, first_name, last_name, email, phone, source, tags)
          values (w.tenant_id, coalesce(nullif(split_part(p ->> 'fullName', ' ', 1), ''), 'Kontakt'),
                  nullif(btrim(substr(p ->> 'fullName', length(split_part(p ->> 'fullName', ' ', 1)) + 1)), ''),
                  nullif(lower(p ->> 'email'), ''), nullif(p ->> 'phone', ''), 'extern', '{Kontakt aus der App}');
        end if;

      when 'member_plan_assigned' then
        if v_cust is not null then
          v_prod := public._product_for_plan(w.tenant_id, p -> 'plan');
          perform public._app_entitlement(v_cust, v_prod, v_at, 'flenski_plan', null, null);
        end if;

      when 'order_completed' then
        if v_cust is not null then
          v_price := round((p -> 'order' ->> 'amount')::numeric * 100)::int;
          for v_plan in select * from jsonb_array_elements(coalesce(p -> 'plans', '[]')) loop
            v_prod := public._product_for_plan(w.tenant_id, v_plan);
            perform public._app_entitlement(v_cust, v_prod, v_at, 'flenski_order',
              case when v_first then v_price end, p -> 'order' ->> 'orderId');
            v_first := false;
          end loop;
        end if;

      when 'member_plan_removed' then
        perform public._notice(w.tenant_id, v_cust, 'plan_entzogen',
          jsonb_build_object('plan', p -> 'plan' ->> 'name', 'grund', p ->> 'reason'), w.id);

      when 'subscription_cancelled' then
        perform public._notice(w.tenant_id, v_cust, 'abo_gekuendigt',
          jsonb_build_object('produkt', p -> 'subscription' ->> 'productName', 'bezahlt_bis', p ->> 'lastPaidDay'), w.id);

      when 'payment_failed' then
        perform public._notice(w.tenant_id, v_cust, 'zahlung_fehlgeschlagen',
          jsonb_build_object('produkt', p -> 'subscription' ->> 'productName', 'versuch', p ->> 'attemptNumber'), w.id);

      when 'member_deleted' then
        if v_cust is not null then
          update public.customers set archived_at = coalesce(archived_at, v_at) where id = v_cust;
          perform public._notice(w.tenant_id, v_cust, 'mitglied_geloescht', jsonb_build_object('grund', p ->> 'reason'), w.id);
        end if;

      when 'event_starts_soon' then
        -- Erinnerung geht an Angemeldete: also ist die Person angemeldet
        v_sess := public._session_for_event(w.tenant_id, p -> 'event', p -> 'category');
        if v_sess is not null and v_cust is not null then
          insert into public.attendances (tenant_id, session_id, customer_id)
          values (w.tenant_id, v_sess, v_cust) on conflict (session_id, customer_id) do nothing;
        end if;

      when 'event_attended' then
        -- Flenski meldet "teilgenommen" schon bei der Anmeldung (auch für Termine in der Zukunft).
        -- Deshalb: angemeldet. Nach Terminbeginn macht finalize_past_sessions() daraus "da" + Abbuchung.
        v_sess := public._session_for_event(w.tenant_id, p -> 'event', p -> 'category');
        if v_sess is not null and v_cust is not null then
          insert into public.attendances (tenant_id, session_id, customer_id)
          values (w.tenant_id, v_sess, v_cust) on conflict (session_id, customer_id) do nothing;
        end if;
        perform public._activity(w.tenant_id, v_cust, v_profile, 'event_attended', p -> 'event' ->> 'title', v_at, w.id,
          'event_attended:' || v_profile || ':' || (p -> 'event' ->> 'id') || ':' || (p -> 'event' ->> 'startAt'));

      when 'course_enrolled' then
        perform public._activity(w.tenant_id, v_cust, v_profile, 'course_enrolled', p -> 'course' ->> 'title', v_at, w.id,
          'course_enrolled:' || v_profile || ':' || (p -> 'course' ->> 'id'));
      when 'course_completed' then
        perform public._activity(w.tenant_id, v_cust, v_profile, 'course_completed', p -> 'course' ->> 'title', v_at, w.id,
          'course_completed:' || v_profile || ':' || (p -> 'course' ->> 'id'));
      when 'groups_post_created', 'community_post_created' then
        perform public._activity(w.tenant_id, v_cust, v_profile, 'post_created', p -> 'space' ->> 'name', v_at, w.id,
          'post:' || coalesce(p -> 'post' ->> 'id', w.dedupe_key));
      when 'comment_created' then
        perform public._activity(w.tenant_id, v_cust, v_profile, 'comment_created', null, v_at, w.id,
          'comment:' || coalesce(p -> 'comment' ->> 'id', w.dedupe_key));
      when 'question_created', 'question_asked' then
        perform public._activity(w.tenant_id, v_cust, v_profile, 'question_asked', null, v_at, w.id, 'question:' || w.dedupe_key);
      when 'file_downloaded' then
        perform public._activity(w.tenant_id, v_cust, v_profile, 'file_downloaded', p -> 'download' ->> 'title', v_at, w.id,
          'download:' || v_profile || ':' || (p -> 'download' ->> 'id') || ':' || v_at);
      when 'article_viewed' then
        perform public._activity(w.tenant_id, v_cust, v_profile, 'article_read', p -> 'article' ->> 'title', v_at, w.id,
          'article:' || v_profile || ':' || (p -> 'article' ->> 'id'));
      when 'lock_screen_viewed', 'lock_screen_cta_clicked' then
        perform public._activity(w.tenant_id, v_cust, v_profile, 'lockscreen_cta', p -> 'lockScreen' ->> 'name', v_at, w.id,
          'lockscreen:' || v_profile || ':' || (p -> 'lockScreen' ->> 'id') || ':' || v_at);
      else
        v_ergebnis := 'unbekanntes Ereignis ' || coalesce(v_ev, '–');
    end case;

    -- Datenschutz (Regel 10): Inhalte von Beiträgen/Kommentaren und die zweite Person nicht aufbewahren
    if v_ev in ('groups_post_created', 'community_post_created', 'comment_created', 'question_created', 'question_asked') then
      update public.webhook_events
      set payload = (payload #- '{post,text}' #- '{comment,text}' #- '{target,title}' #- '{question,text}') - 'targetAuthor',
          raw_body = '[Inhalt nach Prüfung entfernt]'
      where id = p_id;
    end if;

    update public.webhook_events set processed_at = now(), error = nullif(v_ergebnis, 'ok') where id = p_id;
    return v_ergebnis;
  exception when others then
    update public.webhook_events set error = left(sqlerrm, 500) where id = p_id;
    return 'Fehler: ' || sqlerrm;
  end;
end $$;

-- Termine aus der App, deren Beginn vorbei ist: Angemeldete gelten als da (Besuch + Abbuchung).
-- Nur Termine aus Flenski – von Hand angelegte Stunden behalten ihre Liste, wie sie ist.
create or replace function public.finalize_past_sessions() returns int
language plpgsql security definer
set search_path = ''
as $$
declare
  v_a record;
  v_anzahl int := 0;
begin
  if not (public.is_system() or public.is_platform_admin()) then
    raise exception 'Nur für den automatischen Ablauf.' using errcode = '42501';
  end if;
  for v_a in
    select a.session_id, a.customer_id
    from public.attendances a
    join public.sessions s on s.id = a.session_id
    join public.tenants t on t.id = a.tenant_id
    where a.status = 'registered' and s.flenski_event_id is not null and s.starts_at <= now()
      and t.status in ('trial', 'active')
    order by s.starts_at
  loop
    perform public.checkin(v_a.session_id, v_a.customer_id);
    v_anzahl := v_anzahl + 1;
  end loop;
  return v_anzahl;
end $$;

-- Termine einer Flenski-Serie anlegen (wöchentlich, gleiche Uhrzeit auch über die Zeitumstellung)
create or replace function public._sessions_for_series(p_tenant uuid, p_event jsonb) returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_tz text := coalesce(nullif(p_event ->> 'timeZone', ''), 'Europe/Berlin');
  v_start timestamptz := public._ts(p_event ->> 'startsAt');
  v_end timestamptz := public._ts(p_event ->> 'endsAt');
  v_rec jsonb := p_event -> 'recurringEventPattern';
  v_anzahl int := 1;
  v_schritt int := 7;
  v_first uuid;
  v_id uuid;
  i int;
begin
  if v_start is null then return null; end if;
  if jsonb_typeof(v_rec) = 'object' and v_rec ->> 'frequency' = 'weekly' then
    v_anzahl := least(coalesce((v_rec ->> 'totalOccurrences')::int, 26), 52);
    v_schritt := 7 * greatest(coalesce((v_rec ->> 'repeatEvery')::int, 1), 1);
  end if;
  for i in 0 .. v_anzahl - 1 loop
    v_id := public._session_for_event(p_tenant,
      jsonb_build_object('id', p_event ->> 'id', 'title', coalesce(p_event ->> 'title', p_event ->> 'name'),
        'startAt', ((v_start at time zone v_tz) + make_interval(days => i * v_schritt)) at time zone v_tz,
        'endAt', case when v_end is not null then ((v_end at time zone v_tz) + make_interval(days => i * v_schritt)) at time zone v_tz end),
      p_event -> 'category');
    if i = 0 then v_first := v_id; end if;
    update public.sessions set capacity = nullif((p_event ->> 'participantsNumberLimit')::int, 0)
    where id = v_id and capacity is null;
  end loop;
  return v_first;
end $$;

-- Erstabgleich: Stand aus Flenski übernehmen (Mitglieder, Pläne, Events). Mehrfach ausführbar.
-- p_data: {"members": [...member_list...], "plans": [...plan_list...], "events": [...event_list...]}
create or replace function public.import_flenski_snapshot(p_tenant uuid, p_data jsonb) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_m jsonb; v_p jsonb; v_e jsonb; v_name text; v_profile text;
  v_cust uuid; v_prod uuid; v_sess uuid;
  v_personen int := 0; v_produkte int := 0; v_termine int := 0; v_anmeldungen int := 0; v_karten int := 0;
begin
  if not (public.is_system() or public.is_platform_admin()) then
    raise exception 'Nur für den Erstabgleich durch Systemsafari.' using errcode = '42501';
  end if;

  for v_p in select * from jsonb_array_elements(coalesce(p_data -> 'plans', '[]')) loop
    v_prod := public._product_for_plan(p_tenant, v_p);
    v_produkte := v_produkte + 1;
  end loop;

  for v_m in select * from jsonb_array_elements(coalesce(p_data -> 'members', '[]')) loop
    v_cust := public._upsert_member(p_tenant, v_m, null);
    if v_cust is null then continue; end if;
    v_personen := v_personen + 1;
    -- Pläne der Person (Flenski liefert hier nur Namen): Karte anlegen, falls es noch keine aus der App gibt
    for v_name in select jsonb_array_elements_text(case when jsonb_typeof(v_m -> 'plans') = 'array' then v_m -> 'plans' end) loop
      select id into v_prod from public.products where tenant_id = p_tenant and name = v_name and flenski_plan_id is not null limit 1;
      if v_prod is not null and not exists (
        select 1 from public.entitlements where customer_id = v_cust and product_id = v_prod and source in ('flenski_plan', 'flenski_order')) then
        perform public.sell(v_cust, v_prod, 'app', null, now(), 'flenski_plan', 'Erstabgleich');
        v_karten := v_karten + 1;
      end if;
    end loop;
  end loop;

  for v_e in select * from jsonb_array_elements(coalesce(p_data -> 'events', '[]')) loop
    v_sess := public._sessions_for_series(p_tenant, v_e);
    if v_sess is null then continue; end if;
    v_termine := v_termine + 1;
    -- Angemeldete (Flenski: lastAttended) beim ersten Termin der Serie eintragen
    for v_profile in select coalesce(x ->> 'id', x #>> '{}') from jsonb_array_elements(coalesce(v_e -> 'lastAttended', '[]')) x loop
      select id into v_cust from public.customers where tenant_id = p_tenant and flenski_profile_id = nullif(v_profile, '')::uuid;
      if v_cust is not null then
        insert into public.attendances (tenant_id, session_id, customer_id) values (p_tenant, v_sess, v_cust)
        on conflict (session_id, customer_id) do nothing;
        v_anmeldungen := v_anmeldungen + 1;
      end if;
    end loop;
  end loop;

  return jsonb_build_object('personen', v_personen, 'produkte', v_produkte, 'karten', v_karten,
                            'serien', v_termine, 'anmeldungen', v_anmeldungen);
end $$;

revoke execute on function public._sessions_for_series from public, anon, authenticated;
revoke execute on function public.finalize_past_sessions, public.import_flenski_snapshot from public, anon;
grant execute on function public.finalize_past_sessions, public.import_flenski_snapshot to authenticated, service_role;

select cron.schedule('ecrm-termine-abschliessen', '*/15 * * * *', 'select public.finalize_past_sessions()');
