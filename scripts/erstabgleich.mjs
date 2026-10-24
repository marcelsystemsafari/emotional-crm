// Erstabgleich einer Mandantin: übernimmt Mitglieder (mit Plänen) und die kommenden Termine aus Flenski.
// Aufruf: node scripts/erstabgleich.mjs <kürzel>
// Nutzt den Zugang aus .env.<kürzel>.local (FLENSKI_AUTH, sonst FLENSKI_API_KEY). Mehrfach ausführbar
// (import_flenski_snapshot legt nichts doppelt an). Gibt keine personenbezogenen Daten aus, nur Zahlen.
import { adminEnv, lehrerinEnv } from "./env.mjs";

const env = adminEnv();
const slug = (process.argv[2] || "").replace(/[^a-z0-9-]/gi, "");
if (!slug) { console.error("Aufruf: node scripts/erstabgleich.mjs <kürzel>"); process.exit(1); }
const l = lehrerinEnv(slug);
const zugang = (l.FLENSKI_AUTH || "").replace(/^Bearer\s+/i, "");
const kopf = zugang ? { Authorization: `Bearer ${zugang}`, Accept: "application/json" } : { "X-API-KEY": l.FLENSKI_API_KEY || "", Accept: "application/json" };

async function sql(query) {
  const res = await fetch(`https://api.supabase.com/v1/projects/${env.SUPABASE_PROJECT_REF}/database/query`, {
    method: "POST", headers: { Authorization: `Bearer ${env.SUPABASE_ACCESS_TOKEN}`, "Content-Type": "application/json" }, body: JSON.stringify({ query }),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`SQL-Fehler ${res.status}: ${text.slice(0, 300)}`);
  return JSON.parse(text);
}
async function alle(pfad) {
  const liste = [];
  for (let page = 1; page <= 50; page++) {
    const res = await fetch(`https://app.flenski.io/api/v1${pfad}?page=${page}&limit=100`, { headers: kopf });
    if (!res.ok) throw new Error(`Flenski ${pfad}: ${res.status}`);
    const body = await res.json();
    liste.push(...(body.data || []));
    if (page >= (body.meta?.pagination?.pages ?? 1)) break;
  }
  return liste;
}

const t = await sql(`select id, settings->>'flenski_app_id' as app from public.tenants where slug = '${slug}'`);
if (!t.length || !t[0].app) { console.error("Mandantin oder App-ID fehlt: " + slug); process.exit(1); }
const appId = t[0].app;

const profile = await alle(`/apps/${appId}/profiles`);
if (profile.length && profile[0].id === undefined) {
  console.error("Flenski liefert nur die öffentliche Ansicht (ohne IDs) – Zugang prüfen.");
  process.exit(1);
}
const plaene = new Map();
const members = profile.map((p) => {
  for (const pl of p.plans || []) plaene.set(pl.id, { id: pl.id, name: pl.name });
  return {
    id: p.id, fullName: p.fullName, firstName: p.firstName, lastName: p.lastName, email: p.email, createdAt: p.createdAt,
    isAdmin: p.isAdmin, isMemberOfTeam: p.isMemberOfTeam, avatar: p.avatar?.url ? { url: p.avatar.url } : null,
    tags: (p.tags || []).map((x) => (typeof x === "string" ? x : x.name)).filter(Boolean),
    plans: (p.plans || []).map((x) => x.name),
  };
});
const jetzt = Date.now();
const events = (await alle(`/apps/${appId}/events`))
  .filter((e) => new Date(e.startsAtUtc || e.startsAt).getTime() >= jetzt)
  .map((e) => ({
    id: e.id, title: e.title || e.name, frontendUrl: e.frontendUrl, startsAt: e.startsAtUtc || e.startsAt, endsAt: e.endsAtUtc || e.endsAt,
    timeZone: e.timeZone, category: e.category ? { name: e.category.name } : null, participantsNumberLimit: e.participantsNumberLimit,
    lastAttended: (e.lastAttended || []).map((x) => ({ id: x.id })),
  }));

const daten = JSON.stringify({ members, plans: [...plaene.values()], events });
if (daten.includes("$flenski$")) throw new Error("Unerwartete Zeichenfolge in den Daten");
const r = await sql(`select public.import_flenski_snapshot('${t[0].id}', $flenski$${daten}$flenski$::jsonb) as ergebnis`);
console.log("Aus Flenski:", members.length, "Profile,", plaene.size, "Pläne,", events.length, "kommende Termine");
console.log("Übernommen:", JSON.stringify(r[0].ergebnis));
