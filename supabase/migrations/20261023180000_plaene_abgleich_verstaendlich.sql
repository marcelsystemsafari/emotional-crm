-- Plan-Abgleich verständlich machen (Marcel, 23.10.2026): Sperre nur noch 20 Sekunden, und die Oberfläche
-- zeigt immer den Stand ("zuletzt abgeglichen um …").

create or replace function public.flenski_plaene_jetzt_erlaubt(p_tenant uuid, p_user uuid) returns boolean
language sql stable security definer
set search_path = ''
as $$
  select (exists (select 1 from public.platform_admins where user_id = p_user)
          or exists (select 1 from public.tenant_members m join public.tenants t on t.id = m.tenant_id
                     where m.tenant_id = p_tenant and m.user_id = p_user and t.status in ('trial', 'active')))
     and exists (select 1 from public.tenant_secrets s
                 where s.tenant_id = p_tenant and nullif(s.make_webhook_url, '') is not null
                   and (s.plans_synced_at is null or s.plans_synced_at < now() - interval '20 seconds'))
$$;

-- Stand des letzten Plan-Abgleichs (für die Oberfläche)
create or replace function public.plans_stand(p_tenant uuid) returns timestamptz
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not public.can_read(p_tenant) then
    raise exception 'Keine Berechtigung für diese Mandantin.' using errcode = '42501';
  end if;
  return (select plans_synced_at from public.tenant_secrets where tenant_id = p_tenant);
end $$;
revoke execute on function public.plans_stand from public, anon;
grant execute on function public.plans_stand to authenticated, service_role;
