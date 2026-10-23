-- Make als Brücke für das, was der Flenski-API-Schlüssel nicht darf (Marcel, 23.10.2026):
-- Plan entziehen/zuweisen und die vollständige Teilnehmerliste. Make-Szenario "ECRM: Flenski-Aktionen" (Webhook),
-- angestoßen nur bei Bedarf von der Edge Function flenski-sync (Supabase-Secret MAKE_WEBHOOK_URL).
-- Teilnehmerliste: nur wenn Flenski die Namensliste eines fälligen Termins gekürzt hat (sonst 0 Make-Operationen).

-- Termine, die jetzt abgeschlossen werden und deren Namensliste unvollständig ist
create or replace function public.flenski_teilnehmer_benoetigt(p_tenant uuid)
returns table (session_id uuid, event_id uuid)
language plpgsql security definer
set search_path = ''
as $$
begin
  if not public.is_system() then
    raise exception 'Nur für den automatischen Abgleich.' using errcode = '42501';
  end if;
  return query
  select s.id, s.flenski_event_id
  from public.sessions s
  where s.tenant_id = p_tenant and s.flenski_event_id is not null and s.abgeglichen_at is null
    and s.starts_at <= now() - interval '5 minutes'
    and s.flenski_seen_at >= s.starts_at - interval '15 minutes'
    and coalesce(s.flenski_count, 0) > coalesce(array_length(s.flenski_profiles, 1), 0);
end $$;

-- Vollständige Liste aus Make übernehmen (danach gleicht sync_flenski_events exakt ab)
create or replace function public.flenski_teilnehmer_setzen(p_session uuid, p_profiles uuid[]) returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if not public.is_system() then
    raise exception 'Nur für den automatischen Abgleich.' using errcode = '42501';
  end if;
  update public.sessions
  set flenski_profiles = coalesce(p_profiles, '{}'), flenski_count = coalesce(array_length(p_profiles, 1), 0)
  where id = p_session and abgeglichen_at is null;
  -- Wer auf der vollständigen Liste steht, dem CRM aber fehlt (in der gekürzten Liste nicht sichtbar): nachtragen
  insert into public.attendances (tenant_id, session_id, customer_id)
  select s.tenant_id, s.id, c.id
  from public.sessions s join public.customers c on c.tenant_id = s.tenant_id
  where s.id = p_session and s.abgeglichen_at is null and c.anonymized_at is null
    and c.flenski_profile_id = any (coalesce(p_profiles, '{}'))
  on conflict (session_id, customer_id) do update set status = 'registered', entitlement_id = null
    where public.attendances.status = 'cancelled_in_time';
end $$;

revoke execute on function public.flenski_teilnehmer_benoetigt, public.flenski_teilnehmer_setzen from public, anon, authenticated;
grant execute on function public.flenski_teilnehmer_benoetigt, public.flenski_teilnehmer_setzen to service_role;

-- Flenski-Projekt von Lana (für das Make-Modul "Revoke a Plan for a Profile")
update public.tenants set settings = settings || '{"flenski_project_id": "ebe2c601-c1dc-45dc-ab3e-5bd085487bcc"}'
where slug = 'yoga-by-lana' and settings ->> 'flenski_project_id' is null;
