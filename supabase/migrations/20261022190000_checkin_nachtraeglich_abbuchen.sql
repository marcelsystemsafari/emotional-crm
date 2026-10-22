-- Korrektur (gefunden beim Oberflächentest 22.10.2026): War eine Kundin "ohne Karte" eingecheckt und bekommt
-- danach eine Karte verkauft, soll ein erneuter Check-in den Besuch nachträglich von der neuen Karte abbuchen.
-- Vorher tat checkin() bei Status "anwesend" gar nichts mehr.
create or replace function public.checkin(p_session uuid, p_customer uuid) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_att public.attendances := public._anwesenheit(p_session, p_customer);
begin
  if v_att.status <> 'present' then
    update public.attendances
    set status = 'present', checked_in_by = auth.uid(), checked_in_at = now()
    where id = v_att.id;
    perform public._abbuchen(v_att.id);
  elsif v_att.entitlement_id is null then
    -- schon da, aber bisher ohne passende Karte: jetzt nachbuchen (doppelt abbuchen verhindert _abbuchen selbst)
    perform public._abbuchen(v_att.id);
  end if;
  return public._ergebnis(v_att.id);
end $$;
