-- Pläne, die (noch) außerhalb des CRM gezählt werden (Nina, 24.10.2026: 8er-Karte bleibt in Make, Schritt 1).
-- tenants.settings.extern_plaene = Liste von Flenski-Plan-IDs. Solche Produkte:
--   - stehen nicht unter "noch nicht verbunden", sondern als "wird extern gezählt",
--   - lassen sich nicht als Karte mit Besuchen verbinden (setup_product verweigert),
--   - ziehen im CRM nie Besuche ab (Typ "ohne Zählen").

alter table public.products add column if not exists extern_gezaehlt boolean not null default false;

create or replace function public._produkt_extern_markieren() returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  if new.flenski_plan_id is not null and exists (
       select 1 from public.tenants t
       where t.id = new.tenant_id
         and t.settings -> 'extern_plaene' ? new.flenski_plan_id::text) then
    new.extern_gezaehlt := true;
    new.needs_setup := false;
    new.type := 'period';
    new.credits := null;
  end if;
  return new;
end $$;
drop trigger if exists products_extern on public.products;
create trigger products_extern before insert or update of flenski_plan_id, type, needs_setup on public.products
  for each row execute function public._produkt_extern_markieren();
revoke execute on function public._produkt_extern_markieren from public, anon, authenticated;

-- Einrichten verweigern
do $$
declare
  v_src text;
begin
  select pg_get_functiondef('public.setup_product(uuid, public.product_type, int, int, int, text)'::regprocedure) into v_src;
  if position('extern_gezaehlt' in v_src) = 0 then
    v_src := replace(v_src,
      $a$  if not v_p.needs_setup then$a$,
      $b$  if v_p.extern_gezaehlt then
    raise exception 'Dieses Angebot wird außerhalb des CRM gezählt und kann hier nicht verbunden werden.' using errcode = 'P0001';
  end if;
  if not v_p.needs_setup then$b$);
    if position('extern_gezaehlt' in v_src) = 0 then raise exception 'setup_product: Anker fehlt'; end if;
    execute v_src;
  end if;
end $$;

-- Nina: "YN 8er Karte" bleibt in Make (bis Schritt 2)
update public.tenants set settings = settings || '{"extern_plaene": ["b7145251-eb84-4b2a-b5cc-197f3a2fcc06"]}'
where slug = 'yogini-nina';
update public.products set extern_gezaehlt = extern_gezaehlt
where flenski_plan_id = 'b7145251-eb84-4b2a-b5cc-197f3a2fcc06';
