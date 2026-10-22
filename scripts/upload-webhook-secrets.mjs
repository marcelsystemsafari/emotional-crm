// Überträgt die Flenski-Schlüssel (FLENSKI_SECRET_<TRIGGER>=...) aus .env.local in webhook_trigger_secrets.
// Der Trigger ergibt sich aus dem Namen: FLENSKI_SECRET_ARTIKEL_GELESEN → artikel-gelesen (wie ?trigger= in der URL).
// Gibt nur Triggernamen aus, nie Schlüssel. Leere Zeilen werden übersprungen, vorhandene Schlüssel ersetzt.
// Aufruf (im Projektordner): node scripts/upload-webhook-secrets.mjs [mandanten-slug]   (Standard: yoga-by-lana)
import { readFileSync } from "node:fs";

const root = new URL("../", import.meta.url);
const env = Object.fromEntries(
  readFileSync(new URL(".env.local", root), "utf8")
    .split(/\r?\n/)
    .filter((l) => /^[A-Z_]+=/.test(l))
    .map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1).trim()]),
);
const tenant = process.argv[2] ?? "yoga-by-lana";

const secrets = Object.entries(env)
  .filter(([k, v]) => k.startsWith("FLENSKI_SECRET_") && v)
  .map(([k, v]) => [k.slice("FLENSKI_SECRET_".length).toLowerCase().replaceAll("_", "-"), v]);

for (const [trigger, secret] of secrets) {
  if (!/^[A-Za-z0-9_-]+$/.test(secret)) {
    console.error(`Schlüssel für ${trigger} enthält unerwartete Zeichen – bitte in .env.local prüfen.`);
    process.exit(1);
  }
}
if (!/^[a-z0-9-]+$/.test(tenant)) throw new Error("Ungültiger Mandanten-Slug");

const values = secrets.map(([t, s]) => `('${t}', '${s}')`).join(",\n");
const query = `
  insert into public.webhook_trigger_secrets (tenant_id, trigger, secret)
  select t.id, v.trigger, v.secret
  from public.tenants t, (values ${values}) as v(trigger, secret)
  where t.slug = '${tenant}'
  on conflict (tenant_id, trigger) do update set secret = excluded.secret
  returning trigger`;

const res = await fetch(`https://api.supabase.com/v1/projects/${env.SUPABASE_PROJECT_REF}/database/query`, {
  method: "POST",
  headers: { Authorization: `Bearer ${env.SUPABASE_ACCESS_TOKEN}`, "Content-Type": "application/json" },
  body: JSON.stringify({ query }),
});
if (!res.ok) {
  console.error(`Fehler ${res.status}`);
  process.exit(1);
}
const rows = await res.json();
console.log(`${rows.length} Schlüssel für ${tenant} gespeichert: ${rows.map((r) => r.trigger).sort().join(", ")}`);
