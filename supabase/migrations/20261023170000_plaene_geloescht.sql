-- In Flenski gelöschte Pläne unter "Angebote" ausblenden (Marcel, 23.10.2026: keine "toten" Angebote einrichten).
-- Das Produkt bleibt erhalten (gekaufte Karten und Buchungen hängen daran), es bekommt nur flenski_removed_at.
-- Taucht der Plan wieder auf, wird die Markierung zurückgenommen.
-- sync_flenski_plans liefert jetzt {neu, entfernt}. Eine leere Liste entfernt nichts (Schutz bei Fehlern).

alter table public.products add column if not exists flenski_removed_at timestamptz;

drop function if exists public.sync_flenski_plans(uuid, jsonb);
create function public.sync_flenski_plans(p_tenant uuid, p_plans jsonb) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_p jsonb;
  v_ids uuid[] := '{}';
  v_neu int := 0;
  v_entfernt int := 0;
begin
  if not public.is_system() then
    raise exception 'Nur für den automatischen Abgleich.' using errcode = '42501';
  end if;
  for v_p in select * from jsonb_array_elements(coalesce(p_plans, '[]')) loop
    if nullif(v_p ->> 'id', '') is null then continue; end if;
    v_ids := v_ids || (v_p ->> 'id')::uuid;
    if not exists (select 1 from public.products where tenant_id = p_tenant and flenski_plan_id = (v_p ->> 'id')::uuid) then
      v_neu := v_neu + 1;
    end if;
    perform public._product_for_plan(p_tenant, v_p);
    update public.products
    set name = coalesce(nullif(v_p ->> 'name', ''), name), flenski_removed_at = null
    where tenant_id = p_tenant and flenski_plan_id = (v_p ->> 'id')::uuid;
  end loop;

  if array_length(v_ids, 1) > 0 then
    update public.products set flenski_removed_at = now()
    where tenant_id = p_tenant and flenski_plan_id is not null and flenski_removed_at is null
      and not (flenski_plan_id = any (v_ids));
    get diagnostics v_entfernt = row_count;
  end if;

  update public.tenant_secrets set plans_synced_at = now() where tenant_id = p_tenant;
  return jsonb_build_object('neu', v_neu, 'entfernt', v_entfernt);
end $$;
revoke execute on function public.sync_flenski_plans from public, anon, authenticated;
grant execute on function public.sync_flenski_plans to service_role;

-- Abgleich direkt aus der Oberfläche (Reiter "Angebote"): darf diese Person, und ist der letzte Abgleich alt genug?
create or replace function public.flenski_plaene_jetzt_erlaubt(p_tenant uuid, p_user uuid) returns boolean
language sql stable security definer
set search_path = ''
as $$
  select (exists (select 1 from public.platform_admins where user_id = p_user)
          or exists (select 1 from public.tenant_members m join public.tenants t on t.id = m.tenant_id
                     where m.tenant_id = p_tenant and m.user_id = p_user and t.status in ('trial', 'active')))
     and exists (select 1 from public.tenant_secrets s
                 where s.tenant_id = p_tenant and nullif(s.make_webhook_url, '') is not null
                   and (s.plans_synced_at is null or s.plans_synced_at < now() - interval '2 minutes'))
$$;
revoke execute on function public.flenski_plaene_jetzt_erlaubt from public, anon, authenticated;
grant execute on function public.flenski_plaene_jetzt_erlaubt to service_role;
