-- Phase 1, Schritt 1: Wer darf welche Mandantin sehen und bearbeiten?
-- Rollen: owner (Lehrerin), staff (Vertretung), platform_admin (Marcel). Siehe 03-datenmodell.md, "Row Level Security".

create type public.member_role as enum ('owner', 'staff');

create table public.tenant_members (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references public.tenants (id),
  user_id    uuid not null references auth.users (id) on delete cascade,
  role       public.member_role not null,
  created_at timestamptz not null default now(),
  unique (tenant_id, user_id)
);

create table public.platform_admins (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

-- Aufrufe ohne Nutzer-Login: Datenbank direkt (Migration, Tests, Skripte) oder Server mit Service-Role.
-- Nur diese "System"-Aufrufe dürfen die Fachfunktionen ohne Mitgliedschaft nutzen.
create function public.is_system() returns boolean
language sql stable
set search_path = ''
as $$ select coalesce(auth.role(), '') in ('', 'service_role') and auth.uid() is null $$;

create function public.is_platform_admin() returns boolean
language sql stable security definer
set search_path = ''
as $$ select exists (select 1 from public.platform_admins where user_id = auth.uid()) $$;

-- Lesen: Mitglied und Mandantin nicht ruhend/gelöscht (cancelled darf noch 30 Tage lesen + exportieren)
create function public.can_read(p_tenant uuid) returns boolean
language sql stable security definer
set search_path = ''
as $$
  select public.is_system() or public.is_platform_admin() or exists (
    select 1 from public.tenant_members m join public.tenants t on t.id = m.tenant_id
    where m.tenant_id = p_tenant and m.user_id = auth.uid() and t.status in ('trial', 'active', 'cancelled'))
$$;

-- Schreiben: Mitglied und Mandantin aktiv (trial/active)
create function public.can_write(p_tenant uuid) returns boolean
language sql stable security definer
set search_path = ''
as $$
  select public.is_system() or public.is_platform_admin() or exists (
    select 1 from public.tenant_members m join public.tenants t on t.id = m.tenant_id
    where m.tenant_id = p_tenant and m.user_id = auth.uid() and t.status in ('trial', 'active'))
$$;

-- Nur owner: Produkte, Einstellungen, Kundin löschen, Export
create function public.is_owner(p_tenant uuid) returns boolean
language sql stable security definer
set search_path = ''
as $$
  select public.is_system() or public.is_platform_admin() or exists (
    select 1 from public.tenant_members m join public.tenants t on t.id = m.tenant_id
    where m.tenant_id = p_tenant and m.user_id = auth.uid() and m.role = 'owner'
      and t.status in ('trial', 'active'))
$$;

revoke execute on function public.is_system, public.is_platform_admin, public.can_read, public.can_write, public.is_owner from public, anon;
grant execute on function public.is_system, public.is_platform_admin, public.can_read, public.can_write, public.is_owner to authenticated, service_role;

-- tenants: lesen ohne webhook_secret, Einstellungen nur owner
grant select (id, name, slug, timezone, status, flenski_app_url, settings, created_at) on public.tenants to authenticated;
grant update (name, timezone, settings) on public.tenants to authenticated;
create policy tenants_lesen on public.tenants for select to authenticated using (public.can_read(id));
create policy tenants_einstellungen on public.tenants for update to authenticated
  using (public.is_owner(id)) with check (public.is_owner(id));

-- tenant_members: Mitglieder sehen ihr Team; anlegen/ändern nur Marcel (bzw. Skript mit Service-Role)
alter table public.tenant_members enable row level security;
grant select on public.tenant_members to authenticated;
grant insert, update, delete on public.tenant_members to authenticated;
create policy members_lesen on public.tenant_members for select to authenticated using (public.can_read(tenant_id));
create policy members_verwalten on public.tenant_members for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());

alter table public.platform_admins enable row level security;
grant select on public.platform_admins to authenticated;
create policy admins_selbst on public.platform_admins for select to authenticated using (user_id = auth.uid());

-- Standardeinstellungen laut Entscheidungen vom 22.10.2026 (docs/phase1-plan.md)
update public.tenants set settings = settings || '{"storno_frist_stunden": 12, "signal_neu_tage": 14}'::jsonb
where slug = 'yoga-by-lana';
