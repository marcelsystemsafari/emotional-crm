// Richtet den automatischen Flenski-Abgleich für eine Mandantin ein (Entscheidung 0006).
// Aufruf: node scripts/setup-flenski-sync.mjs <slug> <flenski-app-id>
//   - prüft den Schlüssel FLENSKI_API_KEY aus .env.local direkt bei Flenski,
//   - speichert ihn in tenant_secrets und die App-ID in tenants.settings,
//   - legt das Geheimnis für den 5-Minuten-Takt an (Supabase-Secret SYNC_SECRET + Vault ecrm_sync_secret, ecrm_project_url).
// Gibt keinen Schlüssel aus. Mehrfach ausführbar.
import { readFileSync } from "node:fs";
import { randomBytes } from "node:crypto";

const env = Object.fromEntries(
  readFileSync(new URL("../.env.local", import.meta.url), "utf8")
    .split(/\r?\n/)
    .filter((l) => /^[A-Z_]+=/.test(l))
    .map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1).trim().replace(/^["']|["']$/g, "")]),
);
const [slug, appId] = process.argv.slice(2);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
if (!slug || !UUID.test(appId || "")) {
  console.error("Aufruf: node scripts/setup-flenski-sync.mjs <slug> <flenski-app-id>");
  process.exit(1);
}
const apiKey = env.FLENSKI_API_KEY;
if (!apiKey || /['$\\]/.test(apiKey)) {
  console.error("FLENSKI_API_KEY fehlt in .env.local oder enthält unerlaubte Zeichen.");
  process.exit(1);
}

const api = `https://api.supabase.com/v1/projects/${env.SUPABASE_PROJECT_REF}`;
const auth = { Authorization: `Bearer ${env.SUPABASE_ACCESS_TOKEN}`, "Content-Type": "application/json" };
async function sql(query) {
  const res = await fetch(`${api}/database/query`, { method: "POST", headers: auth, body: JSON.stringify({ query }) });
  const text = await res.text();
  if (!res.ok) throw new Error(`SQL-Fehler ${res.status}: ${text.slice(0, 300)}`);
  return JSON.parse(text);
}

// 1. Schlüssel bei Flenski prüfen
const probe = await fetch(`https://app.flenski.io/api/v1/apps/${appId}/events?page=1&limit=1`, {
  headers: { "X-API-KEY": apiKey, Accept: "application/json" },
});
if (!probe.ok) {
  console.error(`Flenski lehnt den Schlüssel für diese App ab (Status ${probe.status}).`);
  process.exit(1);
}
console.log("Flenski-Schlüssel gültig für die App.");

// 2. Schlüssel und App-ID bei der Mandantin speichern
const t = await sql(`select id from public.tenants where slug = '${slug.replace(/'/g, "")}'`);
if (!t.length) { console.error("Mandantin nicht gefunden: " + slug); process.exit(1); }
await sql(`
  update public.tenants set settings = settings || jsonb_build_object('flenski_app_id', '${appId}') where id = '${t[0].id}';
  insert into public.tenant_secrets (tenant_id, flenski_api_key) values ('${t[0].id}', $k$${apiKey}$k$)
  on conflict (tenant_id) do update set flenski_api_key = excluded.flenski_api_key, updated_at = now();`);
console.log("Schlüssel und App-ID bei " + slug + " gespeichert.");

// 3. Geheimnis für den Takt (nur einmal erzeugen, danach wiederverwenden)
const vorhanden = await sql(`select count(*)::int as n from vault.secrets where name = 'ecrm_sync_secret'`);
if (!vorhanden[0].n) {
  const syncSecret = randomBytes(32).toString("hex");
  const res = await fetch(`${api}/secrets`, { method: "POST", headers: auth, body: JSON.stringify([{ name: "SYNC_SECRET", value: syncSecret }]) });
  if (!res.ok) throw new Error(`Supabase-Secret nicht gesetzt (${res.status})`);
  await sql(`select vault.create_secret($s$${syncSecret}$s$, 'ecrm_sync_secret');`);
  console.log("Takt-Geheimnis angelegt (Supabase-Secret + Vault).");
} else {
  console.log("Takt-Geheimnis gibt es schon.");
}
const url = await sql(`select count(*)::int as n from vault.secrets where name = 'ecrm_project_url'`);
if (!url[0].n) {
  await sql(`select vault.create_secret($u$${env.SUPABASE_URL}$u$, 'ecrm_project_url');`);
  console.log("Projekt-Adresse im Vault hinterlegt.");
}
console.log("Fertig. Der Abgleich läuft ab jetzt alle 5 Minuten.");
