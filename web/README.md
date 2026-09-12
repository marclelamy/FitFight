# FitFight API (Next.js)

iOS command API only. No marketing pages. Node.js runtime, never Edge.

## Marc — Vercel

1. Create a Vercel project on this GitHub repo.
2. Set **Root Directory** to `web/`.
3. Env vars (Vercel dashboard only — never paste secrets in git or chat):

| Vercel env | Preview + `develop` | Production (`main`) |
| --- | --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase **develop** project URL | Main / production project URL |
| `SUPABASE_SECRET_KEY` | develop secret key | production secret key |
| `DATABASE_URL` | develop transaction-pooler URL | production transaction-pooler URL |
| `FITFIGHT_APP_URL` | staging site origin (optional) | production site origin (optional) |
| `APPLE_SIGN_IN_TEAM_ID` | Apple developer Team ID | same Team ID |
| `APPLE_SIGN_IN_KEY_ID` | Sign in with Apple key ID | same key ID |
| `APPLE_SIGN_IN_PRIVATE_KEY` | Sign in with Apple `.p8` contents | same key, or its production replacement |
| `APPLE_SIGN_IN_CLIENT_ID` | `com.fitfight.mvp` | `com.fitfight.mvp` |
| `APPLE_SIGN_IN_TOKEN_ENCRYPTION_KEY` | separate base64 32-byte key | separate base64 32-byte key |
| `NOTION_TOKEN` | Notion internal integration token with access to Product Backlog | same token |
| `CURSOR_API_KEY` | Cursor Cloud Agents API key (Dashboard → API Keys) for admin “Send to Cursor” | same key |

Preview deployments must use the **develop** Supabase project. Never point Preview at production.
The Sign in with Apple key must be enabled for the FitFight App ID. It is not the
App Store Connect API key. Keep the staging and production token-encryption keys stable,
because changing one makes already stored revocation tokens unreadable.

Use Supavisor transaction mode (port `6543`) for `DATABASE_URL`, with prepared statements disabled by the backend. The password stays in Vercel. The `private` schema does not need to be exposed through the Data API.

After a `web/` push, Vercel deploys. iOS uses the User JWT as `Authorization: Bearer <jwt>`.

## Local

```bash
cp .env.example .env.local
# fill URL, secret, and pooled database URL from the develop project
npm install
npm run dev
```

- `GET /api/health` → `{ "ok": true }`
- Commands live under `/api/v1/...` (see `contracts/openapi.yaml`)

```bash
npm run typecheck
npm test
```
