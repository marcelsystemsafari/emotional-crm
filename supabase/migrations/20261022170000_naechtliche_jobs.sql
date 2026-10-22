-- Phase 1, Schritt 5: nächtliche Aufgaben per pg_cron (läuft in Supabase, kein eigener Server).
--   02:15 Uhr (UTC) Karten-Verfall: Restguthaben abgelaufener Karten ausbuchen
--   02:30 Uhr (UTC) Aktivitätsdaten älter als 12 Monate löschen (Regel 10, 08-aktivitaet.md)

create extension if not exists pg_cron;

create function public.cleanup_activity_events() returns int
language plpgsql security definer
set search_path = ''
as $$
declare
  v_anzahl int;
begin
  if not (public.is_system() or public.is_platform_admin()) then
    raise exception 'Nur für den nächtlichen Ablauf.' using errcode = '42501';
  end if;
  delete from public.activity_events where occurred_at < now() - interval '12 months';
  get diagnostics v_anzahl = row_count;
  return v_anzahl;
end $$;
revoke execute on function public.cleanup_activity_events from public, anon;

select cron.schedule('ecrm-kartenverfall', '15 2 * * *', 'select public.expire_entitlements()');
select cron.schedule('ecrm-aktivitaet-12-monate', '30 2 * * *', 'select public.cleanup_activity_events()');
