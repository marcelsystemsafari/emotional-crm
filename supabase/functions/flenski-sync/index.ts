// Automatischer Abgleich mit Flenski (Entscheidung 0006).
// Wird alle 5 Minuten von pg_cron angestoßen (Job "ecrm-flenski-abgleich"), Schutz über den Header x-sync-secret.
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

Deno.serve(async (req) => {
  const secret = Deno.env.get("SYNC_SECRET") || "";
  if (!secret || !sameText(req.headers.get("x-sync-secret") || "", secret)) {
    return reply(401, { ok: false, error: "Nicht erlaubt" });
  }

  const { data: tenants, error } = await supabase
    .from("tenants")
    .select("id, slug, settings, status, tenant_secrets(flenski_api_key)")
    .in("status", ["trial", "active"]);
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
      result[t.slug] = data;
    } catch (e) {
      // Fehler bei einer Mandantin hält die anderen nicht auf; ohne frischen Stand wird nichts abgebucht
      console.error(`Abgleich ${t.slug} fehlgeschlagen`, e instanceof Error ? e.message : e);
      result[t.slug] = { fehler: e instanceof Error ? e.message : String(e) };
    }
  }
  return reply(200, { ok: true, result });
});
