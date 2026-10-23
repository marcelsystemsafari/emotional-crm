-- Keine Aufforderung "Plan entziehen", wenn die Person schon eine weitere aktive Karte desselben Angebots hat.
create or replace function public.karte_status_hinweis() returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare
  v_prod public.products;
begin
  select * into v_prod from public.products where id = new.product_id;
  if v_prod.flenski_plan_id is null then return new; end if;

  if new.status in ('used_up', 'expired') and old.status = 'active' then
    -- eine offene Rückgabe ist hinfällig
    update public.customer_notices set resolved_at = now(), detail = detail || '{"erledigt": "Karte wieder leer"}'
    where customer_id = new.customer_id and kind = 'plan_zurueckgeben' and resolved_at is null
      and detail ->> 'entitlement_id' = new.id::text;
    if new.flenski_plan_revoked_at is null
       and not exists (select 1 from public.entitlements e2 where e2.customer_id = new.customer_id
                         and e2.product_id = new.product_id and e2.id <> new.id and e2.status = 'active')
       and not exists (
         select 1 from public.customer_notices n where n.customer_id = new.customer_id and n.kind = 'plan_entziehen'
           and n.resolved_at is null and n.detail ->> 'entitlement_id' = new.id::text) then
      insert into public.customer_notices (tenant_id, customer_id, kind, detail)
      values (new.tenant_id, new.customer_id, 'plan_entziehen',
              jsonb_build_object('entitlement_id', new.id, 'produkt', v_prod.name, 'plan', v_prod.name,
                                 'grund', case new.status when 'expired' then 'abgelaufen' else 'aufgebraucht' end));
    end if;
  elsif new.status = 'active' and old.status in ('used_up', 'expired') then
    update public.customer_notices set resolved_at = now()
    where customer_id = new.customer_id and kind = 'plan_entziehen' and resolved_at is null
      and detail ->> 'entitlement_id' = new.id::text;
    -- Plan war schon entzogen: zurückgeben
    if new.flenski_plan_revoked_at is not null and not exists (
         select 1 from public.customer_notices n where n.customer_id = new.customer_id and n.kind = 'plan_zurueckgeben'
           and n.resolved_at is null and n.detail ->> 'entitlement_id' = new.id::text) then
      insert into public.customer_notices (tenant_id, customer_id, kind, detail)
      values (new.tenant_id, new.customer_id, 'plan_zurueckgeben',
              jsonb_build_object('entitlement_id', new.id, 'produkt', v_prod.name, 'plan', v_prod.name));
    end if;
  end if;
  return new;
end $$;
