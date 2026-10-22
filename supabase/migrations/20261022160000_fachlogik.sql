-- Phase 1, Schritt 4: Fachlogik als SQL-Funktionen (Regel 6). Oberfläche und Webhook rufen nur diese Funktionen auf.
-- Alle laufen mit Rechten der Datenbank (security definer) und prüfen selbst, ob die aufrufende Person darf.

-- Berechtigung prüfen, sonst verständlicher Fehler
create function public._require_write(p_tenant uuid) returns void
language plpgsql stable
set search_path = ''
as $$
begin
  if not public.can_write(p_tenant) then
    raise exception 'Keine Berechtigung für diese Mandantin (oder Mandantin nur lesbar).' using errcode = '42501';
  end if;
end $$;

-- Netto-Abzug einer Anwesenheit (negativ = gerade belastet)
create function public._netto_abzug(p_attendance uuid) returns int
language sql stable
set search_path = ''
as $$ select coalesce(sum(delta), 0)::int from public.ledger_entries where attendance_id = p_attendance $$;

-- Passende Karte für eine Stunde: zuerst unbegrenzte (Kursblock/Abo, kein Abzug),
-- sonst Karte mit Guthaben, die zuerst abläuft (FEFO), bei Gleichstand die ältere.
create function public._passende_karte(p_customer uuid, p_session uuid)
returns table (entitlement_id uuid, unlimited boolean)
language sql stable
set search_path = ''
as $$
  select b.entitlement_id, b.unlimited
  from public.v_entitlement_balance b, public.sessions s
  where s.id = p_session
    and b.customer_id = p_customer
    and b.status <> 'cancelled'
    and b.starts_at <= s.starts_at
    and (b.expires_at is null or b.expires_at > s.starts_at)
    and (b.category is null or s.category is null or lower(b.category) = lower(s.category))
    and (b.unlimited or b.balance > 0)
  order by b.unlimited desc, b.expires_at asc nulls last, b.created_at asc
  limit 1
$$;

-- Belastet eine Anwesenheit (falls nicht schon belastet). Gibt die Karte zurück, null = keine passende Karte.
create function public._abbuchen(p_attendance uuid) returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_att public.attendances;
  v_karte record;
begin
  select * into v_att from public.attendances where id = p_attendance;
  -- alle Karten der Kundin sperren, damit zwei gleichzeitige Check-ins nicht dieselbe letzte Einheit nehmen
  perform 1 from public.entitlements where customer_id = v_att.customer_id for update;
  if public._netto_abzug(p_attendance) < 0 then
    return v_att.entitlement_id;
  end if;
  select * into v_karte from public._passende_karte(v_att.customer_id, v_att.session_id);
  if v_karte.entitlement_id is null then
    update public.attendances set entitlement_id = null where id = p_attendance;
    return null;
  end if;
  if not v_karte.unlimited then
    insert into public.ledger_entries (tenant_id, entitlement_id, customer_id, delta, reason, attendance_id, created_by)
    values (v_att.tenant_id, v_karte.entitlement_id, v_att.customer_id, -1, 'visit', p_attendance, auth.uid());
  end if;
  update public.attendances set entitlement_id = v_karte.entitlement_id where id = p_attendance;
  return v_karte.entitlement_id;
end $$;

-- Hebt eine Belastung wieder auf (Gegenbuchung, nichts wird gelöscht)
create function public._rueckbuchen(p_attendance uuid, p_kommentar text) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_zeile record;
begin
  for v_zeile in
    select tenant_id, entitlement_id, customer_id, sum(delta)::int as netto
    from public.ledger_entries where attendance_id = p_attendance
    group by tenant_id, entitlement_id, customer_id having sum(delta) < 0
  loop
    insert into public.ledger_entries (tenant_id, entitlement_id, customer_id, delta, reason, attendance_id, created_by, comment)
    values (v_zeile.tenant_id, v_zeile.entitlement_id, v_zeile.customer_id, -v_zeile.netto, 'refund', p_attendance, auth.uid(), p_kommentar);
  end loop;
end $$;

-- Anwesenheit holen oder anlegen (Stunde und Kundin müssen zur selben Mandantin gehören)
create function public._anwesenheit(p_session uuid, p_customer uuid) returns public.attendances
language plpgsql
set search_path = ''
as $$
declare
  v_session public.sessions;
  v_customer public.customers;
  v_att public.attendances;
begin
  select * into v_session from public.sessions where id = p_session;
  if not found then raise exception 'Stunde nicht gefunden.' using errcode = 'P0002'; end if;
  perform public._require_write(v_session.tenant_id);
  select * into v_customer from public.customers where id = p_customer and tenant_id = v_session.tenant_id;
  if not found then raise exception 'Kundin nicht gefunden.' using errcode = 'P0002'; end if;
  if v_customer.anonymized_at is not null then raise exception 'Diese Kundin wurde gelöscht.' using errcode = 'P0001'; end if;
  insert into public.attendances (tenant_id, session_id, customer_id)
  values (v_session.tenant_id, p_session, p_customer)
  on conflict (session_id, customer_id) do nothing;
  select * into v_att from public.attendances where session_id = p_session and customer_id = p_customer for update;
  return v_att;
end $$;

-- Antwort für die Oberfläche: Stand nach der Aktion
create function public._ergebnis(p_attendance uuid) returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'attendance_id', a.id,
    'status', a.status,
    'entitlement_id', a.entitlement_id,
    'abgebucht', public._netto_abzug(a.id) < 0,
    'ohne_karte', a.entitlement_id is null and a.status in ('present', 'cancelled_late', 'no_show'),
    'unbegrenzt', coalesce(b.unlimited, false),
    'rest', b.balance,
    'von', b.product_credits,
    'gueltig_bis', b.expires_at)
  from public.attendances a
  left join public.v_entitlement_balance b on b.entitlement_id = a.entitlement_id
  where a.id = p_attendance
$$;

-- ===== Öffentliche Fachfunktionen =====

-- Verkauf: Karte anlegen + Kauf-Buchung. Gibt die neue Karte (entitlement) zurück.
create function public.sell(
  p_customer    uuid,
  p_product     uuid,
  p_paid_via    public.paid_via default 'bar',
  p_price_cents int default null,
  p_starts_at   timestamptz default now(),
  p_source      public.entitlement_source default 'manual',
  p_external_ref text default null
) returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  v_customer public.customers;
  v_product public.products;
  v_id uuid;
begin
  select * into v_customer from public.customers where id = p_customer;
  if not found then raise exception 'Kundin nicht gefunden.' using errcode = 'P0002'; end if;
  perform public._require_write(v_customer.tenant_id);
  if v_customer.anonymized_at is not null then raise exception 'Diese Kundin wurde gelöscht.' using errcode = 'P0001'; end if;
  select * into v_product from public.products where id = p_product and tenant_id = v_customer.tenant_id;
  if not found then raise exception 'Produkt nicht gefunden.' using errcode = 'P0002'; end if;
  if not v_product.active then raise exception 'Dieses Produkt wird nicht mehr verkauft.' using errcode = 'P0001'; end if;

  insert into public.entitlements (tenant_id, customer_id, product_id, source, paid_via, price_cents,
                                   starts_at, expires_at, created_by, external_ref)
  values (v_customer.tenant_id, p_customer, p_product, p_source, p_paid_via,
          coalesce(p_price_cents, v_product.price_cents), p_starts_at,
          p_starts_at + make_interval(days => v_product.validity_days), auth.uid(), p_external_ref)
  returning id into v_id;

  if v_product.type in ('credits', 'single') then
    insert into public.ledger_entries (tenant_id, entitlement_id, customer_id, delta, reason, created_by)
    values (v_customer.tenant_id, v_id, p_customer, v_product.credits, 'purchase', auth.uid());
  end if;

  insert into public.audit_log (tenant_id, actor, action, entity, entity_id, diff)
  values (v_customer.tenant_id, auth.uid(), 'sell', 'entitlements', v_id,
          jsonb_build_object('product', v_product.name, 'paid_via', p_paid_via,
                             'price_cents', coalesce(p_price_cents, v_product.price_cents)));
  return v_id;
end $$;

-- Check-in: anwesend + −1 von der passenden Karte. Ohne passende Karte trotzdem anwesend ("offen").
-- Mehrfaches Antippen bucht nur einmal ab.
create function public.checkin(p_session uuid, p_customer uuid) returns jsonb
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
  end if;
  return public._ergebnis(v_att.id);
end $$;

-- Check-in rückgängig (z. B. falsch angetippt): Gegenbuchung, Anwesenheit zurück auf "angemeldet"
create function public.undo_checkin(p_session uuid, p_customer uuid) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_att public.attendances := public._anwesenheit(p_session, p_customer);
begin
  perform public._rueckbuchen(v_att.id, 'Check-in rückgängig');
  update public.attendances
  set status = 'registered', entitlement_id = null, checked_in_by = null, checked_in_at = null
  where id = v_att.id;
  return public._ergebnis(v_att.id);
end $$;

-- Absage bzw. nicht erschienen. Rechtzeitig (vor Stornofrist) = kein Abzug bzw. Rückbuchung;
-- zu spät / nicht erschienen = Abzug laut Einstellung der Mandantin.
create function public.cancel_attendance(p_session uuid, p_customer uuid, p_no_show boolean default false) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_att public.attendances := public._anwesenheit(p_session, p_customer);
  v_settings jsonb;
  v_beginn timestamptz;
  v_status public.attendance_status;
  v_abzug boolean;
begin
  select t.settings, s.starts_at into v_settings, v_beginn
  from public.sessions s join public.tenants t on t.id = s.tenant_id where s.id = p_session;

  v_status := case
    when p_no_show then 'no_show'
    when now() <= v_beginn - coalesce((v_settings ->> 'storno_frist_stunden')::numeric, 12) * interval '1 hour'
      then 'cancelled_in_time'
    else 'cancelled_late'
  end;
  v_abzug := (v_status = 'cancelled_late' and coalesce((v_settings ->> 'abzug_bei_spaeter_absage')::boolean, true))
          or (v_status = 'no_show' and coalesce((v_settings ->> 'abzug_bei_no_show')::boolean, true));

  update public.attendances set status = v_status where id = v_att.id;
  if v_abzug then
    perform public._abbuchen(v_att.id);
  else
    perform public._rueckbuchen(v_att.id,
      case v_status when 'cancelled_in_time' then 'Rechtzeitig abgesagt' else 'Absage ohne Abzug (Einstellung)' end);
    update public.attendances set entitlement_id = null where id = v_att.id;
  end if;
  return public._ergebnis(v_att.id);
end $$;

-- Korrektur: Plus/Minus mit Pflichtkommentar. Gibt das neue Guthaben der Karte zurück.
create function public.correct(p_entitlement uuid, p_delta int, p_comment text) returns int
language plpgsql security definer
set search_path = ''
as $$
declare
  v_karte public.entitlements;
begin
  select * into v_karte from public.entitlements where id = p_entitlement;
  if not found then raise exception 'Karte nicht gefunden.' using errcode = 'P0002'; end if;
  perform public._require_write(v_karte.tenant_id);
  if coalesce(length(btrim(p_comment)), 0) = 0 then
    raise exception 'Bitte gib einen Grund für die Korrektur an.' using errcode = '23514';
  end if;
  if coalesce(p_delta, 0) = 0 then
    raise exception 'Die Korrektur muss mindestens +1 oder −1 sein.' using errcode = '23514';
  end if;
  insert into public.ledger_entries (tenant_id, entitlement_id, customer_id, delta, reason, created_by, comment)
  values (v_karte.tenant_id, p_entitlement, v_karte.customer_id, p_delta, 'correction', auth.uid(), btrim(p_comment));
  return (select balance from public.v_entitlement_balance where entitlement_id = p_entitlement);
end $$;

-- Verfall: abgelaufene Karten buchen ihr Restguthaben aus. Läuft nachts automatisch (nur System/Marcel).
create function public.expire_entitlements() returns int
language plpgsql security definer
set search_path = ''
as $$
declare
  v_karte record;
  v_anzahl int := 0;
begin
  if not (public.is_system() or public.is_platform_admin()) then
    raise exception 'Nur für den nächtlichen Ablauf.' using errcode = '42501';
  end if;
  for v_karte in
    select b.* from public.v_entitlement_balance b
    where b.status <> 'cancelled' and b.expires_at is not null and b.expires_at <= now()
      and (b.status <> 'expired' or (not b.unlimited and b.balance > 0))
  loop
    if not v_karte.unlimited and v_karte.balance > 0 then
      insert into public.ledger_entries (tenant_id, entitlement_id, customer_id, delta, reason, comment)
      values (v_karte.tenant_id, v_karte.entitlement_id, v_karte.customer_id, -v_karte.balance, 'expiry',
              'Abgelaufen am ' || to_char(v_karte.expires_at at time zone 'Europe/Berlin', 'DD.MM.YYYY'));
    end if;
    perform public.refresh_entitlement_status(v_karte.entitlement_id);
    v_anzahl := v_anzahl + 1;
  end loop;
  return v_anzahl;
end $$;

-- Signale: um wen sollte sich die Lehrerin jetzt kümmern? Schwellen aus tenants.settings.
create function public.customer_signals(p_tenant uuid)
returns table (customer_id uuid, signal text, detail jsonb)
language plpgsql stable security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_s jsonb;
  v_inaktiv int; v_ablauf int; v_fast_leer int; v_neu int;
begin
  if not public.can_read(p_tenant) then
    raise exception 'Keine Berechtigung für diese Mandantin.' using errcode = '42501';
  end if;
  select settings into v_s from public.tenants where id = p_tenant;
  v_inaktiv   := coalesce((v_s ->> 'signal_inaktiv_tage')::int, 21);
  v_ablauf    := coalesce((v_s ->> 'signal_ablauf_tage')::int, 14);
  v_fast_leer := coalesce((v_s ->> 'signal_fast_leer_ab')::int, 1);
  v_neu       := coalesce((v_s ->> 'signal_neu_tage')::int, 14);

  return query
  with kundinnen as (
    select o.* from public.v_customer_overview o
    join public.customers c on c.id = o.customer_id
    where o.tenant_id = p_tenant and c.archived_at is null and c.anonymized_at is null
  ),
  erster_besuch as (
    select a.customer_id, min(s.starts_at) as am
    from public.attendances a join public.sessions s on s.id = a.session_id
    where a.tenant_id = p_tenant and a.status = 'present'
    group by a.customer_id
  ),
  letzter_kauf as (
    select e.customer_id, max(e.starts_at) as am from public.entitlements e
    where e.tenant_id = p_tenant group by e.customer_id
  )
  -- Droht abzuspringen: noch Guthaben (oder Abo/Block), aber lange nicht da
  select k.customer_id, 'droht_abzuspringen',
         jsonb_build_object('tage_ohne_besuch', extract(day from now() - coalesce(k.last_visit_at, lk.am))::int,
                            'guthaben', k.credits_balance, 'unbegrenzt', k.has_unlimited)
  from kundinnen k left join letzter_kauf lk on lk.customer_id = k.customer_id
  where (k.credits_balance > 0 or k.has_unlimited)
    and coalesce(k.last_visit_at, lk.am) < now() - make_interval(days => v_inaktiv)
  union all
  -- Karte fast leer: kommt regelmäßig (Besuch in den letzten 30 Tagen), Guthaben ≤ Schwelle
  select k.customer_id, 'karte_fast_leer', jsonb_build_object('guthaben', k.credits_balance)
  from kundinnen k
  where not k.has_unlimited and k.credits_balance <= v_fast_leer
    and k.last_visit_at >= now() - interval '30 days'
  union all
  -- Karte läuft bald ab und ist noch nicht verbraucht
  select b.customer_id, 'laeuft_bald_ab',
         jsonb_build_object('produkt', b.product_name, 'gueltig_bis', b.expires_at, 'rest', b.balance)
  from public.v_entitlement_balance b join kundinnen k on k.customer_id = b.customer_id
  where b.status = 'active' and (b.unlimited or b.balance > 0)
    and b.expires_at between now() and now() + make_interval(days => v_ablauf)
  union all
  -- Neu dabei: erster Besuch innerhalb der letzten Tage
  select k.customer_id, 'neu_dabei', jsonb_build_object('erster_besuch', eb.am)
  from kundinnen k join erster_besuch eb on eb.customer_id = k.customer_id
  where eb.am >= now() - make_interval(days => v_neu);
end $$;

-- Kundin löschen = Personendaten entfernen, Buchungen bleiben anonym erhalten (Regel 9, Art. 17 DSGVO).
create function public.anonymize_customer(p_customer uuid) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select tenant_id into v_tenant from public.customers where id = p_customer;
  if not found then raise exception 'Kundin nicht gefunden.' using errcode = 'P0002'; end if;
  if not public.is_owner(v_tenant) then
    raise exception 'Nur die Inhaberin darf Kundinnen löschen.' using errcode = '42501';
  end if;
  update public.customers
  set first_name = 'Gelöschte Kundin', last_name = null, email = null, phone = null,
      guardian_name = null, guardian_email = null, guardian_phone = null,
      tags = '{}', note = null, flenski_profile_id = null,
      archived_at = coalesce(archived_at, now()), anonymized_at = now()
  where id = p_customer;
  delete from public.activity_events where customer_id = p_customer;
end $$;

-- Rechte: Hilfsfunktionen nur intern, Fachfunktionen für eingeloggte Nutzerinnen
revoke execute on function public._require_write, public._netto_abzug, public._passende_karte, public._abbuchen,
  public._rueckbuchen, public._anwesenheit, public._ergebnis from public, anon, authenticated;
revoke execute on function public.sell, public.checkin, public.undo_checkin, public.cancel_attendance, public.correct,
  public.expire_entitlements, public.customer_signals, public.anonymize_customer from public, anon;
grant execute on function public.sell, public.checkin, public.undo_checkin, public.cancel_attendance, public.correct,
  public.expire_entitlements, public.customer_signals, public.anonymize_customer to authenticated, service_role;
