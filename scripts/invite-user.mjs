// Lädt eine Person ins CRM ein (die offene Registrierung ist geschlossen, Entscheidung in docs/phase1-plan.md).
// Legt den Login an, falls es ihn noch nicht gibt, und ordnet die Person einer Mandantin mit Rolle zu.
// Anmelden kann sie sich danach selbst per E-Mail-Code.
//
// Aufruf (im Projektordner):
//   node scripts/invite-user.mjs <email> <mandanten-slug> <owner|staff>
//   node scripts/invite-user.mjs <email> --platform-admin
import { readFileSync } from "node:fs";

const env = Object.fromEntries(
  readFileSync(new URL("../.env.local", import.meta.url), "utf8")
    .split(/\r?\n/)
    .filter((l) => /^[A-Z_]+=/.test(l))
    .map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1).trim()]),
);
const ref = env.SUPABASE_PROJECT_REF;
const mgmt = { Authorization: `Bearer ${env.SUPABASE_ACCESS_TOKEN}`, "Content-Type": "application/json" };

const [email, tenant, role] = process.argv.slice(2).map((a) => a?.trim());
if (!email?.includes("@") || !tenant || (tenant !== "--platform-admin" && !["owner", "staff"].includes(role))) {
  console.error("Aufruf: node scripts/invite-user.mjs <email> <mandanten-slug> <owner|staff>  oder  <email> --platform-admin");
  process.exit(1);
}
const lit = (s) => `'${s.replaceAll("'", "''")}'`;

async function sql(query) {
  const res = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
    method: "POST", headers: mgmt, body: JSON.stringify({ query }),
  });
  if (!res.ok) throw new Error(`SQL-Fehler ${res.status}: ${await res.text()}`);
  return res.json();
}

let [user] = await sql(`select id from auth.users where lower(email) = lower(${lit(email)})`);
if (!user) {
  // Service-Role-Schlüssel nur im Speicher holen, nie anzeigen oder speichern
  const keys = await (await fetch(`https://api.supabase.com/v1/projects/${ref}/api-keys?reveal=true`, { headers: mgmt })).json();
  const service = keys.find((k) => k.name === "service_role")?.api_key;
  const res = await fetch(`https://${ref}.supabase.co/auth/v1/admin/users`, {
    method: "POST",
    headers: { apikey: service, Authorization: `Bearer ${service}`, "Content-Type": "application/json" },
    body: JSON.stringify({ email, email_confirm: true }),
  });
  if (!res.ok) throw new Error(`Login anlegen fehlgeschlagen: ${res.status} ${await res.text()}`);
  user = await res.json();
  console.log(`Login angelegt für ${email}`);
}

if (tenant === "--platform-admin") {
  await sql(`insert into public.platform_admins (user_id) values (${lit(user.id)}) on conflict do nothing`);
  console.log(`${email} ist Plattform-Admin (sieht alle Mandantinnen).`);
} else {
  const rows = await sql(`
    insert into public.tenant_members (tenant_id, user_id, role)
    select id, ${lit(user.id)}, ${lit(role)} from public.tenants where slug = ${lit(tenant)}
    on conflict (tenant_id, user_id) do update set role = excluded.role
    returning id`);
  if (!rows.length) throw new Error(`Mandantin ${tenant} nicht gefunden`);
  console.log(`${email} ist jetzt ${role} bei ${tenant}. Anmelden per E-Mail-Code.`);
}
