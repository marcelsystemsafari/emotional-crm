-- Profilfotos aus Flenski (member.avatar.url) für die Oberfläche (Entwurf v2, 22.10.2026).
-- Dazu liefert v_customer_engagement Foto und Flenski-Profil-ID (für den Link "Profil in der App").

alter table public.customers add column if not exists avatar_url text;

create or replace function public._upsert_member(p_tenant uuid, p_member jsonb, p_event uuid) returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_profile uuid := nullif(p_member ->> 'id', '')::uuid;
  v_first text := nullif(btrim(p_member ->> 'firstName'), '');
  v_last text := nullif(btrim(p_member ->> 'lastName'), '');
  v_full text := nullif(btrim(p_member ->> 'fullName'), '');
  v_email text := nullif(lower(btrim(p_member ->> 'email')), '');
  v_tags text[] := coalesce(array(select jsonb_array_elements_text(case when jsonb_typeof(p_member -> 'tags') = 'array' then p_member -> 'tags' end)), '{}');
  v_id uuid;
  v_dublette uuid;
  v_ausschluss text[];
  v_joined timestamptz := public._ts(p_member ->> 'createdAt');
  v_avatar text := nullif(p_member #>> '{avatar,url}', '');
begin
  if v_profile is null then return null; end if;
  -- Profile mit Ausschluss-Tag (z. B. "Yogalehrerin") sind keine Kundinnen (tenants.settings.ausschluss_tags)
  select coalesce(array(select jsonb_array_elements_text(settings -> 'ausschluss_tags')), '{}') into v_ausschluss
  from public.tenants where id = p_tenant;
  if v_tags && v_ausschluss then return null; end if;
  if coalesce((p_member ->> 'isMemberOfTeam')::boolean, false) or coalesce((p_member ->> 'isAdmin')::boolean, false) then
    return null;
  end if;
  if v_first is null then
    v_first := coalesce(split_part(v_full, ' ', 1), 'Mitglied');
    v_last := coalesce(v_last, nullif(btrim(substr(v_full, length(split_part(v_full, ' ', 1)) + 1)), ''));
  end if;

  select id into v_id from public.customers where tenant_id = p_tenant and flenski_profile_id = v_profile;
  if v_id is not null then
    update public.customers
    set first_name = v_first, last_name = v_last, email = coalesce(v_email, email),
        tags = (select array(select distinct unnest(tags || v_tags))),
        joined_at = coalesce(v_joined, joined_at),
        avatar_url = coalesce(v_avatar, avatar_url)
    where id = v_id and anonymized_at is null;
    return v_id;
  end if;

  insert into public.customers (tenant_id, first_name, last_name, email, source, flenski_profile_id, tags, joined_at, avatar_url)
  values (p_tenant, v_first, v_last, v_email, 'flenski', v_profile, v_tags, coalesce(v_joined, now()), v_avatar)
  returning id into v_id;

  -- Mögliche Dublette: gleiche E-Mail bei einer Person ohne App-Verknüpfung – nicht zusammenführen, nur Hinweis
  if v_email is not null then
    select id into v_dublette from public.customers
    where tenant_id = p_tenant and id <> v_id and lower(email) = v_email and anonymized_at is null limit 1;
    if v_dublette is not null then
      insert into public.customer_notices (tenant_id, customer_id, kind, detail, webhook_event_id)
      values (p_tenant, v_id, 'moegliche_dublette', jsonb_build_object('andere_person', v_dublette), p_event);
    end if;
  end if;
  return v_id;
end $$;

create or replace view public.v_customer_engagement with (security_invoker = true) as
with basis as (
  select c.id as customer_id, c.tenant_id, c.first_name, c.last_name, c.source, c.is_child, c.tags,
         coalesce(c.joined_at, c.created_at) as joined_at, c.avatar_url, c.flenski_profile_id, c.last_visit_at, c.last_app_activity_at,
         greatest(c.last_visit_at, c.last_app_activity_at) as last_activity_at,
         coalesce((t.settings ->> 'engagement_neu_tage')::int, 14) as neu_tage,
         coalesce((t.settings ->> 'engagement_aktiv_tage')::int, 14) as aktiv_tage,
         coalesce((t.settings ->> 'engagement_abkuehlt_tage')::int, 30) as abkuehlt_tage,
         coalesce((t.settings ->> 'gewicht_besuch')::int, 3) as g_besuch,
         coalesce((t.settings ->> 'gewicht_aktiv')::int, 2) as g_aktiv,
         coalesce((t.settings ->> 'gewicht_passiv')::int, 1) as g_passiv
  from public.customers c join public.tenants t on t.id = c.tenant_id
  where c.archived_at is null and c.anonymized_at is null
),
besuche as (
  select a.customer_id, s.starts_at as am
  from public.attendances a join public.sessions s on s.id = a.session_id
  where a.status = 'present'
),
app as (
  select customer_id, occurred_at as am,
         case when type in ('article_read', 'file_downloaded', 'lockscreen_cta') then 'passiv' else 'aktiv' end as art
  from public.activity_events where customer_id is not null
)
select b.customer_id, b.tenant_id, b.first_name, b.last_name, b.source, b.is_child, b.tags, b.joined_at,
       b.last_visit_at, b.last_app_activity_at, b.last_activity_at,
       case
         when b.joined_at >= now() - make_interval(days => b.neu_tage) then 'neu'
         when b.last_activity_at >= now() - make_interval(days => b.aktiv_tage) then 'dabei'
         when b.last_activity_at >= now() - make_interval(days => b.abkuehlt_tage) then 'kuehlt_ab'
         else 'eingeschlafen'
       end as status,
       case when b.last_activity_at is null then null
            else extract(day from now() - b.last_activity_at)::int end as tage_still,
       ( (select count(*) from besuche v where v.customer_id = b.customer_id and v.am between now() - interval '30 days' and now()) * b.g_besuch
       + (select count(*) from app x where x.customer_id = b.customer_id and x.am >= now() - interval '30 days' and x.art = 'aktiv') * b.g_aktiv
       + (select count(*) from app x where x.customer_id = b.customer_id and x.am >= now() - interval '30 days' and x.art = 'passiv') * b.g_passiv
       )::int as score_30d,
       (select count(*) from besuche v where v.customer_id = b.customer_id and v.am <= now())::int as besuche_gesamt,
       array(
         select ((select count(*) from besuche v where v.customer_id = b.customer_id
                    and v.am >= now() - make_interval(days => 7 * (w + 1)) and v.am < now() - make_interval(days => 7 * w))
               + (select count(*) from app x where x.customer_id = b.customer_id
                    and x.am >= now() - make_interval(days => 7 * (w + 1)) and x.am < now() - make_interval(days => 7 * w)))::int
         from generate_series(7, 0, -1) w
       ) as events_8w,
       b.avatar_url, b.flenski_profile_id
from basis b;
