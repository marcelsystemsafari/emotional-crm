-- Phase 3 (neu), Schritt 1: Flenski-Webhooks verarbeiten (Entscheidung 0005, docs/phase3-plan.md).
-- (Wiederholbar geschrieben: ein erster Einspielversuch war am 22.10.2026 nach Teilschritten abgebrochen.)
-- Grundlage sind die echten Payloads in inbox/webhooks/ (Format siehe docs/04, "Ergebnisse Phase 0").
-- Verarbeitet werden nur Nachrichten mit gültiger Signatur; jede Nachricht wirkt genau einmal.
-- Team- und Admin-Profile (z. B. die Lehrerin selbst) werden nicht als Kundinnen geführt.

alter type public.activity_type add value if not exists 'lockscreen_cta';

-- Produkte aus Flenski-Plänen: Flenski kennt keine Einheiten/Gültigkeit/Preis. Bis die Lehrerin das einmal
-- einrichtet, gilt das Produkt als "Zeitraum" (Teilnahme ohne Abzug) und ist als einzurichten markiert.
alter table public.products add column if not exists needs_setup boolean not null default false;

-- Hinweise an der Person (Übersicht "Um diese Menschen kümmerst du dich jetzt")
create table if not exists public.customer_notices (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants (id),
  customer_id      uuid,
  kind             text not null,
  detail           jsonb not null default '{}'::jsonb,
  webhook_event_id uuid references public.webhook_events (id) on delete set null,
  created_at       timestamptz not null default now(),
  resolved_at      timestamptz,
  resolved_by      uuid,
  foreign key (tenant_id, customer_id) references public.customers (tenant_id, id)
);
create index if not exists customer_notices_open_idx on public.customer_notices (tenant_id, created_at desc) where resolved_at is null;
alter table public.customer_notices enable row level security;
grant select on public.customer_notices to authenticated;
grant update (resolved_at, resolved_by) on public.customer_notices to authenticated;
drop policy if exists notices_lesen on public.customer_notices;
create policy notices_lesen on public.customer_notices for select to authenticated using (public.can_read(tenant_id));
drop policy if exists notices_erledigen on public.customer_notices;
create policy notices_erledigen on public.customer_notices for update to authenticated
  using (public.can_write(tenant_id)) with check (public.can_write(tenant_id));

-- ===== Hilfsfunktionen =====

create or replace function public._ts(p_text text) returns timestamptz
language sql immutable
set search_path = ''
as $$ select nullif(p_text, '')::timestamptz $$;

-- Person aus dem Flenski-Mitglied anlegen oder aktualisieren. Gibt null für Team/Admin zurück.
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
begin
  if v_profile is null then return null; end if;
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

-- Produkt zum Flenski-Plan (wird beim ersten Mal automatisch angelegt, "einzurichten")
create or replace function public._product_for_plan(p_tenant uuid, p_plan jsonb) returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_plan uuid := nullif(p_plan ->> 'id', '')::uuid;
  v_id uuid;
begin
  if v_plan is null then return null; end if;
  select id into v_id from public.products where tenant_id = p_tenant and flenski_plan_id = v_plan;
  if v_id is null then
    insert into public.products (tenant_id, name, type, flenski_plan_id, needs_setup)
    values (p_tenant, coalesce(nullif(p_plan ->> 'name', ''), 'Plan aus der App'), 'period', v_plan, true)
    returning id into v_id;
  end if;
  return v_id;
end $$;

-- Karte für Person + Produkt aus der App: "Plan zugewiesen" und "Bestellung abgeschlossen" kommen oft beide.
-- Gleiche Person + gleicher Plan innerhalb von 10 Minuten = ein Kauf (04, Mapping).
create or replace function public._app_entitlement(p_customer uuid, p_product uuid, p_at timestamptz, p_source public.entitlement_source,
                                        p_price_cents int, p_ref text) returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select id into v_id from public.entitlements
  where customer_id = p_customer and product_id = p_product and source in ('flenski_plan', 'flenski_order')
    and starts_at between p_at - interval '10 minutes' and p_at + interval '10 minutes'
  order by starts_at limit 1;
  if v_id is null then
    v_id := public.sell(p_customer, p_product, 'app', p_price_cents, p_at, p_source, p_ref);
  else
    update public.entitlements
    set price_cents = coalesce(p_price_cents, price_cents), external_ref = coalesce(p_ref, external_ref), paid_via = 'app'
    where id = v_id;
  end if;
  return v_id;
end $$;

-- Stunde zum Flenski-Event (je Termin)
create or replace function public._session_for_event(p_tenant uuid, p_event jsonb, p_category jsonb) returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_event uuid := nullif(p_event ->> 'id', '')::uuid;
  v_start timestamptz := public._ts(p_event ->> 'startAt');
  v_id uuid;
begin
  if v_event is null or v_start is null then return null; end if;
  select id into v_id from public.sessions where tenant_id = p_tenant and flenski_event_id = v_event and starts_at = v_start;
  if v_id is null then
    insert into public.sessions (tenant_id, title, starts_at, ends_at, category, flenski_event_id)
    values (p_tenant, coalesce(nullif(p_event ->> 'title', ''), 'Termin aus der App'), v_start,
            case when public._ts(p_event ->> 'endAt') > v_start then public._ts(p_event ->> 'endAt') end,
            nullif(p_category ->> 'name', ''), v_event)
    returning id into v_id;
  end if;
  return v_id;
end $$;

create or replace function public._activity(p_tenant uuid, p_customer uuid, p_profile uuid, p_type public.activity_type,
                                 p_title text, p_at timestamptz, p_event uuid, p_key text) returns void
language plpgsql
set search_path = ''
as $$
begin
  -- ohne Person (Team/Admin) keine Aktivität speichern
  if p_customer is null then return; end if;
  insert into public.activity_events (tenant_id, customer_id, flenski_profile_id, type, title, occurred_at, webhook_event_id, dedupe_key)
  values (p_tenant, p_customer, p_profile, p_type, nullif(p_title, ''), p_at, p_event, p_key)
  on conflict (tenant_id, dedupe_key) do nothing;
  if p_customer is not null then
    update public.customers set last_app_activity_at = greatest(coalesce(last_app_activity_at, p_at), p_at) where id = p_customer;
  end if;
end $$;

create or replace function public._notice(p_tenant uuid, p_customer uuid, p_kind text, p_detail jsonb, p_event uuid) returns void
language sql
set search_path = ''
as $$
  insert into public.customer_notices (tenant_id, customer_id, kind, detail, webhook_event_id)
  values (p_tenant, p_customer, p_kind, coalesce(p_detail, '{}'), p_event)
$$;

-- ===== Verarbeitung einer Nachricht =====
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
        -- Entscheidung 0005: Teilnahme laut Flenski = Besuch, bucht von der passenden Karte ab
        v_sess := public._session_for_event(w.tenant_id, p -> 'event', p -> 'category');
        if v_sess is not null and v_cust is not null then
          perform public.checkin(v_sess, v_cust);
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

-- Alles Offene verarbeiten (Wiederholung, Nachverarbeitung des Mitschnitts), in Eingangsreihenfolge
create or replace function public.process_pending_webhooks(p_tenant uuid default null) returns int
language plpgsql security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_anzahl int := 0;
begin
  if not (public.is_system() or public.is_platform_admin()) then
    raise exception 'Nur für den Webhook-Empfänger.' using errcode = '42501';
  end if;
  for v_id in
    select id from public.webhook_events
    where processed_at is null and signature_valid is true and (p_tenant is null or tenant_id = p_tenant)
    order by received_at
  loop
    if public.process_webhook_event(v_id) = 'ok' then v_anzahl := v_anzahl + 1; end if;
  end loop;
  return v_anzahl;
end $$;

-- Produkt aus der App einmalig einrichten (Einheiten, Gültigkeit, Preis, Kategorie). Bestehende Karten
-- werden nachgezogen: Kauf-Buchung, Ablaufdatum, und bisherige Teilnahmen werden nachträglich abgebucht.
create or replace function public.setup_product(p_product uuid, p_type public.product_type, p_credits int, p_validity_days int,
                                     p_price_cents int, p_category text) returns int
language plpgsql security definer
set search_path = ''
as $$
declare
  v_p public.products;
  v_e record;
  v_a record;
  v_anzahl int := 0;
begin
  select * into v_p from public.products where id = p_product;
  if not found then raise exception 'Produkt nicht gefunden.' using errcode = 'P0002'; end if;
  if not public.is_owner(v_p.tenant_id) then
    raise exception 'Produkte richtet nur die Inhaberin ein.' using errcode = '42501';
  end if;
  if not v_p.needs_setup then
    raise exception 'Dieses Produkt ist schon eingerichtet.' using errcode = 'P0001';
  end if;

  update public.products
  set type = p_type, credits = case p_type when 'credits' then p_credits when 'single' then 1 end,
      validity_days = p_validity_days, price_cents = coalesce(p_price_cents, price_cents),
      category = nullif(btrim(p_category), ''), needs_setup = false
  where id = p_product;

  for v_e in select * from public.entitlements where product_id = p_product order by starts_at loop
    update public.entitlements
    set expires_at = case when p_validity_days is not null then v_e.starts_at + make_interval(days => p_validity_days) end,
        price_cents = coalesce(v_e.price_cents, p_price_cents)
    where id = v_e.id;
    if p_type in ('credits', 'single') then
      insert into public.ledger_entries (tenant_id, entitlement_id, customer_id, delta, reason, created_by, comment)
      values (v_e.tenant_id, v_e.id, v_e.customer_id, case p_type when 'credits' then p_credits else 1 end, 'purchase',
              auth.uid(), 'Kauf aus der App, Produkt eingerichtet');
      -- bisherige Teilnahmen mit dieser Karte jetzt abbuchen
      for v_a in select a.id from public.attendances a join public.sessions s on s.id = a.session_id
                 where a.entitlement_id = v_e.id and a.status in ('present', 'cancelled_late', 'no_show') order by s.starts_at loop
        update public.attendances set entitlement_id = null where id = v_a.id;
        perform public._abbuchen(v_a.id);
      end loop;
    end if;
    perform public.refresh_entitlement_status(v_e.id);
    v_anzahl := v_anzahl + 1;
  end loop;
  return v_anzahl;
end $$;

revoke execute on function public._ts, public._upsert_member, public._product_for_plan, public._app_entitlement,
  public._session_for_event, public._activity, public._notice from public, anon, authenticated;
revoke execute on function public.process_webhook_event, public.process_pending_webhooks, public.setup_product from public, anon;
grant execute on function public.process_webhook_event, public.process_pending_webhooks, public.setup_product to authenticated, service_role;
