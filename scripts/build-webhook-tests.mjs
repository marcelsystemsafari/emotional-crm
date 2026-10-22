// Erzeugt Datenbank-Tests aus den echten Beispiel-Payloads (inbox/webhooks/*.json).
// In der Vorlage steht {{trigger}}, das wird durch den Payload als jsonb ersetzt.
// Aufruf (im Projektordner): node scripts/build-webhook-tests.mjs
import { readFileSync, writeFileSync, readdirSync } from "node:fs";

const root = new URL("../", import.meta.url);
const templates = new URL("supabase/tests/fixtures/", root);

for (const file of readdirSync(templates).filter((f) => f.endsWith(".template.sql"))) {
  const sql = readFileSync(new URL(file, templates), "utf8").replace(/\{\{([a-z0-9-]+)\}\}/g, (_, trigger) => {
    const json = JSON.stringify(JSON.parse(readFileSync(new URL(`inbox/webhooks/${trigger}.json`, root), "utf8")));
    return `($payload$${json}$payload$::jsonb)`;
  });
  const out = file.replace(".template.sql", ".test.sql");
  writeFileSync(new URL(`supabase/tests/database/${out}`, root),
    `-- ERZEUGT aus supabase/tests/fixtures/${file} – nicht von Hand bearbeiten (node scripts/build-webhook-tests.mjs)\n${sql}`);
  console.log(`erzeugt: supabase/tests/database/${out}`);
}
