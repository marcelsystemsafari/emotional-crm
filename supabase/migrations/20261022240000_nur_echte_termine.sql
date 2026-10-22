-- Korrektur (Marcel, 22.10.2026): Kurse müssen 1:1 dem entsprechen, was in Flenski existiert.
-- Bisher wurden aus "recurringEventPattern.totalOccurrences" Folgetermine selbst hochgerechnet – Flenski legt sie
-- aber erst später an (upfrontOccurrences = 0). Ab jetzt wird nur der Termin übernommen, den Flenski liefert.
-- Weitere Termine kommen mit dem nächsten Abgleich bzw. per Webhook, sobald es sie in Flenski gibt.

-- Link zum Termin in der App (Flenski liefert ihn als frontendUrl)
alter table public.sessions add column if not exists app_url text;

create or replace function public._sessions_for_series(p_tenant uuid, p_event jsonb) returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if public._ts(p_event ->> 'startsAt') is null then return null; end if;
  v_id := public._session_for_event(p_tenant,
    jsonb_build_object('id', p_event ->> 'id', 'title', coalesce(p_event ->> 'title', p_event ->> 'name'),
      'startAt', p_event ->> 'startsAt', 'endAt', p_event ->> 'endsAt'),
    p_event -> 'category');
  update public.sessions
  set capacity = coalesce(nullif((p_event ->> 'participantsNumberLimit')::int, 0), capacity),
      app_url = coalesce(nullif(p_event ->> 'frontendUrl', ''), app_url)
  where id = v_id;
  return v_id;
end $$;

-- Selbst hochgerechnete Folgetermine entfernen: Termine aus Flenski ohne Anmeldung, deren Event-Termin
-- nicht der von Flenski gelieferte erste Termin ist (je Event der früheste bleibt stehen).
delete from public.sessions s
where s.flenski_event_id is not null
  and not exists (select 1 from public.attendances a where a.session_id = s.id)
  and s.starts_at > (select min(s2.starts_at) from public.sessions s2
                     where s2.tenant_id = s.tenant_id and s2.flenski_event_id = s.flenski_event_id);
