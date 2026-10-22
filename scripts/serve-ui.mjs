// Zeigt ui/crm.html lokal unter http://localhost:4173 an – zum Testen ohne Flenski.
// Die Seite spricht mit der echten Supabase-Datenbank; zum Ausprobieren CRM_CONFIG auf die Demo stellen:
//   http://localhost:4173/?tenant=yoga-by-lana-demo
// Aufruf (im Projektordner): node scripts/serve-ui.mjs
import { createServer } from "node:http";
import { readFileSync } from "node:fs";

const file = new URL("../ui/crm.html", import.meta.url);
const port = Number(process.env.PORT) || 4173;

createServer((req, res) => {
  const url = new URL(req.url, `http://localhost:${port}`);
  if (url.pathname !== "/") {
    res.writeHead(404).end();
    return;
  }
  const tenant = (url.searchParams.get("tenant") || "").replace(/[^a-z0-9-]/g, "");
  let html = readFileSync(file, "utf8");
  if (tenant) html = html.replace(/window\.CRM_CONFIG = \{ tenant: "[^"]*" \};/, `window.CRM_CONFIG = { tenant: "${tenant}" };`);
  // Flenski-ähnlicher Rahmen: beiger Hintergrund, Seitenrand
  const page = `<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>CRM lokal</title></head><body style="margin:0;background:#f5efe6;font-family:system-ui,sans-serif;padding:16px">${html}</body></html>`;
  res.writeHead(200, { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" }).end(page);
}).listen(port, () => console.log(`CRM lokal: http://localhost:${port}/?tenant=yoga-by-lana-demo`));
