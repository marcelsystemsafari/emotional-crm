-- Abgleich mit Flenski nur bei Bedarf (Marcel, 23.10.2026): Flenski wird nicht mehr alle 5 Minuten gefragt.
-- pg_cron prüft weiterhin alle 5 Minuten, aber nur in der Datenbank (kostet nichts) und ruft die Edge Function
-- nur auf, wenn eine Mandantin fällig ist:
--   - ein Kurs beginnt in den nächsten 20 Minuten oder hat vor höchstens 10 Minuten begonnen und ist noch offen, oder
--   - der letzte Abgleich ist über eine Stunde her (neue Termine, Anmeldungen zwischendurch).
-- Ergebnis: etwa 24 Abfragen am Tag plus etwa 7 rund um jeden Kurs, statt 288 am Tag.

alter table public.tenant_secrets add column if not exists last_sync_at timestamptz;

create or replace function public.flenski_faellige_mandanten() returns setof uuid
language sql stable security definer
set search_path = ''
as $$
  select t.id
  from public.tenants t join public.tenant_secrets s on s.tenant_id = t.id
  where t.status in ('trial', 'active') and nullif(t.settings ->> 'flenski_app_id', '') is not null
    and (s.last_sync_at is null
         or s.last_sync_at < now() - interval '60 minutes'
         or exists (select 1 from public.sessions x
                    where x.tenant_id = t.id and x.flenski_event_id is not null and x.abgeglichen_at is null
                      and x.starts_at between now() - interval '10 minutes' and now() + interval '20 minutes')
         -- falls ein Abschluss hängen geblieben ist (z. B. Flenski kurz nicht erreichbar): bis 2 Stunden nachholen
         or exists (select 1 from public.sessions x
                    where x.tenant_id = t.id and x.flenski_event_id is not null and x.abgeglichen_at is null
                      and x.flenski_seen_at >= x.starts_at - interval '15 minutes'
                      and x.starts_at between now() - interval '2 hours' and now() - interval '5 minutes'))
$$;
revoke execute on function public.flenski_faellige_mandanten from public, anon, authenticated;
grant execute on function public.flenski_faellige_mandanten to service_role;

-- Zeitpunkt des Abgleichs merken
do $$
declare
  v_src text;
begin
  -- sync_flenski_events bekommt am Ende "letzter Abgleich = jetzt"; Rest unverändert
  select pg_get_functiondef('public.sync_flenski_events(uuid, jsonb)'::regprocedure) into v_src;
  if position('last_sync_at' in v_src) = 0 then
    v_src := replace(v_src,
      $a$  return jsonb_build_object('termine', v_termine, 'abgeschlossen', v_abgeschlossen);$a$,
      $b$  update public.tenant_secrets set last_sync_at = now() where tenant_id = p_tenant;
  return jsonb_build_object('termine', v_termine, 'abgeschlossen', v_abgeschlossen);$b$);
    if position('last_sync_at' in v_src) = 0 then raise exception 'sync_flenski_events: Ende nicht gefunden'; end if;
    execute v_src;
  end if;
end $$;

select cron.unschedule('ecrm-flenski-abgleich') where exists (select 1 from cron.job where jobname = 'ecrm-flenski-abgleich');
select cron.schedule('ecrm-flenski-abgleich', '*/5 * * * *', $job$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'ecrm_project_url') || '/functions/v1/flenski-sync',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-sync-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'ecrm_sync_secret')),
    body := '{}'::jsonb)
  where exists (select 1 from vault.decrypted_secrets where name = 'ecrm_sync_secret')
    and exists (select 1 from public.flenski_faellige_mandanten())
$job$);
