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

// Plan einer Person in der App entziehen bzw. wieder zuweisen (Pfade ermittelt 23.10.2026, Felder wie im
// Make-Modul revokePlansProfile: E-Mail der Person und Plan-IDs). Gibt null bei Erfolg, sonst eine kurze Fehlerbeschreibung.
async function revokePlan(appId: string, apiKey: string, email: string, planId: string) {
  return await planCall(`${FLENSKI_API}/apps/${appId}/profiles/plans/revoke`, apiKey, email, planId);
}
async function assignPlan(appId: string, apiKey: string, email: string, planId: string) {
  return await planCall(`${FLENSKI_API}/apps/${appId}/profiles/plans`, apiKey, email, planId);
}
async function planCall(url: string, apiKey: string, email: string, planId: string) {
  const res = await fetch(url, {
    method: "POST",
    headers: { "X-API-KEY": apiKey, "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ email, planIds: [planId] }),
    signal: AbortSignal.timeout(20000),
  });
  if (res.ok) return null;
  return `Flenski ${res.status}: ${(await res.text()).slice(0, 200)}`;
}

// Offene Entzüge einer Mandantin abarbeiten (nur wenn sie es eingeschaltet hat, prüft die Datenbank)
async function revokeOpenPlans(tenantId: string, appId: string, apiKey: string) {
  const { data: offen, error } = await supabase.rpc("flenski_offene_entzuege", { p_tenant: tenantId });
  if (error) throw error;
  let entzogen = 0;
  for (const o of offen || []) {
    let fehler: string | null;
    try {
      fehler = await revokePlan(appId, apiKey, o.email, o.plan_id);
    } catch (e) {
      fehler = e instanceof Error ? e.message : String(e);
    }
    await supabase.rpc("flenski_entzug_ergebnis", { p_notice: o.notice_id, p_ok: !fehler, p_info: fehler });
    if (!fehler) entzogen++;
    else console.error(`Plan-Entzug fehlgeschlagen (${o.produkt})`, fehler);
  }
  return entzogen;
}

// Karte wieder aufgefüllt: Plan zurückgeben
async function restorePlans(tenantId: string, appId: string, apiKey: string) {
  const { data: offen, error } = await supabase.rpc("flenski_offene_rueckgaben", { p_tenant: tenantId });
  if (error) throw error;
  let zurueck = 0;
  for (const o of offen || []) {
    let fehler: string | null;
    try {
      fehler = await assignPlan(appId, apiKey, o.email, o.plan_id);
    } catch (e) {
      fehler = e instanceof Error ? e.message : String(e);
    }
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
      const { data, error: rpcError } = await supabase.rpc("sync_flenski_events", { p_tenant: t.id, p_events: events });
      if (rpcError) throw rpcError;
      const entzogen = await revokeOpenPlans(t.id, appId, apiKey);
      const zurueck = await restorePlans(t.id, appId, apiKey);
      result[t.slug] = { ...data, plaene_entzogen: entzogen, plaene_zurueck: zurueck };
    } catch (e) {
      // Fehler bei einer Mandantin hält die anderen nicht auf; ohne frischen Stand wird nichts abgebucht
      console.error(`Abgleich ${t.slug} fehlgeschlagen`, e instanceof Error ? e.message : e);
      result[t.slug] = { fehler: e instanceof Error ? e.message : String(e) };
    }
  }
  return reply(200, { ok: true, result });
});
