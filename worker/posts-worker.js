// Cloudflare Worker: posts-worker.js
// Handles the Community Feed posts using a D1 database.
// Deploy this as a SEPARATE worker (e.g. beis-social-worker) from the KV worker.
//
// D1 Database setup - run this SQL once in the Cloudflare dashboard:
//   CREATE TABLE IF NOT EXISTS posts (
//     id INTEGER PRIMARY KEY AUTOINCREMENT,
//     user_email TEXT NOT NULL,
//     display_name TEXT,
//     avatar_url TEXT,
//     content TEXT NOT NULL,
//     created_at INTEGER NOT NULL DEFAULT (unixepoch())
//   );
//
// Author identity comes from a verified Google ID token (Authorization: Bearer <id_token>),
// never from the request body or an X-User-Email header.

import {
    bearerToken,
    verifyGoogleIdToken,
    isAdminEmail,
    DEFAULT_GOOGLE_CLIENT_ID,
} from './google-auth.js';

const MAX_CONTENT_LENGTH = 5000;

const json = (body, status, corsHeaders) =>
    new Response(JSON.stringify(body), {
        status,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

export default {
    async fetch(request, env) {
        const url = new URL(request.url);

        const corsHeaders = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        };

        if (request.method === 'OPTIONS') {
            return new Response(null, { headers: corsHeaders });
        }

        // Resolve the caller from a verified Google ID token.
        const requireAdmin = async () => {
            const token = bearerToken(request);
            const payload = token
                ? await verifyGoogleIdToken(
                      token,
                      env.GOOGLE_CLIENT_ID || DEFAULT_GOOGLE_CLIENT_ID
                  )
                : null;
            if (!payload || !payload.email) {
                return { ok: false, response: json({ error: 'Google sign-in required' }, 401, corsHeaders) };
            }
            const email = String(payload.email).toLowerCase();
            if (!isAdminEmail(email, env)) {
                return { ok: false, response: json({ error: 'Not an admin account' }, 403, corsHeaders) };
            }
            return {
                ok: true,
                email,
                name: payload.name || email,
                picture: payload.picture || '',
            };
        };

        try {
            // 1. GET /api/posts
            if (url.pathname === '/api/posts' && request.method === 'GET') {
                const { results } = await env.DB.prepare(
                    'SELECT * FROM posts ORDER BY created_at DESC LIMIT 50'
                ).all();

                return json(results, 200, corsHeaders);
            }

            // 2. POST /api/posts
            if (url.pathname === '/api/posts' && request.method === 'POST') {
                const identity = await requireAdmin();
                if (!identity.ok) return identity.response;

                const body = await request.json();
                const content = typeof body?.content === 'string' ? body.content.trim() : '';

                if (!content) return json({ error: 'Missing content' }, 400, corsHeaders);
                if (content.length > MAX_CONTENT_LENGTH) {
                    return json(
                        { error: `Post is too long (limit ${MAX_CONTENT_LENGTH} characters)` },
                        400,
                        corsHeaders
                    );
                }

                await env.DB.prepare(
                    `INSERT INTO posts (user_email, display_name, avatar_url, content)
           VALUES (?, ?, ?, ?)`
                )
                    .bind(identity.email, identity.name, identity.picture, content)
                    .run();

                return json({ success: true }, 200, corsHeaders);
            }

            // 3. DELETE /api/posts/:id
            if (request.method === 'DELETE' && url.pathname.startsWith('/api/posts/')) {
                const identity = await requireAdmin();
                if (!identity.ok) return identity.response;

                const id = Number.parseInt(url.pathname.split('/').pop(), 10);
                if (!Number.isInteger(id) || id < 1) {
                    return json({ error: 'Invalid post id' }, 400, corsHeaders);
                }

                await env.DB.prepare('DELETE FROM posts WHERE id = ?').bind(id).run();

                return json({ success: true }, 200, corsHeaders);
            }

            return new Response('Not Found', { status: 404, headers: corsHeaders });
        } catch (err) {
            return json({ error: err.message }, 500, corsHeaders);
        }
    },
};
