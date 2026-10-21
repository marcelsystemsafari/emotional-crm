// Empfänger für Flenski-Automationen ("Webhook senden").
// Phase 0: speichert jede Anfrage unverändert in webhook_events und antwortet sofort mit 200.
// Verarbeitung (Kundinnen, Pläne, Aktivität) kommt in Phase 3, auf Basis der hier gesammelten echten Payloads.
//
// URL je Automation:
//   https://<projekt>.supabase.co/functions/v1/flenski-webhook?tenant=<slug>&trigger=<triggername>
// "trigger" setzen wir selbst in der URL, weil unbekannt ist, ob Flenski den Triggernamen im Body mitschickt.

import { createClient } from "jsr:@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

// Diese Header nie speichern (Zugangsdaten bzw. reine Infrastruktur-Angaben)
const SKIP_HEADERS = new Set(["authorization", "apikey", "cookie"]);

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function reply(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function sha256Hex(text: string) {
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(hash), (b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  // Aufruf im Browser: kurze Bestätigung, dass der Empfänger läuft
  if (req.method !== "POST") return reply(200, { ok: true, info: "flenski-webhook bereit" });

  const url = new URL(req.url);
  const tenantParam = url.searchParams.get("tenant");
  if (!tenantParam) return reply(400, { ok: false, error: "Parameter tenant fehlt" });

  const { data: tenant, error: tenantError } = await supabase
    .from("tenants")
    .select("id")
    .eq(UUID.test(tenantParam) ? "id" : "slug", tenantParam)
    .maybeSingle();
  if (tenantError) {
    console.error("Mandant nicht lesbar", tenantError);
    return reply(500, { ok: false, error: "Mandant nicht lesbar" });
  }
  if (!tenant) return reply(404, { ok: false, error: "Unbekannter Mandant" });

  const rawBody = await req.text();
  let payload: unknown = null;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    // kein JSON: nur raw_body speichern
  }

  const headers: Record<string, string> = {};
  req.headers.forEach((value, key) => {
    if (!SKIP_HEADERS.has(key.toLowerCase())) headers[key] = value;
  });

  const { error } = await supabase.from("webhook_events").upsert(
    {
      tenant_id: tenant.id,
      trigger: url.searchParams.get("trigger"),
      headers,
      payload,
      raw_body: rawBody,
      dedupe_key: await sha256Hex(rawBody),
    },
    { onConflict: "tenant_id,dedupe_key", ignoreDuplicates: true },
  );

  // Konnte nicht gespeichert werden: Fehler melden, damit nichts stillschweigend verloren geht
  if (error) {
    console.error("Speichern fehlgeschlagen", error);
    return reply(500, { ok: false, error: "Speichern fehlgeschlagen" });
  }

  return reply(200, { ok: true });
});
