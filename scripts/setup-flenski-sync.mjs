// Richtet den automatischen Flenski-Abgleich für eine Mandantin ein (Entscheidungen 0006, 0008).
// Aufruf: node scripts/setup-flenski-sync.mjs <slug> <flenski-app-id>
//   - liest aus .env.<kürzel>.local den Zugangscode FLENSKI_AUTH (Bearer-Code einer eingeloggten Flenski-Sitzung)
//     und den Erneuerungscode FLENSKI_REFRESH; ohne FLENSKI_AUTH alter Weg FLENSKI_API_KEY (nur öffentliche Apps),
//   - prüft den Zugang direkt bei Flenski (Termine der App),
//   - speichert alles in tenant_secrets und die App-ID in tenants.settings,
//   - legt das Geheimnis für den 5-Minuten-Takt an (Supabase-Secret SYNC_SECRET + Vault ecrm_sync_secret, ecrm_project_url).
// Gibt keinen Schlüssel aus. Mehrfach ausführbar.
import { randomBytes } from "node:crypto";
import { adminEnv, lehrerinEnv } from "./env.mjs";

const env = adminEnv();
const [slug, appId] = process.argv.slice(2);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
if (!slug || !UUID.test(appId || "")) {
  console.error("Aufruf: node scripts/setup-flenski-sync.mjs <slug> <flenski-app-id>");
  process.exit(1);
}
const lehrerin = lehrerinEnv(slug);
const zugang = (lehrerin.FLENSKI_AUTH || "").replace(/^Bearer\s+/i, "");
const erneuerung = lehrerin.FLENSKI_REFRESH || "";
const apiKey = lehrerin.FLENSKI_API_KEY || "";
for (const [name, wert] of [["FLENSKI_AUTH", zugang], ["FLENSKI_REFRESH", erneuerung], ["FLENSKI_API_KEY", apiKey]]) {
  if (/['$\\\s]/.test(wert)) { console.error(name + " enthält unerlaubte Zeichen."); process.exit(1); }
}
if (!zugang && !apiKey) {
  console.error("Weder FLENSKI_AUTH noch FLENSKI_API_KEY in .env." + slug + ".local.");
  process.exit(1);
}
function ablauf(code) {
  try { const p = JSON.parse(Buffer.from(code.split(".")[1], "base64url").toString()); return p.exp ? new Date(p.exp * 1000).toISOString() : null; }
  catch { return null; }
}

const api = `https://api.supabase.com/v1/projects/${env.SUPABASE_PROJECT_REF}`;
const auth = { Authorization: `Bearer ${env.SUPABASE_ACCESS_TOKEN}`, "Content-Type": "application/json" };
async function sql(query) {
  const res = await fetch(`${api}/database/query`, { method: "POST", headers: auth, body: JSON.stringify({ query }) });
  const text = await res.text();
  if (!res.ok) throw new Error(`SQL-Fehler ${res.status}: ${text.slice(0, 300)}`);
  return JSON.parse(text);
}
const q = (v) => (v ? `$k$${v}$k$` : "null");

// 1. Zugang bei Flenski prüfen
const probe = await fetch(`https://app.flenski.io/api/v1/apps/${appId}/events?page=1&limit=1`, {
  headers: zugang ? { Authorization: `Bearer ${zugang}`, Accept: "application/json" } : { "X-API-KEY": apiKey, Accept: "application/json" },
});
if (!probe.ok) {
  console.error(`Flenski lehnt den Zugang für diese App ab (Status ${probe.status}).`);
  process.exit(1);
}
const exp = zugang ? ablauf(zugang) : null;
console.log("Flenski-Zugang gültig für die App" + (exp ? ", Zugangscode läuft ab am " + exp.slice(0, 10) : "") + (erneuerung ? ", automatische Erneuerung eingerichtet." : "."));

// 2. Zugang und App-ID bei der Mandantin speichern
const t = await sql(`select id from public.tenants where slug = '${slug.replace(/'/g, "")}'`);
if (!t.length) { console.error("Mandantin nicht gefunden: " + slug); process.exit(1); }
await sql(`
  update public.tenants set settings = settings || jsonb_build_object('flenski_app_id', '${appId}') where id = '${t[0].id}';
  insert into public.tenant_secrets (tenant_id, flenski_api_key, flenski_auth, flenski_refresh, flenski_auth_expires, flenski_auth_fehler)
  values ('${t[0].id}', ${q(apiKey)}, ${q(zugang)}, ${q(erneuerung)}, ${exp ? `'${exp}'` : "null"}, null)
  on conflict (tenant_id) do update set flenski_api_key = excluded.flenski_api_key, flenski_auth = excluded.flenski_auth,
    flenski_refresh = excluded.flenski_refresh, flenski_auth_expires = excluded.flenski_auth_expires,
    flenski_auth_fehler = null, updated_at = now();`);
console.log("Zugang und App-ID bei " + slug + " gespeichert.");

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
