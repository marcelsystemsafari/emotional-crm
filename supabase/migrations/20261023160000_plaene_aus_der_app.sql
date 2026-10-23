-- Neue Pläne aus Flenski automatisch unter "Angebote" zeigen (Marcel, 23.10.2026).
-- Flenski meldet das Anlegen eines Plans nicht, und der API-Schlüssel darf Pläne nicht lesen. Deshalb holt
-- flenski-sync die Planliste über das Make-Szenario (Aktion "plans"): einmal am Tag automatisch und sofort,
-- wenn die Lehrerin unter "Angebote" auf "Neue Pläne aus der App holen" tippt (request_plan_sync).
-- Ohne Make erscheint ein neuer Plan wie bisher beim ersten Kauf bzw. der ersten Zuweisung.

alter table public.tenant_secrets add column if not exists plans_synced_at timestamptz;
alter table public.tenant_secrets add column if not exists plans_requested_at timestamptz;

-- Lehrerin fordert den Abruf an (Knopf unter "Angebote")
create or replace function public.request_plan_sync(p_tenant uuid) returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if not public.can_write(p_tenant) then
    raise exception 'Keine Berechtigung für diese Mandantin.' using errcode = '42501';
  end if;
  update public.tenant_secrets set plans_requested_at = now() where tenant_id = p_tenant;
end $$;

-- Muss die Planliste geholt werden? (für flenski-sync)
create or replace function public.flenski_plaene_faellig(p_tenant uuid) returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (select 1 from public.tenant_secrets s
                 where s.tenant_id = p_tenant and nullif(s.make_webhook_url, '') is not null
                   and (s.plans_synced_at is null or s.plans_synced_at < now() - interval '1 day'
                        or s.plans_requested_at > s.plans_synced_at))
$$;

-- Planliste übernehmen: neue Pläne als "noch nicht verbunden", Namen aktuell halten
create or replace function public.sync_flenski_plans(p_tenant uuid, p_plans jsonb) returns int
language plpgsql security definer
set search_path = ''
as $$
declare
  v_p jsonb;
  v_neu int := 0;
begin
  if not public.is_system() then
    raise exception 'Nur für den automatischen Abgleich.' using errcode = '42501';
  end if;
  for v_p in select * from jsonb_array_elements(coalesce(p_plans, '[]')) loop
    if nullif(v_p ->> 'id', '') is null then continue; end if;
    if not exists (select 1 from public.products where tenant_id = p_tenant and flenski_plan_id = (v_p ->> 'id')::uuid) then
      v_neu := v_neu + 1;
    end if;
    perform public._product_for_plan(p_tenant, v_p);
    update public.products set name = v_p ->> 'name'
    where tenant_id = p_tenant and flenski_plan_id = (v_p ->> 'id')::uuid
      and nullif(v_p ->> 'name', '') is not null and name is distinct from v_p ->> 'name';
  end loop;
  update public.tenant_secrets set plans_synced_at = now() where tenant_id = p_tenant;
  return v_neu;
end $$;

-- Fällig für den 5-Minuten-Takt, sobald Pläne angefordert sind
do $$
declare
  v_src text;
begin
  select pg_get_functiondef('public.flenski_faellige_mandanten()'::regprocedure) into v_src;
  if position('flenski_plaene_faellig' in v_src) = 0 then
    v_src := replace(v_src, $a$    and (s.last_sync_at is null$a$, $b$    and (public.flenski_plaene_faellig(t.id)
         or s.last_sync_at is null$b$);
    if position('flenski_plaene_faellig' in v_src) = 0 then raise exception 'flenski_faellige_mandanten: Anker fehlt'; end if;
    execute v_src;
  end if;
end $$;

revoke execute on function public.flenski_plaene_faellig, public.sync_flenski_plans from public, anon, authenticated;
grant execute on function public.flenski_plaene_faellig, public.sync_flenski_plans to service_role;
revoke execute on function public.request_plan_sync from public, anon;
grant execute on function public.request_plan_sync to authenticated, service_role;
