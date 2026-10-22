// Empfänger für Flenski-Automationen ("Webhook senden").
// Phase 0: speichert jede Anfrage unverändert in webhook_events, prüft die Flenski-Signatur und antwortet sofort mit 200.
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

function toHex(buffer: ArrayBuffer) {
  return Array.from(new Uint8Array(buffer), (b) => b.toString(16).padStart(2, "0")).join("");
}

async function sha256Hex(text: string) {
  return toHex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
}

async function hmacSha256Hex(secret: string, text: string) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return toHex(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(text)));
}

// Vergleich ohne frühen Abbruch, damit die Laufzeit nichts über den Schlüssel verrät
function sameText(a: string, b: string) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// Flenski: X-Flenski-Signature = "sha256=" + HMAC-SHA256(Schlüssel der Automation, Rohbody).
// null = kein Schlüssel hinterlegt. Der Knopf „Testen“ nutzt einen Einmalschlüssel und ergibt immer false.
async function checkSignature(tenantId: string, trigger: string | null, header: string | null, rawBody: string) {
  if (!trigger) return null;
  const { data, error } = await supabase
    .from("webhook_trigger_secrets")
    .select("secret")
    .eq("tenant_id", tenantId)
    .eq("trigger", trigger)
    .maybeSingle();
  if (error) console.error("Schlüssel nicht lesbar", error);
  if (!data) return null;
  if (!header) return false;
  return sameText(header, "sha256=" + await hmacSha256Hex(data.secret, rawBody));
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

  const trigger = url.searchParams.get("trigger");

  const { error } = await supabase.from("webhook_events").upsert(
    {
      tenant_id: tenant.id,
      trigger,
      headers,
      payload,
      raw_body: rawBody,
      // Auch bei falscher Signatur speichern (Regel 4); verarbeitet werden in Phase 3 nur gültige
      signature_valid: await checkSignature(tenant.id, trigger, req.headers.get("x-flenski-signature"), rawBody),
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
