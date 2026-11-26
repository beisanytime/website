# Beis Anytime API worker

One Cloudflare Worker now backs the whole product. It is deployed as `beis-api`
(`https://beis-api.beisanytime.workers.dev`) and the site and apps call it at
**`https://api.beisanytime.com`**.

`worker/index.js` is self-contained — the Google ID-token verifier lives in the same
file — so it can be deployed with `wrangler` or pasted into the dashboard.

## Routes

Library and media
- `GET /api/all-shiurim` — R2 library merged with the legacy KV library
- `GET /api/shiurim/id/:id` — one shiur
- `GET|HEAD /api/video-proxy?key=…` — serves videos/thumbnails from R2 (Range aware)

Admin (require `X-Upload-Password` **and** a verified admin Google ID token)
- `POST /api/admin/prepare-upload`, `PUT /api/admin/upload-part`, `POST /api/admin/complete-upload`, `POST /api/admin/abort-upload`
- `PUT /api/upload-proxy` (thumbnail)
- `GET /api/admin/shiurim`, `DELETE /api/admin/shiurim/:id`
- `POST /api/admin/refresh-thumbnails`, `POST /api/admin/cleanup-malformed-thumbnails`
- `GET /api/admin/upload-logs`
- `GET /api/debug-r2`

Social
- `GET /api/views/:id`, `POST /api/views/increment` `{ id }`
- `GET /api/likes/:id`, `POST /api/likes/:id` (toggle; signed in)
- `GET /api/comments/:id`, `POST /api/comments/:id` `{ text }` (signed in)
- `DELETE /api/comments/:id/:commentId` (admin)
- `GET /api/users/:email`, `PUT /api/users/:email` `{ displayName }` (self or admin)
- `POST /api/ban` `{ email }` (admin)

Community feed (D1)
- `GET /api/posts`, `POST /api/posts` `{ content }` (admin), `DELETE /api/posts/:id` (admin)

Everything else is proxied to the legacy worker at `beis-anytime-api` (with credentials
and identity headers stripped).

## Identity

Callers send their Google ID token as `Authorization: Bearer <id_token>`. The worker
verifies the RS256 signature against Google's JWKS and checks issuer, audience,
expiry and the verified-email claim before trusting the email. `X-User-Email` is
ignored everywhere — it used to be spoofable.

Admin access on the library/upload routes needs the upload password plus a verified
admin identity. Social admin actions (delete comment, ban) accept a verified admin
identity or the optional `ADMIN_API_KEY` secret in `X-Admin-Key`.

## Bindings to create

| Binding | Type | Used for |
| --- | --- | --- |
| `NEW_VIDEO_BUCKET` | R2 | library videos and thumbnails |
| `DB` | D1 | community posts (`posts` table) |
| `VIEWS_KV` | KV | view counts |
| `LIKES_KV` | KV | likes per shiur |
| `COMMENTS_KV` | KV | comments per shiur |
| `USERS_KV` | KV | display names |
| `BANS_KV` | KV | banned commenters |
| `UPLOAD_LOGS_KV` | KV | upload history |

D1 schema (run once):

```sql
CREATE TABLE IF NOT EXISTS posts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_email TEXT NOT NULL,
  display_name TEXT,
  avatar_url TEXT,
  content TEXT NOT NULL,
  created_at INTEGER NOT NULL DEFAULT (unixepoch())
);
```

## Variables and secrets

- `UPLOAD_PASSWORD` (secret) — admin password for uploads
- `ADMIN_EMAILS` — comma-separated admin Google addresses (default `joshuacalvert1@gmail.com`)
- `GOOGLE_CLIENT_ID` — ID-token audience (defaults to the public web client id)
- `ALLOWED_ORIGINS` — comma-separated origins; unset keeps `*`
- `R2_PUBLIC_URL` — public R2 domain (default `https://r2.beisanytime.com`)
- `ADMIN_API_KEY` (optional secret) — alternative to a Google identity for social admin actions

## Deploy

```bash
cd worker
wrangler deploy            # bundles worker/index.js
wrangler secret put UPLOAD_PASSWORD
```

Recommended `wrangler.toml`:

```toml
name = "beis-api"
main = "index.js"
compatibility_date = "2025-01-01"

routes = [
  { pattern = "api.beisanytime.com", custom_domain = true }
]
```

The `custom_domain` route requires `beisanytime.com` to be on the same Cloudflare
account; the Workers dashboard equivalent is *Settings → Domains & Routes → Add
custom domain*. Until it is added, the site and app have no working API URL.

## Smoke tests

```bash
curl "https://api.beisanytime.com/api/all-shiurim"
curl "https://api.beisanytime.com/api/views/<shiur-id>"
curl -X POST "https://api.beisanytime.com/api/views/increment" \
  -H "Content-Type: application/json" -d '{"id":"<shiur-id>"}'
curl "https://api.beisanytime.com/api/posts"

# Signed-in comment (401 without a token)
curl -X POST "https://api.beisanytime.com/api/comments/<shiur-id>" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <google-id-token>" \
  -d '{"text":"Hello"}'
```

## Still open

- Comment and like writes are not rate limited.
- The legacy `beis-anytime-api` worker is still queried for old shiurim; retire it once
  the library is fully in R2.
