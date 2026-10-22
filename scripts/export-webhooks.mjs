// Legt pro Trigger das neueste Webhook-Ereignis aus webhook_events anonymisiert in inbox/webhooks/ ab:
//   <trigger>.json          Body (Personendaten und Beitragsinhalte ersetzt)
//   <trigger>.headers.txt   Header
// Diese Dateien sind die Grundlage für Prüfschemas und Test-Fixtures (CLAUDE.md, Regel 5).
// Aufruf (im Projektordner): node scripts/export-webhooks.mjs
import { readFileSync, writeFileSync } from "node:fs";

const root = new URL("../", import.meta.url);
const env = Object.fromEntries(
  readFileSync(new URL(".env.local", root), "utf8")
    .split(/\r?\n/)
    .filter((l) => /^[A-Z_]+=/.test(l))
    .map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1).trim()]),
);

async function sql(query) {
  const res = await fetch(`https://api.supabase.com/v1/projects/${env.SUPABASE_PROJECT_REF}/database/query`, {
    method: "POST",
    headers: { Authorization: `Bearer ${env.SUPABASE_ACCESS_TOKEN}`, "Content-Type": "application/json" },
    body: JSON.stringify({ query }),
  });
  if (!res.ok) throw new Error(`Fehler ${res.status}: ${await res.text()}`);
  return res.json();
}

// Ersetzungen nach Feldname. Titel von Kursen, Events, Plänen usw. bleiben stehen (keine Personendaten).
const REPLACE = {
  email: "erika.muster@example.com",
  fullName: "Erika Muster",
  firstName: "Erika",
  lastName: "Muster",
  phone: "+49 151 00000000",
  bio: "[entfernt]",
  headline: "[entfernt]",
  originalName: "beispiel.jpg",
  text: "<div>[Inhalt entfernt]</div>",
  message: "[Inhalt entfernt]",
};

function anonymize(value, parent) {
  if (Array.isArray(value)) return value.map((v) => anonymize(v, parent));
  if (!value || typeof value !== "object") return value;
  const out = {};
  for (const [key, v] of Object.entries(value)) {
    if (v !== null && typeof v === "string" && key in REPLACE) out[key] = REPLACE[key];
    else if (key === "url" && typeof v === "string" && v.startsWith("https://cdn.flenski.io/")) out[key] = "https://cdn.flenski.io/beispiel.jpg";
    // Bei Kommentaren ist der Titel des Ziel-Beitrags dessen Textanfang
    else if (key === "title" && parent === "target" && value.type === "post") out[key] = "[Beitragsanfang entfernt]";
    else out[key] = anonymize(v, key);
  }
  return out;
}

const rows = await sql(`
  select distinct on (trigger) trigger, headers, payload, raw_body,
         headers->>'baggage' like '%webhook_test%' as test_knopf, received_at
  from webhook_events where trigger is not null
  order by trigger, received_at desc`);

for (const r of rows) {
  const body = r.payload ? JSON.stringify(anonymize(r.payload), null, 2) : r.raw_body;
  writeFileSync(new URL(`inbox/webhooks/${r.trigger}.json`, root), body + "\n");
  const headers = Object.entries(r.headers).sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => `${k}: ${v}`);
  const note = `# Empfangen ${r.received_at} · ${r.test_knopf ? "über den Knopf „Testen“ in Flenski (Beispieldaten)" : "echtes Ereignis"}`;
  writeFileSync(new URL(`inbox/webhooks/${r.trigger}.headers.txt`, root), [note, ...headers].join("\n") + "\n");
  console.log(`${r.test_knopf ? "TEST" : "ECHT"}  ${r.trigger}`);
}
