-- Automatischer Plan-Entzug in Flenski (Marcel, 23.10.2026).
-- Ist eine Karte mit Flenski-Plan leer oder abgelaufen (Hinweis "plan_entziehen", Migration 260000), entzieht
-- die Edge Function flenski-sync beim nächsten Abgleich den Plan in der App:
--   POST https://app.flenski.io/api/v1/apps/{appId}/profiles/plans/revoke  (Pfad ermittelt 23.10.2026)
-- Nur wenn die Mandantin es eingeschaltet hat: tenants.settings.plan_entzug_automatisch = true.
-- Nicht entzogen wird, wenn die Person inzwischen eine neue, aktive Karte desselben Angebots hat.
-- Klappt es dreimal nicht, bleibt der Hinweis für die Lehrerin stehen (sie entzieht dann von Hand).

alter table public.entitlements add column if not exists flenski_plan_revoked_at timestamptz;

-- Offene Entzüge einer Mandantin (für die Edge Function)
create or replace function public.flenski_offene_entzuege(p_tenant uuid)
returns table (notice_id uuid, email text, plan_id uuid, produkt text)
language plpgsql security definer
set search_path = ''
as $$
begin
  if not public.is_system() then
    raise exception 'Nur für den automatischen Abgleich.' using errcode = '42501';
  end if;

  -- Hinweise, die sich erledigt haben (neue aktive Karte desselben Angebots), still schließen
  update public.customer_notices n set resolved_at = now(), detail = n.detail || '{"erledigt": "neue Karte"}'
  from public.entitlements e
  where n.tenant_id = p_tenant and n.kind = 'plan_entziehen' and n.resolved_at is null
    and e.id = (n.detail ->> 'entitlement_id')::uuid
    and exists (select 1 from public.entitlements e2
                where e2.customer_id = e.customer_id and e2.product_id = e.product_id and e2.status = 'active');

  return query
  select n.id, c.email, p.flenski_plan_id, p.name
  from public.customer_notices n
  join public.tenants t on t.id = n.tenant_id
  join public.entitlements e on e.id = (n.detail ->> 'entitlement_id')::uuid
  join public.products p on p.id = e.product_id
  join public.customers c on c.id = e.customer_id
  where n.tenant_id = p_tenant and n.kind = 'plan_entziehen' and n.resolved_at is null
    and coalesce((t.settings ->> 'plan_entzug_automatisch')::boolean, false)
    and e.status in ('used_up', 'expired') and e.flenski_plan_revoked_at is null
    and p.flenski_plan_id is not null and nullif(c.email, '') is not null and c.anonymized_at is null
    and coalesce((n.detail ->> 'versuche')::int, 0) < 3;
end $$;

-- Ergebnis eines Entzugs festhalten
create or replace function public.flenski_entzug_ergebnis(p_notice uuid, p_ok boolean, p_info text) returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if not public.is_system() then
    raise exception 'Nur für den automatischen Abgleich.' using errcode = '42501';
  end if;
  if p_ok then
    update public.entitlements set flenski_plan_revoked_at = now()
    where id = (select (detail ->> 'entitlement_id')::uuid from public.customer_notices where id = p_notice);
    update public.customer_notices
    set resolved_at = now(), detail = detail || jsonb_build_object('automatisch', true)
    where id = p_notice;
  else
    update public.customer_notices
    set detail = detail || jsonb_build_object('versuche', coalesce((detail ->> 'versuche')::int, 0) + 1, 'fehler', left(p_info, 300))
    where id = p_notice;
  end if;
end $$;

-- Rückmeldung "Plan entzogen" aus Flenski:
--   - nach unserem eigenen Entzug: still als erledigt ablegen (kein doppelter Hinweis),
--   - hat die Lehrerin selbst entzogen: ihren offenen Hinweis "Plan entziehen" gleich mit erledigen.
create or replace function public._plan_entzogen_abgleichen() returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  if new.kind <> 'plan_entzogen' or new.customer_id is null then return new; end if;
  if exists (select 1 from public.entitlements e join public.products p on p.id = e.product_id
             where e.customer_id = new.customer_id and p.name = new.detail ->> 'plan'
               and e.flenski_plan_revoked_at > now() - interval '1 day') then
    new.resolved_at := now();
    new.detail := new.detail || '{"automatisch": true}';
  end if;
  update public.customer_notices set resolved_at = now(), detail = detail || '{"erledigt": "in der App entzogen"}'
  where customer_id = new.customer_id and kind = 'plan_entziehen' and resolved_at is null
    and detail ->> 'produkt' = new.detail ->> 'plan';
  return new;
end $$;
drop trigger if exists notices_plan_entzogen on public.customer_notices;
create trigger notices_plan_entzogen before insert on public.customer_notices
  for each row execute function public._plan_entzogen_abgleichen();

-- Neue Karte desselben Angebots: offener Hinweis "Plan entziehen" ist hinfällig
create or replace function public._neue_karte_hinweis_erledigen() returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  update public.customer_notices n set resolved_at = now(), detail = n.detail || '{"erledigt": "neue Karte"}'
  from public.entitlements e
  where n.customer_id = new.customer_id and n.kind = 'plan_entziehen' and n.resolved_at is null
    and e.id = (n.detail ->> 'entitlement_id')::uuid and e.product_id = new.product_id and e.id <> new.id;
  return new;
end $$;
drop trigger if exists entitlements_neue_karte on public.entitlements;
create trigger entitlements_neue_karte after insert on public.entitlements
  for each row execute function public._neue_karte_hinweis_erledigen();

-- Offene Entzüge machen die Mandantin für den nächsten 5-Minuten-Takt fällig
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
         or exists (select 1 from public.sessions x
                    where x.tenant_id = t.id and x.flenski_event_id is not null and x.abgeglichen_at is null
                      and x.flenski_seen_at >= x.starts_at - interval '15 minutes'
                      and x.starts_at between now() - interval '2 hours' and now() - interval '5 minutes')
         or (coalesce((t.settings ->> 'plan_entzug_automatisch')::boolean, false)
             and s.last_sync_at < now() - interval '10 minutes'
             and exists (select 1 from public.customer_notices n
                         where n.tenant_id = t.id and n.kind = 'plan_entziehen' and n.resolved_at is null
                           and coalesce((n.detail ->> 'versuche')::int, 0) < 3)))
$$;

revoke execute on function public._plan_entzogen_abgleichen, public._neue_karte_hinweis_erledigen from public, anon, authenticated;
revoke execute on function public.flenski_offene_entzuege, public.flenski_entzug_ergebnis from public, anon, authenticated;
grant execute on function public.flenski_offene_entzuege, public.flenski_entzug_ergebnis to service_role;
