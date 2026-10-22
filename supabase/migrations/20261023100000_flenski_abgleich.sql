-- Automatischer Teilnehmer-Abgleich mit Flenski (Entscheidung 0006, 22.10.2026).
-- Alle 5 Minuten holt die Edge Function flenski-sync die Termine der App (API-Schlüssel je Mandantin)
-- und ruft sync_flenski_events auf:
--   1. Termine anlegen/aktualisieren (neue Termine kommen so automatisch ins CRM).
--   2. Bis 5 Minuten nach Beginn: Stand der Anmeldungen merken und die Liste im CRM angleichen.
--   3. Ab 5 Minuten nach Beginn: einmal abschließen. Wer auf der Flenski-Liste steht, war da (Besuch + Abzug).
--      Wer nicht mehr drauf steht, hat sich abgemeldet (kein Abzug).
-- Flenski zeigt pro Termin die Anzahl (attendedCount) und die Namen der zuletzt Angemeldeten (lastAttended).
-- Ist die Namensliste kürzer als die Anzahl, bucht das CRM nur ab, was eindeutig ist, und meldet den Rest
-- als "Teilnahme unklar" an die Lehrerin (kommt nur bei großen Kursen mit Abmeldungen vor).

create extension if not exists pg_net;

-- ===== Flenski-Schlüssel je Mandantin (nur Server, nie Browser) =====
create table if not exists public.tenant_secrets (
  tenant_id       uuid primary key references public.tenants (id),
  flenski_api_key text not null,
  updated_at      timestamptz not null default now()
);
alter table public.tenant_secrets enable row level security;
-- keine Policies: nur Service-Role (Edge Function) und Datenbank selbst lesen
revoke all on public.tenant_secrets from anon, authenticated;

-- ===== Abgleich-Stand je Termin =====
alter table public.sessions add column if not exists flenski_count int;
alter table public.sessions add column if not exists flenski_profiles uuid[];
alter table public.sessions add column if not exists flenski_seen_at timestamptz;
alter table public.sessions add column if not exists abgeglichen_at timestamptz;
alter table public.sessions add column if not exists abgleich_info jsonb;

-- Läuft für diese Mandantin der automatische Abgleich?
create or replace function public._flenski_sync_aktiv(p_tenant uuid) returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (select 1 from public.tenants t join public.tenant_secrets s on s.tenant_id = t.id
                 where t.id = p_tenant and nullif(t.settings ->> 'flenski_app_id', '') is not null)
$$;

-- Einen Termin abschließen (einmalig, ab 5 Minuten nach Beginn)
create or replace function public._flenski_abschliessen(p_session uuid) returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  s public.sessions;
  v_a record;
  v_vollstaendig boolean;
  v_da int := 0; v_ab int := 0; v_unklar int := 0;
begin
  select * into s from public.sessions where id = p_session for update;
  if s.abgeglichen_at is not null then return s.abgleich_info; end if;
  v_vollstaendig := coalesce(array_length(s.flenski_profiles, 1), 0) >= coalesce(s.flenski_count, 0);

  for v_a in
    select a.customer_id, c.flenski_profile_id, c.first_name
    from public.attendances a join public.customers c on c.id = a.customer_id
    where a.session_id = s.id and a.status = 'registered'
  loop
    if v_a.flenski_profile_id = any (coalesce(s.flenski_profiles, '{}')) then
      perform public.checkin(s.id, v_a.customer_id);
      v_da := v_da + 1;
    elsif v_vollstaendig then
      update public.attendances set status = 'cancelled_in_time', entitlement_id = null
      where session_id = s.id and customer_id = v_a.customer_id;
      v_ab := v_ab + 1;
    else
      perform public._notice(s.tenant_id, v_a.customer_id, 'teilnahme_unklar',
        jsonb_build_object('session_id', s.id, 'titel', s.title, 'beginn', s.starts_at), null);
      v_unklar := v_unklar + 1;
    end if;
  end loop;

  update public.sessions
  set abgeglichen_at = now(),
      abgleich_info = jsonb_build_object('waren_da', v_da, 'abgemeldet', v_ab, 'unklar', v_unklar,
                                         'anzahl_app', s.flenski_count, 'stand', s.flenski_seen_at)
  where id = s.id
  returning abgleich_info into s.abgleich_info;
  return s.abgleich_info;
end $$;

-- Hauptfunktion: Termine aus Flenski übernehmen, Anmeldungen angleichen, fällige Termine abschließen
create or replace function public.sync_flenski_events(p_tenant uuid, p_events jsonb) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_e jsonb;
  v_sess uuid;
  s public.sessions;
  v_ids uuid[];
  v_count int;
  v_cust uuid;
  v_p uuid;
  v_termine int := 0; v_abgeschlossen int := 0;
begin
  if not public.is_system() then
    raise exception 'Nur für den automatischen Abgleich.' using errcode = '42501';
  end if;

  for v_e in select * from jsonb_array_elements(coalesce(p_events, '[]')) loop
    v_sess := public._sessions_for_series(p_tenant, v_e);
    if v_sess is null then continue; end if;
    v_termine := v_termine + 1;
    update public.sessions
    set title = coalesce(nullif(coalesce(v_e ->> 'title', v_e ->> 'name'), ''), title),
        capacity = coalesce(nullif((v_e ->> 'participantsNumberLimit')::int, 0), capacity)
    where id = v_sess
    returning * into s;

    -- nach 5 Minuten ab Beginn wird der Stand nicht mehr verändert
    if s.abgeglichen_at is not null or now() > s.starts_at + interval '5 minutes' then continue; end if;

    select coalesce(array_agg(distinct (x ->> 'id')::uuid) filter (where x ->> 'id' is not null), '{}')
    into v_ids from jsonb_array_elements(coalesce(v_e -> 'lastAttended', '[]')) x;
    v_count := coalesce((v_e ->> 'attendedCount')::int, array_length(v_ids, 1), 0);

    update public.sessions set flenski_count = v_count, flenski_profiles = v_ids, flenski_seen_at = now() where id = s.id;

    -- Wer in Flenski angemeldet ist, steht im CRM als angemeldet (auch nach einer Absage im CRM).
    -- Nur Absagen ohne Abzug werden zurückgesetzt, damit keine Buchung verwaist.
    foreach v_p in array v_ids loop
      select id into v_cust from public.customers
      where tenant_id = p_tenant and flenski_profile_id = v_p and anonymized_at is null;
      if v_cust is null then continue; end if;   -- Team, Lehrerin mit Ausschluss-Tag, unbekannt
      insert into public.attendances (tenant_id, session_id, customer_id) values (p_tenant, s.id, v_cust)
      on conflict (session_id, customer_id) do update set status = 'registered', entitlement_id = null
        where public.attendances.status = 'cancelled_in_time';
    end loop;

    -- Vollständige Liste: wer im CRM angemeldet ist, aber nicht mehr in Flenski, hat sich abgemeldet
    if coalesce(array_length(v_ids, 1), 0) >= v_count then
      update public.attendances a set status = 'cancelled_in_time', entitlement_id = null
      from public.customers c
      where a.session_id = s.id and a.status = 'registered' and c.id = a.customer_id
        and (c.flenski_profile_id is null or not (c.flenski_profile_id = any (v_ids)));
    end if;
  end loop;

  -- Fällige Termine abschließen: Beginn + 5 Minuten vorbei, frischer Stand von kurz vor/nach Beginn
  for v_sess in
    select id from public.sessions
    where tenant_id = p_tenant and flenski_event_id is not null and abgeglichen_at is null
      and starts_at <= now() - interval '5 minutes'
      and flenski_seen_at >= starts_at - interval '15 minutes'
    order by starts_at
  loop
    perform public._flenski_abschliessen(v_sess);
    v_abgeschlossen := v_abgeschlossen + 1;
  end loop;

  return jsonb_build_object('termine', v_termine, 'abgeschlossen', v_abgeschlossen);
end $$;

-- Alter Weg (Anmeldung = da, ohne Prüfung) nur noch für Mandantinnen ohne Abgleich.
-- Bei Mandantinnen mit Abgleich: Termine, für die 24 Stunden lang kein Stand kam, werden markiert (kein Abzug).
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
      and t.status in ('trial', 'active') and not public._flenski_sync_aktiv(t.id)
    order by s.starts_at
  loop
    perform public.checkin(v_a.session_id, v_a.customer_id);
    v_anzahl := v_anzahl + 1;
  end loop;

  update public.sessions s set abgleich_info = jsonb_build_object('fehlt', true)
  where s.flenski_event_id is not null and s.abgeglichen_at is null and s.abgleich_info is null
    and s.starts_at < now() - interval '24 hours' and public._flenski_sync_aktiv(s.tenant_id);
  return v_anzahl;
end $$;

-- Ausnahmen durch die Lehrerin (Kurs-Ansicht): War da / War nicht da / Kulanz
create or replace function public.set_attendance(p_session uuid, p_customer uuid, p_art text) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_att public.attendances := public._anwesenheit(p_session, p_customer);
begin
  perform public._require_write(v_att.tenant_id);
  if p_art = 'war_da' then
    return public.checkin(p_session, p_customer);
  elsif p_art in ('nicht_da', 'kulanz') then
    perform public._rueckbuchen(v_att.id, case p_art when 'kulanz' then 'Kulanz' else 'War nicht da' end);
    update public.attendances
    set status = case p_art when 'kulanz' then 'no_show' else 'cancelled_in_time' end::public.attendance_status,
        entitlement_id = null
    where id = v_att.id;
    update public.customer_notices set resolved_at = now(), resolved_by = auth.uid()
    where customer_id = p_customer and kind = 'teilnahme_unklar' and resolved_at is null
      and detail ->> 'session_id' = p_session::text;
    return public._ergebnis(v_att.id);
  end if;
  raise exception 'Unbekannte Aktion.' using errcode = '22023';
end $$;

-- "War da" erledigt einen offenen Unklar-Hinweis ebenfalls
create or replace function public._unklar_erledigen() returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  if new.status <> 'registered' then
    update public.customer_notices set resolved_at = now()
    where customer_id = new.customer_id and kind = 'teilnahme_unklar' and resolved_at is null
      and detail ->> 'session_id' = new.session_id::text;
  end if;
  return new;
end $$;
drop trigger if exists attendances_unklar_erledigen on public.attendances;
create trigger attendances_unklar_erledigen after update of status on public.attendances
  for each row execute function public._unklar_erledigen();

revoke execute on function public._flenski_sync_aktiv, public._flenski_abschliessen, public._unklar_erledigen
  from public, anon, authenticated;
revoke execute on function public.sync_flenski_events from public, anon, authenticated;
grant execute on function public.sync_flenski_events to service_role;
revoke execute on function public.set_attendance from public, anon;
grant execute on function public.set_attendance to authenticated, service_role;

-- Zeitplan: alle 5 Minuten die Edge Function anstoßen. Adresse und Geheimnis liegen im Vault
-- (eingerichtet mit scripts/setup-flenski-sync.mjs, nie in Migrationen).
select cron.unschedule('ecrm-flenski-abgleich') where exists (select 1 from cron.job where jobname = 'ecrm-flenski-abgleich');
select cron.schedule('ecrm-flenski-abgleich', '*/5 * * * *', $job$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'ecrm_project_url') || '/functions/v1/flenski-sync',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-sync-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'ecrm_sync_secret')),
    body := '{}'::jsonb)
  where exists (select 1 from vault.decrypted_secrets where name = 'ecrm_sync_secret')
$job$);
