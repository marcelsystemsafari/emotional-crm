// Automatischer Abgleich mit Flenski (Entscheidung 0006).
// pg_cron prüft alle 5 Minuten in der Datenbank, ob eine Mandantin fällig ist (flenski_faellige_mandanten:
// Kurs beginnt bald / hat gerade begonnen, oder letzter Abgleich über eine Stunde her), und ruft nur dann hier an.
// Schutz über den Header x-sync-secret.
// Holt für jede Mandantin mit Flenski-Schlüssel alle Termine der App und übergibt sie an
// sync_flenski_events: Termine anlegen, Anmeldungen angleichen, Termine 5 Minuten nach Beginn abschließen.
//
// Flenski-Schnittstelle: https://app.flenski.io/api/v1, Header X-API-KEY, Pfad /apps/{appId}/events?page=&limit=
// (ermittelt am 23.10.2026, siehe docs/04-flenski-integration.md).

import { createClient } from "jsr:@supabase/supabase-js@2";

const FLENSKI_API = "https://app.flenski.io/api/v1";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

function reply(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function sameText(a: string, b: string) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// Nur die Felder, die der Abgleich braucht (keine Beschreibungen, keine Profildaten außer der ID)
// deno-lint-ignore no-explicit-any
function slim(e: any) {
  return {
    id: e.id,
    title: e.title || e.name,
    startsAt: e.startsAtUtc || e.startsAt,
    endsAt: e.endsAtUtc || e.endsAt,
    timeZone: e.timeZone,
    category: e.category ? { name: e.category.name } : null,
    participantsNumberLimit: e.participantsNumberLimit,
    frontendUrl: e.frontendUrl,
    attendedCount: e.attendedCount,
    // deno-lint-ignore no-explicit-any
    lastAttended: (e.lastAttended || []).map((p: any) => ({ id: p.id })),
  };
}

async function fetchEvents(appId: string, apiKey: string) {
  const events = [];
  for (let page = 1; page <= 20; page++) {
    const res = await fetch(`${FLENSKI_API}/apps/${appId}/events?page=${page}&limit=100`, {
      headers: { "X-API-KEY": apiKey, Accept: "application/json" },
      signal: AbortSignal.timeout(20000),
    });
    if (!res.ok) throw new Error(`Flenski antwortet ${res.status}`);
    const body = await res.json();
    events.push(...(body.data || []).map(slim));
    const pages = body.meta?.pagination?.pages ?? 1;
    if (page >= pages) break;
  }
  return events;
}

// Was der Flenski-API-Schlüssel nicht darf (Plan entziehen/zuweisen, vollständige Teilnehmerliste), erledigt das
// Make-Szenario "ECRM: Flenski-Aktionen" mit Marcels Flenski-Verbindung. Aufruf nur bei Bedarf, je etwa 3 Make-Operationen.
// Supabase-Secret MAKE_WEBHOOK_URL. Antwort von Make: {"ok":true, ...}; alles andere gilt als Fehler.
// deno-lint-ignore no-explicit-any
async function make(daten: Record<string, unknown>): Promise<any> {
  const url = Deno.env.get("MAKE_WEBHOOK_URL");
  if (!url) throw new Error("MAKE_WEBHOOK_URL fehlt");
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(daten),
    signal: AbortSignal.timeout(40000),
  });
  const text = await res.text();
  let antwort;
  try { antwort = JSON.parse(text); } catch { throw new Error(`Make antwortet ${res.status}: ${text.slice(0, 120)}`); }
  if (!antwort?.ok) throw new Error(`Make meldet Fehler: ${text.slice(0, 200)}`);
  return antwort;
}

// deno-lint-ignore no-explicit-any
async function planAktion(aktion: "revoke" | "assign", t: any, email: string, planId: string) {
  try {
    await make({ aktion, projectId: t.settings?.flenski_project_id, appId: t.settings?.flenski_app_id, email, planId });
    return null;
  } catch (e) {
    return e instanceof Error ? e.message : String(e);
  }
}

// Vollständige Teilnehmerliste für fällige Termine, deren Namensliste Flenski gekürzt hat
async function fehlendeTeilnehmer(tenantId: string) {
  const { data: offen, error } = await supabase.rpc("flenski_teilnehmer_benoetigt", { p_tenant: tenantId });
  if (error) throw error;
  let geholt = 0;
  for (const o of offen || []) {
    try {
      const antwort = await make({ aktion: "attendees", eventId: o.event_id });
      // deno-lint-ignore no-explicit-any
      const ids = (antwort.body?.data || []).map((p: any) => p.id).filter(Boolean);
      const { error: e2 } = await supabase.rpc("flenski_teilnehmer_setzen", { p_session: o.session_id, p_profiles: ids });
      if (e2) throw e2;
      geholt++;
    } catch (e) {
      // ohne vollständige Liste gleicht das CRM vorsichtig ab ("Teilnahme unklar" statt raten)
      console.error("Teilnehmerliste über Make fehlgeschlagen", e instanceof Error ? e.message : e);
    }
  }
  return geholt;
}

// Offene Entzüge einer Mandantin abarbeiten (nur wenn sie es eingeschaltet hat, prüft die Datenbank)
// deno-lint-ignore no-explicit-any
async function revokeOpenPlans(t: any) {
  const { data: offen, error } = await supabase.rpc("flenski_offene_entzuege", { p_tenant: t.id });
  if (error) throw error;
  let entzogen = 0;
  for (const o of offen || []) {
    const fehler = await planAktion("revoke", t, o.email, o.plan_id);
    await supabase.rpc("flenski_entzug_ergebnis", { p_notice: o.notice_id, p_ok: !fehler, p_info: fehler });
    if (!fehler) entzogen++;
    else console.error(`Plan-Entzug fehlgeschlagen (${o.produkt})`, fehler);
  }
  return entzogen;
}

// Karte wieder aufgefüllt: Plan zurückgeben
// deno-lint-ignore no-explicit-any
async function restorePlans(t: any) {
  const { data: offen, error } = await supabase.rpc("flenski_offene_rueckgaben", { p_tenant: t.id });
  if (error) throw error;
  let zurueck = 0;
  for (const o of offen || []) {
    const fehler = await planAktion("assign", t, o.email, o.plan_id);
    await supabase.rpc("flenski_rueckgabe_ergebnis", { p_notice: o.notice_id, p_ok: !fehler, p_info: fehler });
    if (!fehler) zurueck++;
    else console.error(`Plan-Rückgabe fehlgeschlagen (${o.produkt})`, fehler);
  }
  return zurueck;
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("SYNC_SECRET") || "";
  if (!secret || !sameText(req.headers.get("x-sync-secret") || "", secret)) {
    return reply(401, { ok: false, error: "Nicht erlaubt" });
  }

  // Nur Mandantinnen, bei denen gerade ein Kurs ansteht oder der letzte Abgleich über eine Stunde her ist
  const { data: faellig, error: faelligError } = await supabase.rpc("flenski_faellige_mandanten");
  if (faelligError) {
    console.error("Fällige Mandanten nicht lesbar", faelligError);
    return reply(500, { ok: false });
  }
  const ids = (faellig || []).map((r: unknown) => (typeof r === "string" ? r : Object.values(r as object)[0]));
  if (!ids.length) return reply(200, { ok: true, result: {} });

  const { data: tenants, error } = await supabase
    .from("tenants")
    .select("id, slug, settings, status, tenant_secrets(flenski_api_key)")
    .in("id", ids);
  if (error) {
    console.error("Mandanten nicht lesbar", error);
    return reply(500, { ok: false });
  }

  const result: Record<string, unknown> = {};
  for (const t of tenants || []) {
    const appId = t.settings?.flenski_app_id;
    // deno-lint-ignore no-explicit-any
    const apiKey = (t as any).tenant_secrets?.flenski_api_key;
    if (!appId || !apiKey) continue;
    try {
      const events = await fetchEvents(appId, apiKey);
      const listen = await fehlendeTeilnehmer(t.id);
      const { data, error: rpcError } = await supabase.rpc("sync_flenski_events", { p_tenant: t.id, p_events: events });
      if (rpcError) throw rpcError;
      const entzogen = await revokeOpenPlans(t);
      const zurueck = await restorePlans(t);
      result[t.slug] = { ...data, listen_ueber_make: listen, plaene_entzogen: entzogen, plaene_zurueck: zurueck };
    } catch (e) {
      // Fehler bei einer Mandantin hält die anderen nicht auf; ohne frischen Stand wird nichts abgebucht
      console.error(`Abgleich ${t.slug} fehlgeschlagen`, e instanceof Error ? e.message : e);
      result[t.slug] = { fehler: e instanceof Error ? e.message : String(e) };
    }
  }
  return reply(200, { ok: true, result });
});
