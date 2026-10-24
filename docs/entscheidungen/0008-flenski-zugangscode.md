# 0008 – Anmeldung bei Flenski mit Zugangscode und automatischer Erneuerung

**Datum:** 24.10.2026 · **Entschieden von:** Marcel

## Kontext
Der 36-stellige „API Key“ aus den Flenski-Profil-Einstellungen wird von der Flenski-Schnittstelle nicht erkannt (getestet mit allen üblichen Methoden). Bei Lana fiel das nicht auf, weil ihre App öffentlich ist. Bei Ninas App („nur mit Anmeldung“) kamen keine Termine und nur öffentliche Profilfelder. Ein freigegebener Test hat gezeigt: Marcels Make-Schlüsselbund schickt `Authorization: Bearer <Zugangscode>` – den Code einer eingeloggten Flenski-Sitzung (JWT). Flenski erneuert solche Codes mit einem Erneuerungscode über `POST /api/v1/auth/refresh-token {refreshToken}`.

## Entscheidung
- Der Server meldet sich mit einem **Zugangscode** an (`tenant_secrets.flenski_auth`), aus Marcels eingeloggter Flenski-Sitzung (Browser → F12 → Netzwerk → `authorization: Bearer …`).
- Dazu der **Erneuerungscode** (`tenant_secrets.flenski_refresh`, Browser-Cookie `refreshToken`). `flenski-sync` erneuert den Zugangscode selbst, wenn er in weniger als 14 Tagen abläuft. Fehler werden in `flenski_auth_fehler` vermerkt.
- Empfehlung: für das CRM eine **eigene Sitzung** anlegen (privates Browserfenster, einloggen, beide Codes kopieren, Fenster schließen ohne Abmelden), damit Marcels normale Sitzung unberührt bleibt.
- Ablage nur in `.env.<kürzel>.local` (Übergabe) und `tenant_secrets` (nur Server). Nie im Chat, nie in Git.

## Folgen
- Funktioniert auch für Apps mit Anmeldung (Nina: 83 Termine, 22 Profile mit ID/E-Mail).
- Mit demselben Zugang wären Plan entziehen/zuweisen und Teilnehmerlisten ohne Make möglich – Make (Entscheidung 0007) kann später entfallen; vorher prüfen.
- Risiko: Der Code hat die Rechte von Marcels Konto. Abmelden in Flenski (bewusst) kann ihn ungültig machen → Hinweis im CRM nötig.
- Nicht offiziell dokumentiert; ändert Flenski die Anmeldung, muss das angepasst werden.
