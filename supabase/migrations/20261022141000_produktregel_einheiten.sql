-- Korrektur: "credits > 0" ist bei leerem Feld nicht falsch, sondern unbekannt – und ließ Karten ohne Einheiten durch.
alter table public.products drop constraint products_check;
alter table public.products add constraint products_einheiten_check check (
  case type
    when 'credits' then coalesce(credits > 0, false)
    when 'single' then coalesce(credits = 1, false)
    else credits is null
  end
);
