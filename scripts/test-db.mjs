// Ersatz für "supabase test db" ohne Docker: führt supabase/tests/database/*.test.sql
// gegen das verknüpfte Projekt aus. Jede Testdatei endet mit rollback, es bleiben keine Testdaten zurück.
// Aufruf (im Projektordner): node scripts/test-db.mjs
import { readFileSync, readdirSync } from "node:fs";
// pg liegt (wie die Supabase-CLI) im nicht hochgeladenen Ordner .tools: cd .tools && npm install pg@8.13.1
import pg from "../.tools/node_modules/pg/lib/index.js";

const root = new URL("../", import.meta.url);
const env = Object.fromEntries(
  readFileSync(new URL(".env.local", root), "utf8")
    .split(/\r?\n/)
    .filter((l) => /^[A-Z_]+=/.test(l))
    .map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1).trim()]),
);

const client = new pg.Client({
  host: "aws-0-eu-west-1.pooler.supabase.com",
  port: 5432, // Session-Modus, damit "set local role" in der Transaktion wirkt
  user: `postgres.${env.SUPABASE_PROJECT_REF}`,
  password: env.SUPABASE_DB_PASSWORD,
  database: "postgres",
  ssl: { rejectUnauthorized: false },
});
await client.connect();

const dir = new URL("supabase/tests/database/", root);
let failed = 0;
for (const file of readdirSync(dir).filter((f) => f.endsWith(".test.sql")).sort()) {
  console.log(`# ${file}`);
  try {
    const results = [].concat(await client.query(readFileSync(new URL(file, dir), "utf8")));
    for (const r of results) {
      for (const row of r.rows ?? []) {
        for (const value of Object.values(row)) {
          if (typeof value !== "string") continue;
          for (const line of value.split("\n")) {
            if (/^(not ok|ok|1\.\.|#)/.test(line)) console.log(line);
            if (line.startsWith("not ok") || line.includes("Looks like you failed")) failed++;
          }
        }
      }
    }
  } catch (e) {
    failed++;
    console.log(`not ok - Datei bricht ab: ${e.message}`);
    await client.query("rollback").catch(() => {});
  }
}
await client.end();
console.log(failed ? `\nFEHLGESCHLAGEN (${failed})` : "\nAlle Tests grün.");
process.exit(failed ? 1 : 0);
