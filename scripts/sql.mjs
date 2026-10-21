// Führt SQL gegen das verknüpfte Supabase-Projekt aus (Management-API).
// Aufruf: node scripts/sql.mjs "select 1"   oder   node scripts/sql.mjs -f datei.sql
// Liest SUPABASE_ACCESS_TOKEN und SUPABASE_PROJECT_REF aus .env.local und gibt sie nie aus.
import { readFileSync } from "node:fs";

const env = Object.fromEntries(
  readFileSync(new URL("../.env.local", import.meta.url), "utf8")
    .split(/\r?\n/)
    .filter((l) => /^[A-Z_]+=/.test(l))
    .map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1).trim()]),
);

const args = process.argv.slice(2);
const query = args[0] === "-f" ? readFileSync(args[1], "utf8") : args.join(" ");

const res = await fetch(
  `https://api.supabase.com/v1/projects/${env.SUPABASE_PROJECT_REF}/database/query`,
  {
    method: "POST",
    headers: { Authorization: `Bearer ${env.SUPABASE_ACCESS_TOKEN}`, "Content-Type": "application/json" },
    body: JSON.stringify({ query }),
  },
);
const text = await res.text();
if (!res.ok) {
  console.error(`Fehler ${res.status}: ${text}`);
  process.exit(1);
}
console.log(JSON.stringify(JSON.parse(text), null, 2));
