// Hinterlegt die Make-Adresse (Szenario "ECRM: Flenski-Aktionen" der Lehrerin) und ihr Flenski-Projekt im CRM.
// Aufruf: node scripts/setup-make.mjs <slug> <flenski-projekt-id> <make-webhook-url> [an|aus]
//   an  = automatischer Plan-Entzug/-Rückgabe eingeschaltet (Standard)
//   aus = Adresse nur für die vollständige Teilnehmerliste, Pläne entzieht die Lehrerin selbst
// Die Make-Adresse wird nicht ausgegeben. Mehrfach ausführbar.
import { readFileSync } from "node:fs";

const env = Object.fromEntries(
  readFileSync(new URL("../.env.local", import.meta.url), "utf8")
    .split(/\r?\n/)
    .filter((l) => /^[A-Z_]+=/.test(l))
    .map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1).trim()]),
);
const [slug, projectId, url, modus = "an"] = process.argv.slice(2);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
if (!slug || !UUID.test(projectId || "") || !/^https:\/\/hook\.[a-z0-9]+\.make\.com\/[a-z0-9]+$/i.test(url || "")) {
  console.error("Aufruf: node scripts/setup-make.mjs <slug> <flenski-projekt-id> <make-webhook-url> [an|aus]");
  process.exit(1);
}

async function sql(query) {
  const res = await fetch(`https://api.supabase.com/v1/projects/${env.SUPABASE_PROJECT_REF}/database/query`, {
    method: "POST",
    headers: { Authorization: `Bearer ${env.SUPABASE_ACCESS_TOKEN}`, "Content-Type": "application/json" },
    body: JSON.stringify({ query }),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`SQL-Fehler ${res.status}: ${text.slice(0, 300)}`);
  return JSON.parse(text);
}

const s = slug.replace(/[^a-z0-9-]/gi, "");
const r = await sql(`
  update public.tenant_secrets ts set make_webhook_url = '${url}'
  from public.tenants t where t.id = ts.tenant_id and t.slug = '${s}' returning t.id;`);
if (!r.length) {
  console.error("Mandantin nicht gefunden oder Flenski-Abgleich noch nicht eingerichtet (zuerst setup-flenski-sync.mjs).");
  process.exit(1);
}
await sql(`update public.tenants set settings = settings || jsonb_build_object('flenski_project_id', '${projectId}',
  'plan_entzug_automatisch', ${modus === "aus" ? "false" : "true"}) where slug = '${s}';`);
console.log(`Make für ${s} hinterlegt, automatischer Plan-Entzug: ${modus === "aus" ? "aus" : "an"}.`);
