// Liest die Schlüsseldateien auf Marcels Rechner (nie in Git, siehe .gitignore).
//   .env.local                 → Supabase-Zugang (gilt für alle Lehrerinnen)
//   .env.<kürzel>.local        → Schlüssel einer Lehrerin: FLENSKI_API_KEY, FLENSKI_SECRET_<TRIGGER>
// Werte werden nie ausgegeben.
import { existsSync, readFileSync } from "node:fs";

const root = new URL("../", import.meta.url);

function lesen(datei) {
  return Object.fromEntries(
    readFileSync(new URL(datei, root), "utf8")
      .split(/\r?\n/)
      .filter((l) => /^[A-Z_]+=/.test(l))
      .map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1).trim().replace(/^["']|["']$/g, "")]),
  );
}

export function adminEnv() {
  return lesen(".env.local");
}

export function lehrerinEnv(slug) {
  const kuerzel = String(slug || "").replace(/[^a-z0-9-]/gi, "");
  const datei = `.env.${kuerzel}.local`;
  if (!kuerzel || !existsSync(new URL(datei, root))) {
    console.error(`Schlüsseldatei ${datei} fehlt. Bitte im Projektordner anlegen (Vorlage: .env.lehrerin.example).`);
    process.exit(1);
  }
  return lesen(datei);
}
