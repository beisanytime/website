/**
 * Beis Anytime — the single API worker.
 *
 * Deployed as `beis-api` (https://beis-api.beisanytime.workers.dev) and served to
 * the site and the apps at https://api.beisanytime.com.
 *
 * Routes
 *   Library / media  GET  /api/all-shiurim
 *                    GET  /api/shiurim/id/:id
 *                    GET  /api/video-proxy?key=...
 *                    PUT  /api/upload-proxy?key=...
 *   Admin            POST /api/admin/prepare-upload | upload-part | complete-upload | abort-upload
 *                    GET  /api/admin/shiurim | upload-logs
 *                    DELETE /api/admin/shiurim/:id
 *                    POST /api/admin/refresh-thumbnails | cleanup-malformed-thumbnails
 *                    GET  /api/debug-r2
 *   Social           GET|POST /api/views/:id, POST /api/views/increment
 *                    GET|POST /api/likes/:id
 *                    GET|POST /api/comments/:id, DELETE /api/comments/:id/:commentId
 *                    GET|PUT  /api/users/:email
 *                    POST /api/ban
 *   Community feed   GET|POST /api/posts, DELETE /api/posts/:id
 *   Fallback         everything else is proxied to the legacy KV worker.
 *
 * Bindings
 *   NEW_VIDEO_BUCKET (R2)  DB (D1)
 *   VIEWS_KV  LIKES_KV  COMMENTS_KV  USERS_KV  BANS_KV  UPLOAD_LOGS_KV (KV)
 *
 * Secrets / vars
 *   UPLOAD_PASSWORD   required for admin routes
 *   ADMIN_EMAILS      comma-separated admin Google addresses (default joshuacalvert1@gmail.com)
 *   GOOGLE_CLIENT_ID  ID-token audience (defaults to the public web client id)
 *   ALLOWED_ORIGINS   comma-separated origins; unset keeps "*"
 *   R2_PUBLIC_URL     public R2 domain (default https://r2.beisanytime.com)
 *   ADMIN_API_KEY     optional secret accepted as X-Admin-Key for social admin actions
 *
 * Identity: callers prove who they are with a Google ID token in
 * `Authorization: Bearer <id_token>`. The token is verified here against Google's
 * JWKS (RS256, issuer, audience, expiry, verified email), so the email in it can be
 * trusted. X-User-Email is never trusted.
 */

const GOOGLE_CERTS_URL = 'https://www.googleapis.com/oauth2/v3/certs';
const VALID_ISSUERS = new Set(['accounts.google.com', 'https://accounts.google.com']);
const SIGNING_KEY_TTL_MS = 60 * 60 * 1000;
const CLOCK_SKEW_SECONDS = 60;

// The public OAuth client id shipped in the web app. Public by design, not a secret.
const DEFAULT_GOOGLE_CLIENT_ID =
  '248585696121-67ecvsoqhtbpc0b2qt5f486864p0uvnq.apps.googleusercontent.com';

const DEFAULT_ADMIN_EMAILS = ['joshuacalvert1@gmail.com'];

const OLD_WORKER_URL = 'https://beis-anytime-api.beisanytime.workers.dev';

const MAX_POST_LENGTH = 5000;
const MAX_COMMENT_LENGTH = 2000;
const MAX_DISPLAY_NAME_LENGTH = 80;

// --- Google ID token verification -------------------------------------------

let cachedKeys = null;
let cachedKeysExpireAt = 0;

const base64UrlToBytes = (value) => {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized.padEnd(normalized.length + ((4 - (normalized.length % 4)) % 4), '=');
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
};

const base64UrlToJson = (value) => JSON.parse(new TextDecoder().decode(base64UrlToBytes(value)));

const getAdminEmails = (env) => {
  const configured = String((env && env.ADMIN_EMAILS) || '');
  const emails = configured.split(',').map(email => email.trim().toLowerCase()).filter(Boolean);
  return emails.length ? emails : DEFAULT_ADMIN_EMAILS;
};

const isAdminEmail = (email, env) =>
  typeof email === 'string' && getAdminEmails(env).includes(email.trim().toLowerCase());

// Constant-time-ish string compare so password checks do not leak length/prefix.
const timingSafeEqual = (a, b) => {
  const left = String(a ?? '');
  const right = String(b ?? '');
  let mismatch = left.length === right.length ? 0 : 1;
  const length = Math.max(left.length, right.length);
  for (let i = 0; i < length; i += 1) {
    mismatch |= (left.charCodeAt(i) || 0) ^ (right.charCodeAt(i) || 0);
  }
  return mismatch === 0;
};

const bearerToken = (request) => {
  const header = request.headers.get('Authorization') || '';
  const match = header.match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : null;
};

const getSigningKeys = async () => {
  if (cachedKeys && Date.now() < cachedKeysExpireAt) return cachedKeys;
  const response = await fetch(GOOGLE_CERTS_URL, { headers: { Accept: 'application/json' } });
  if (!response.ok) throw new Error(`Unable to fetch Google signing keys (HTTP ${response.status})`);
  const jwks = await response.json();
  if (!jwks || !Array.isArray(jwks.keys) || jwks.keys.length === 0) {
    throw new Error('Google signing keys response was empty');
  }
  cachedKeys = jwks.keys;
  cachedKeysExpireAt = Date.now() + SIGNING_KEY_TTL_MS;
  return cachedKeys;
};

/**
 * Verify a Google ID token and return its claims, or null when it is not valid.
 */
const verifyGoogleIdToken = async (token, audience) => {
  if (typeof token !== 'string') return null;
  const parts = token.split('.');
  if (parts.length !== 3) return null;

  try {
    const header = base64UrlToJson(parts[0]);
    if (!header || header.alg !== 'RS256' || !header.kid) return null;

    const keys = await getSigningKeys();
    const jwk = keys.find(key => key.kid === header.kid);
    if (!jwk) return null;

    const key = await crypto.subtle.importKey(
      'jwk',
      { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: 'RS256', ext: true },
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['verify']
    );
    const signatureValid = await crypto.subtle.verify(
      'RSASSA-PKCS1-v1_5',
      key,
      base64UrlToBytes(parts[2]),
      new TextEncoder().encode(`${parts[0]}.${parts[1]}`)
    );
    if (!signatureValid) return null;

    const payload = base64UrlToJson(parts[1]);
    if (!payload) return null;

    const now = Math.floor(Date.now() / 1000);
    if (typeof payload.exp !== 'number' || payload.exp + CLOCK_SKEW_SECONDS < now) return null;
    if (typeof payload.iat === 'number' && payload.iat - CLOCK_SKEW_SECONDS > now) return null;
    if (!VALID_ISSUERS.has(payload.iss)) return null;

    const audiences = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
    if (audience && !audiences.includes(audience)) return null;

    if (!payload.email || payload.email_verified === false) return null;

    return payload;
  } catch (error) {
    console.error('Google ID token verification failed:', error);
    return null;
  }
};

/**
 * Admin access for the library/upload routes: the upload password AND a verified
 * admin Google identity. Returns { ok: true, email, name } or { ok: false, status, error }.
 */
const authenticateAdmin = async (request, env) => {
  const expectedPassword = env && env.UPLOAD_PASSWORD;
  if (!expectedPassword) {
    console.error('UPLOAD_PASSWORD environment variable is not set');
    return { ok: false, status: 500, error: 'Server is not configured for admin access' };
  }

  const password = request.headers.get('X-Upload-Password') || '';
  if (!timingSafeEqual(password, expectedPassword)) {
    return { ok: false, status: 401, error: 'Unauthorized' };
  }

  const token = bearerToken(request);
  const payload = token
    ? await verifyGoogleIdToken(token, (env && env.GOOGLE_CLIENT_ID) || DEFAULT_GOOGLE_CLIENT_ID)
    : null;
  if (!payload) {
    return { ok: false, status: 401, error: 'Google sign-in required' };
  }

  const email = String(payload.email).toLowerCase();
  if (!isAdminEmail(email, env)) {
    return { ok: false, status: 403, error: 'This Google account is not an admin' };
  }

  return { ok: true, email, name: payload.name || email };
};

// --- KV JSON helpers (social data) ------------------------------------------

const getKVJson = async (kv, key) => {
  const txt = await kv.get(key);
  if (!txt) return null;
  try { return JSON.parse(txt); } catch (e) { return null; }
};

const putKVJson = async (kv, key, val) => {
  await kv.put(key, JSON.stringify(val));
};

// Path segments arrive percent-encoded; KV keys are built from the decoded id so a
// GET and the matching POST (which sends the id in a JSON body) address the same key.
const decodePart = (value) => {
  try { return decodeURIComponent(value); } catch (e) { return value; }
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    // Configuration
    const R2_PUBLIC_BASE = env.R2_PUBLIC_URL || 'https://r2.beisanytime.com';

    // Set ALLOWED_ORIGINS (comma-separated) to lock the API to the real site.
    // Unset keeps the previous "*" behaviour so the existing deployment keeps working.
    const allowedOrigins = String(env.ALLOWED_ORIGINS || '')
      .split(',')
      .map(origin => origin.trim())
      .filter(Boolean);
    const requestOrigin = request.headers.get("Origin") || '';
    const allowOrigin = allowedOrigins.length === 0
      ? "*"
      : (allowedOrigins.includes(requestOrigin) ? requestOrigin : allowedOrigins[0]);

    const corsHeaders = {
      "Access-Control-Allow-Origin": allowOrigin,
      "Vary": "Origin",
      "Access-Control-Allow-Methods": "GET, HEAD, POST, PUT, DELETE, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Range, Authorization, X-User-Email, X-Admin-Key, X-Upload-Password, X-User-Name",
      "Access-Control-Expose-Headers": "Accept-Ranges, Content-Length, Content-Range, ETag, Content-Type",
    };

    if (method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }

    // --- Helpers: JSON responses and complete bucket listing ---
    const jsonResponse = (body, status = 200) => new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    });
    const json = jsonResponse;
    const noContent = () => new Response(null, { status: 204, headers: corsHeaders });

    // R2 returns at most 1000 keys per call; follow the cursor so big libraries are complete.
    const listAllKeys = async (prefix) => {
      const objects = [];
      let cursor;
      do {
        const page = await env.NEW_VIDEO_BUCKET.list(prefix ? { prefix, cursor } : { cursor });
        objects.push(...page.objects);
        cursor = page.truncated ? page.cursor : undefined;
      } while (cursor);
      return objects;
    };

    // --- Identity: verified Google ID token, resolved once per request ---
    let identityPromise = null;
    const getIdentity = () => {
      if (!identityPromise) {
        identityPromise = (async () => {
          const token = bearerToken(request);
          if (!token) return null;
          return await verifyGoogleIdToken(
            token,
            env.GOOGLE_CLIENT_ID || DEFAULT_GOOGLE_CLIENT_ID
          );
        })();
      }
      return identityPromise;
    };
    const getIdentityEmail = async () => {
      const claims = await getIdentity();
      return claims && claims.email ? String(claims.email).toLowerCase() : null;
    };
    // Social admin actions: a verified admin Google account, or the ADMIN_API_KEY secret.
    const isAdminRequest = async () => {
      const email = await getIdentityEmail();
      if (email && isAdminEmail(email, env)) return true;
      const expectedKey = env.ADMIN_API_KEY;
      return !!(expectedKey && timingSafeEqual(request.headers.get('X-Admin-Key') || '', expectedKey));
    };

    // --- Helper: Verify upload password AND a verified admin Google identity ---
    const verifyPassword = async (request) => {
      const result = await authenticateAdmin(request, env);
      if (!result.ok) {
        console.error(`Admin request rejected: ${result.error}`);
        return false;
      }
      return true;
    };

    // --- Helper: Log upload to KV ---
    const logUpload = async (env, userEmail, userName, filename, type) => {
      try {
        if (!env.UPLOAD_LOGS_KV) return;
        const timestamp = new Date().toISOString();
        const key = `upload:${Date.now()}:${filename}`;
        const entry = { timestamp, email: userEmail, name: userName, filename, type };
        await env.UPLOAD_LOGS_KV.put(key, JSON.stringify(entry), {
          expirationTtl: 60 * 60 * 24 * 365 // 1 year retention
        });
        console.log(`Upload logged: ${userName} (${userEmail}) uploaded ${filename}`);
      } catch (err) {
        console.error('Failed to log upload:', err);
      }
    };

    // --- Utility: Parse filename to Metadata ---
    const parseFilename = (filename) => {
      const cleanName = filename.replace(/\.(mp4|mov|m4a|mp3)$/i, '');
      const base = `${url.origin}/api/video-proxy?key=`;

      // Helper to build URLs using the proxy
      const getProxyUrl = (key) => `${base}${encodeURIComponent(key)}`;

      // Try OLD format first: split by " - " (space dash space)
      const oldParts = cleanName.split(' - ');
      if (oldParts.length >= 3 && /^\d{4}-\d{2}-\d{2}$/.test(oldParts[0].trim())) {
        const date = oldParts[0].trim();
        const rabbi = oldParts[1].trim().replace(/_/g, ' ');
        const title = oldParts.slice(2).join(' - ').trim().replace(/_/g, ' ');
        return {
          id: filename,
          title: title,
          rabbi: rabbi,
          date: date,
          thumbnailUrl: getProxyUrl(`thumbnails/${cleanName}.jpg`),
          playbackUrl: getProxyUrl(filename),
          source: 'r2'
        };
      }

      // Try NEW format: YYYY-MM-DD-Rabbi-Title (date is first 10 chars)
      const dateMatch = cleanName.match(/^(\d{4}-\d{2}-\d{2})-(.+)$/);
      if (dateMatch) {
        const date = dateMatch[1];
        const rest = dateMatch[2];
        const firstDash = rest.indexOf('-');
        let rabbi, title;
        if (firstDash !== -1) {
          rabbi = rest.substring(0, firstDash).replace(/_/g, ' ');
          title = rest.substring(firstDash + 1).replace(/_/g, ' ');
        } else {
          rabbi = 'guests';
          title = rest.replace(/_/g, ' ');
        }
        return {
          id: filename,
          title: title,
          rabbi: rabbi,
          date: date,
          thumbnailUrl: getProxyUrl(`thumbnails/${cleanName}.jpg`),
          playbackUrl: getProxyUrl(filename),
          source: 'r2'
        };
      }

      // Fallback: return basic info so the video still shows
      return {
        id: filename,
        title: cleanName.replace(/[-_]/g, ' '),
        rabbi: 'guests',
        date: new Date().toISOString().split('T')[0],
        thumbnailUrl: getProxyUrl(`thumbnails/${cleanName}.jpg`),
        playbackUrl: getProxyUrl(filename),
        source: 'r2'
      };
    };

    // ============================================================
    // SOCIAL: views, likes, comments, display names, bans
    // ============================================================
    const parts = path.replace(/\/+$/, '').split('/').filter(Boolean);
    const isApi = parts[0] === 'api';

    // --- Views ---
    // GET /api/views/:id  |  POST /api/views/increment { id }
    if (isApi && parts[1] === 'views') {
      if (!env.VIEWS_KV) return json({ error: 'VIEWS_KV is not bound' }, 500);

      if (method === 'POST' && parts[2] === 'increment') {
        let body;
        try { body = await request.json(); } catch (e) { return json({ error: 'Invalid JSON' }, 400); }
        const id = body && body.id;
        if (!id) return json({ error: 'Missing id' }, 400);
        const key = String(id);
        const prev = await env.VIEWS_KV.get(key) || '0';
        const next = String((parseInt(prev, 10) || 0) + 1);
        await env.VIEWS_KV.put(key, next);
        return json({ count: parseInt(next, 10) });
      }

      if (method === 'GET' && parts[2] && parts[2] !== 'increment') {
        const val = await env.VIEWS_KV.get(decodePart(parts[2])) || '0';
        return json({ count: parseInt(val, 10) });
      }

      return json({ error: 'Not found' }, 404);
    }

    // --- Likes ---
    if (isApi && parts[1] === 'likes') {
      if (!env.LIKES_KV) return json({ error: 'LIKES_KV is not bound' }, 500);
      const id = parts[2] ? decodePart(parts[2]) : '';
      if (!id) return json({ error: 'Missing id' }, 400);
      const key = `likes:${id}`;

      if (method === 'GET') {
        const data = await getKVJson(env.LIKES_KV, key) || { users: [] };
        const users = Array.isArray(data.users) ? data.users : [];
        const email = await getIdentityEmail();
        return json({ count: users.length, userLiked: !!(email && users.includes(email)) });
      }

      if (method === 'POST') {
        const email = await getIdentityEmail();
        if (!email) return json({ error: 'Google sign-in required' }, 401);
        const data = await getKVJson(env.LIKES_KV, key) || { users: [] };
        data.users = Array.isArray(data.users) ? data.users : [];
        const idx = data.users.indexOf(email);
        let userLiked;
        if (idx >= 0) {
          data.users.splice(idx, 1);
          userLiked = false;
        } else {
          data.users.push(email);
          userLiked = true;
        }
        await putKVJson(env.LIKES_KV, key, data);
        return json({ count: data.users.length, userLiked });
      }

      return json({ error: 'Method not allowed' }, 405);
    }

    // --- Comments ---
    if (isApi && parts[1] === 'comments') {
      if (!env.COMMENTS_KV) return json({ error: 'COMMENTS_KV is not bound' }, 500);
      const id = parts[2] ? decodePart(parts[2]) : '';
      const commentId = parts[3] ? decodePart(parts[3]) : '';
      if (!id) return json({ error: 'Missing id' }, 400);
      const key = `comments:${id}`;

      if (method === 'GET' && !commentId) {
        const data = await getKVJson(env.COMMENTS_KV, key) || { comments: [] };
        const comments = (data.comments || []).slice().sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
        return json({ comments });
      }

      if (method === 'POST' && !commentId) {
        const claims = await getIdentity();
        if (!claims || !claims.email) return json({ error: 'Google sign-in required' }, 401);
        const email = String(claims.email).toLowerCase();

        if (env.BANS_KV) {
          const banned = await env.BANS_KV.get(`ban:${email}`);
          if (banned) return json({ error: 'You are banned from commenting' }, 403);
        }

        let body;
        try { body = await request.json(); } catch (e) { return json({ error: 'Invalid JSON' }, 400); }
        const text = body && body.text ? String(body.text).slice(0, MAX_COMMENT_LENGTH).trim() : '';
        if (!text) return json({ error: 'Empty comment' }, 400);

        const storedUser = env.USERS_KV ? (await getKVJson(env.USERS_KV, `user:${email}`) || {}) : {};
        const displayName = storedUser.displayName || claims.name || email;

        const comment = {
          id: `${Date.now()}-${Math.random().toString(36).slice(2, 9)}`,
          email,
          displayName,
          text,
          createdAt: new Date().toISOString()
        };
        const data = await getKVJson(env.COMMENTS_KV, key) || { comments: [] };
        data.comments = data.comments || [];
        data.comments.push(comment);
        await putKVJson(env.COMMENTS_KV, key, data);
        return json({ ok: true, comment });
      }

      if (method === 'DELETE' && commentId) {
        if (!(await isAdminRequest())) return json({ error: 'Admin only' }, 403);
        const data = await getKVJson(env.COMMENTS_KV, key) || { comments: [] };
        data.comments = (data.comments || []).filter(c => c.id !== commentId);
        await putKVJson(env.COMMENTS_KV, key, data);
        return noContent();
      }

      return json({ error: 'Method not allowed' }, 405);
    }

    // --- Display names ---
    // GET /api/users/:email  |  PUT /api/users/:email { displayName }
    if (isApi && parts[1] === 'users' && parts[2]) {
      if (!env.USERS_KV) return json({ error: 'USERS_KV is not bound' }, 500);
      const email = decodeURIComponent(parts[2]).toLowerCase();
      const key = `user:${email}`;

      if (method === 'GET') {
        const data = await getKVJson(env.USERS_KV, key) || {};
        return json(data);
      }

      if (method === 'PUT') {
        const callerEmail = await getIdentityEmail();
        if (!callerEmail) return json({ error: 'Google sign-in required' }, 401);
        if (callerEmail !== email && !(await isAdminRequest())) {
          return json({ error: 'Permission denied' }, 403);
        }
        let body;
        try { body = await request.json(); } catch (e) { return json({ error: 'Invalid JSON' }, 400); }
        const displayName = body && body.displayName
          ? String(body.displayName).slice(0, MAX_DISPLAY_NAME_LENGTH).trim()
          : '';
        const prev = await getKVJson(env.USERS_KV, key) || {};
        prev.displayName = displayName;
        await putKVJson(env.USERS_KV, key, prev);
        return json({ ok: true });
      }

      return json({ error: 'Method not allowed' }, 405);
    }

    // --- Bans ---
    // POST /api/ban { email }
    if (isApi && parts[1] === 'ban' && method === 'POST') {
      if (!env.BANS_KV) return json({ error: 'BANS_KV is not bound' }, 500);
      if (!(await isAdminRequest())) return json({ error: 'Admin only' }, 403);
      let body;
      try { body = await request.json(); } catch (e) { return json({ error: 'Invalid JSON' }, 400); }
      const email = body && body.email ? String(body.email).trim().toLowerCase() : '';
      if (!email) return json({ error: 'Missing email' }, 400);
      await env.BANS_KV.put(`ban:${email}`, '1');
      return json({ ok: true });
    }

    // ============================================================
    // COMMUNITY FEED (D1)
    // ============================================================
    if (isApi && parts[1] === 'posts') {
      if (!env.DB) return json({ error: 'DB is not bound' }, 500);

      const requireAdmin = async () => {
        const claims = await getIdentity();
        if (!claims || !claims.email) return { ok: false, response: json({ error: 'Google sign-in required' }, 401) };
        const email = String(claims.email).toLowerCase();
        if (!isAdminEmail(email, env)) return { ok: false, response: json({ error: 'Not an admin account' }, 403) };
        return {
          ok: true,
          email,
          name: claims.name || email,
          picture: claims.picture || ''
        };
      };

      try {
        // GET /api/posts
        if (parts.length === 2 && method === 'GET') {
          const { results } = await env.DB.prepare(
            'SELECT * FROM posts ORDER BY created_at DESC LIMIT 50'
          ).all();
          return json(results);
        }

        // POST /api/posts
        if (parts.length === 2 && method === 'POST') {
          const identity = await requireAdmin();
          if (!identity.ok) return identity.response;

          let body;
          try { body = await request.json(); } catch (e) { return json({ error: 'Invalid JSON' }, 400); }
          const content = typeof body?.content === 'string' ? body.content.trim() : '';

          if (!content) return json({ error: 'Missing content' }, 400);
          if (content.length > MAX_POST_LENGTH) {
            return json({ error: `Post is too long (limit ${MAX_POST_LENGTH} characters)` }, 400);
          }

          await env.DB.prepare(
            `INSERT INTO posts (user_email, display_name, avatar_url, content)
             VALUES (?, ?, ?, ?)`
          ).bind(identity.email, identity.name, identity.picture, content).run();

          return json({ success: true });
        }

        // DELETE /api/posts/:id
        if (parts.length === 3 && method === 'DELETE') {
          const identity = await requireAdmin();
          if (!identity.ok) return identity.response;

          const id = Number.parseInt(parts[2], 10);
          if (!Number.isInteger(id) || id < 1) return json({ error: 'Invalid post id' }, 400);

          await env.DB.prepare('DELETE FROM posts WHERE id = ?').bind(id).run();
          return json({ success: true });
        }

        return json({ error: 'Not found' }, 404);
      } catch (err) {
        return json({ error: err.message }, 500);
      }
    }

    // ============================================================
    // LIBRARY: media, metadata, admin, uploads
    // ============================================================

    // --- Route: GET /api/video-proxy?key=... ---
    // Serves files (videos/thumbnails) directly via the worker's binding.
    if (path === "/api/video-proxy" && (method === "GET" || method === "HEAD")) {
      const key = url.searchParams.get("key");
      if (!key) return new Response("Missing key", { status: 400, headers: corsHeaders });

      const range = request.headers.get("Range");
      let obj;
      try {
        // R2 understands the browser's Range header, including suffix ranges.
        obj = await env.NEW_VIDEO_BUCKET.get(key, range ? { range: request.headers } : undefined);
      } catch (error) {
        return jsonResponse({ error: "Unable to read media" }, 502);
      }
      if (!obj) return new Response("Not found", { status: 404, headers: corsHeaders });

      const headers = new Headers(corsHeaders);
      obj.writeHttpMetadata(headers);
      if (/^thumbnails\//i.test(key)) {
        headers.set("Content-Type", "image/jpeg");
      } else if (/\.mp4$/i.test(key)) {
        headers.set("Content-Type", "video/mp4");
      } else if (/\.mov$/i.test(key)) {
        headers.set("Content-Type", "video/quicktime");
      } else if (/\.(m4a|mp3)$/i.test(key)) {
        headers.set("Content-Type", "audio/mpeg");
      }
      headers.set("ETag", obj.httpEtag);
      headers.set("Accept-Ranges", "bytes");
      headers.set("Cache-Control", "public, max-age=31536000, immutable");

      if (obj.range) {
        const rangeOffset = obj.range.offset ?? Math.max(0, obj.size - obj.range.length);
        const rangeLength = obj.range.length ?? obj.size;
        headers.set("Content-Range", `bytes ${rangeOffset}-${rangeOffset + rangeLength - 1}/${obj.size}`);
        headers.set("Content-Length", String(rangeLength));
      } else {
        headers.set("Content-Length", String(obj.size));
      }

      // HEAD must expose the same metadata as GET without consuming a body.
      return new Response(method === "HEAD" ? null : obj.body, {
        status: obj.range ? 206 : 200,
        headers
      });
    }

    // --- Route: GET /api/debug-r2 ---
    if (path === "/api/debug-r2" && method === "GET") {
      if (!(await verifyPassword(request))) return jsonResponse({ error: 'Unauthorized' }, 401);
      const objects = await listAllKeys();
      return jsonResponse({ objects });
    }

    // --- Route: POST /api/admin/refresh-thumbnails ---
    if (path === "/api/admin/refresh-thumbnails" && method === "POST") {
      if (!(await verifyPassword(request))) return jsonResponse({ error: 'Unauthorized' }, 401);
      const userEmail = await getIdentityEmail();
      if (!userEmail) return jsonResponse({ error: 'Google sign-in required' }, 401);
      try {
        const body = await request.json();
        const { key, thumbnail } = body || {};
        if (!key || !thumbnail || !/^data:image\/jpeg;base64,/.test(thumbnail)) {
          return jsonResponse({ error: "Missing video key or JPEG thumbnail" }, 400);
        }
        const base64 = thumbnail.substring("data:image/jpeg;base64,".length);
        const binary = Uint8Array.from(atob(base64), char => char.charCodeAt(0));
        const videoKey = key.replace(/^thumbnails\//i, '');
        if (/^thumbnails\//i.test(key) || !/\.(mp4|mov|m4v)$/i.test(videoKey)) {
          return jsonResponse({ error: "Expected a video object key" }, 400);
        }
        const thumbKey = `thumbnails/${videoKey.replace(/\.[^.]+$/, '.jpg')}`;
        await env.NEW_VIDEO_BUCKET.put(thumbKey, binary, { httpMetadata: { contentType: "image/jpeg" } });
        return jsonResponse({ success: true, key, thumbnailKey: thumbKey });
      } catch (err) {
        return jsonResponse({ error: err.message }, 500);
      }
    }

    // --- Route: POST /api/admin/cleanup-malformed-thumbnails ---
    if (path === "/api/admin/cleanup-malformed-thumbnails" && method === "POST") {
      if (!(await verifyPassword(request))) return jsonResponse({ error: 'Unauthorized' }, 401);
      const userEmail = await getIdentityEmail();
      if (!userEmail) return jsonResponse({ error: 'Google sign-in required' }, 401);
      const objects = await listAllKeys("thumbnails/");
      const malformed = objects.filter(object => /\.(mp4|mov|m4v)$/i.test(object.key));
      await Promise.all(malformed.map(object => env.NEW_VIDEO_BUCKET.delete(object.key)));
      return jsonResponse({ deleted: malformed.length });
    }

    // --- Route: GET /api/admin/shiurim ---
    if (path === "/api/admin/shiurim" && method === "GET") {
      if (!(await verifyPassword(request))) return jsonResponse({ error: 'Unauthorized' }, 401);
      return handleAllShiurim();
    }

    // --- Route: DELETE /api/admin/shiurim/:id ---
    if (path.startsWith("/api/admin/shiurim/") && method === "DELETE") {
      if (!(await verifyPassword(request))) return jsonResponse({ error: 'Unauthorized' }, 401);
      const id = decodeURIComponent(path.split("/").pop());

      if (/\.(mp4|mov|m4a|mp3)$/i.test(id)) {
        // Delete from R2
        await env.NEW_VIDEO_BUCKET.delete(id);
        // Also try deleting thumbnail
        const thumbKey = `thumbnails/${id.replace(/\.[^.]+$/, '.jpg')}`;
        await env.NEW_VIDEO_BUCKET.delete(thumbKey);

        return jsonResponse({ success: true });
      }

      // Fallback
      return fetch(`${OLD_WORKER_URL}${path}`, {
        method: 'DELETE',
        headers: request.headers
      });
    }

    // --- Route: GET /api/all-shiurim ---
    async function handleAllShiurim() {
      try {
        // 1. Fetch from Old Worker (Parallel)
        const oldPromise = fetch(`${OLD_WORKER_URL}/api/all-shiurim`).then(r => r.ok ? r.json() : []);

        // 2. List from R2
        const objects = await listAllKeys();
        const r2Shiurim = objects
          .filter(obj => !/^thumbnails\//i.test(obj.key) && /\.(mp4|mov|m4a|mp3)$/i.test(obj.key))
          .map(obj => parseFilename(obj.key))
          .filter(s => s !== null);

        let oldShiurim = await oldPromise;

        // Safety: Ensure oldShiurim is an array
        if (oldShiurim && !Array.isArray(oldShiurim)) {
          oldShiurim = [oldShiurim];
        } else if (!oldShiurim) {
          oldShiurim = [];
        }

        // Merge results
        const merged = [...r2Shiurim, ...oldShiurim];

        // Sort by date descending
        merged.sort((a, b) => new Date(b.date) - new Date(a.date));

        return jsonResponse(merged);
      } catch (err) {
        return jsonResponse({ error: err.message }, 500);
      }
    }

    if (path === "/api/all-shiurim" && method === "GET") {
      return handleAllShiurim();
    }

    // --- Route: GET /api/shiurim/id/:id ---
    if (path.startsWith("/api/shiurim/id/") && method === "GET") {
      const id = decodeURIComponent(path.split("/").pop());

      // Check if it's an R2 file (ends with video extension)
      if (/\.(mp4|mov|m4a|mp3)$/i.test(id)) {
        const metadata = parseFilename(id);
        if (metadata) {
          return jsonResponse(metadata);
        }
      }

      // Fallback to Old Worker
      return fetch(`${OLD_WORKER_URL}${path}`, {
        headers: { ...request.headers, "Access-Control-Allow-Origin": "*" }
      });
    }

    // ============================================================
    // CHUNKED MULTIPART UPLOAD (Bypasses 100MB worker body limit)
    // Flow: prepare-upload -> upload-part (x N) -> complete-upload
    // ============================================================

    // --- Route: POST /api/admin/abort-upload ---
    // Releases a half-finished multipart upload instead of leaving orphaned parts.
    if (path === "/api/admin/abort-upload" && method === "POST") {
      if (!(await verifyPassword(request))) return jsonResponse({ error: 'Unauthorized' }, 401);
      try {
        const { r2Key, uploadId } = await request.json();
        if (!r2Key || !uploadId) return jsonResponse({ error: 'Missing r2Key or uploadId' }, 400);
        const multipartUpload = env.NEW_VIDEO_BUCKET.resumeMultipartUpload(r2Key, uploadId);
        await multipartUpload.abort();
        return jsonResponse({ success: true });
      } catch (err) {
        return jsonResponse({ error: err.message }, 500);
      }
    }

    // --- Route: POST /api/admin/prepare-upload ---
    if (path === "/api/admin/prepare-upload" && method === "POST") {
      if (!(await verifyPassword(request))) return jsonResponse({ error: 'Unauthorized' }, 401);
      const claims = await getIdentity();
      const userEmail = claims && claims.email ? String(claims.email).toLowerCase() : null;
      if (!userEmail) return jsonResponse({ error: 'Google sign-in required' }, 401);
      try {
        const body = await request.json();
        const { title, rabbi, date, fileName } = body;

        if (!title || !rabbi || !date) {
          return new Response("Missing metadata", { status: 400, headers: corsHeaders });
        }

        const extension = fileName.split('.').pop();
        const cleanTitle = title.replace(/[\\/:*?"<>| ]/g, '_');
        const cleanRabbi = rabbi.replace(/ /g, '_');
        const r2Key = `${date}-${cleanRabbi}-${cleanTitle}.${extension}`;
        const thumbKey = `thumbnails/${date}-${cleanRabbi}-${cleanTitle}.jpg`;

        // Set content type based on extension
        const contentType = extension.toLowerCase() === 'mov' ? 'video/quicktime' :
          ['m4a', 'mp3'].includes(extension.toLowerCase()) ? 'audio/mpeg' :
          'video/mp4';

        // Start multipart upload for the video
        const multipartUpload = await env.NEW_VIDEO_BUCKET.createMultipartUpload(r2Key, {
          httpMetadata: { contentType: contentType }
        });

        // Log the upload
        const userName = request.headers.get('X-User-Name') || claims.name || userEmail;
        await logUpload(env, userEmail, userName, r2Key, 'prepare');

        return jsonResponse({
          r2Key: r2Key,
          thumbKey: thumbKey,
          uploadId: multipartUpload.uploadId,
          // Thumbnail goes through the simple proxy (small file)
          thumbnailUrl: `${url.origin}/api/upload-proxy?key=${encodeURIComponent(thumbKey)}`
        });
      } catch (err) {
        return jsonResponse({ error: err.message }, 500);
      }
    }

    // --- Route: PUT /api/admin/upload-part ---
    if (path === "/api/admin/upload-part" && method === "PUT") {
      if (!(await verifyPassword(request))) return jsonResponse({ error: 'Unauthorized' }, 401);
      try {
        const r2Key = url.searchParams.get("key");
        const uploadId = url.searchParams.get("uploadId");
        const partNumber = Number.parseInt(url.searchParams.get("partNumber"), 10);

        if (!r2Key || !uploadId || !Number.isInteger(partNumber) || partNumber < 1) {
          return new Response("Missing or invalid key, uploadId, or partNumber", { status: 400, headers: corsHeaders });
        }

        const multipartUpload = env.NEW_VIDEO_BUCKET.resumeMultipartUpload(r2Key, uploadId);
        const part = await multipartUpload.uploadPart(partNumber, request.body);

        return jsonResponse({
          partNumber: part.partNumber,
          etag: part.etag
        });
      } catch (err) {
        return jsonResponse({ error: err.message }, 500);
      }
    }

    // --- Route: POST /api/admin/complete-upload ---
    if (path === "/api/admin/complete-upload" && method === "POST") {
      if (!(await verifyPassword(request))) return jsonResponse({ error: 'Unauthorized' }, 401);
      try {
        const { r2Key, uploadId, parts } = await request.json();

        if (!r2Key || !uploadId || !Array.isArray(parts) || parts.length === 0) {
          return new Response("Missing r2Key, uploadId, or parts", { status: 400, headers: corsHeaders });
        }

        const normalizedParts = parts
          .map(part => ({
            partNumber: Number(part.partNumber),
            etag: part.etag
          }))
          .filter(part => Number.isInteger(part.partNumber) && part.partNumber > 0 && typeof part.etag === 'string' && part.etag.length > 0)
          .sort((a, b) => a.partNumber - b.partNumber);

        if (normalizedParts.length !== parts.length || normalizedParts.some((part, index) => index > 0 && part.partNumber === normalizedParts[index - 1].partNumber)) {
          return new Response("Invalid or duplicate multipart parts", { status: 400, headers: corsHeaders });
        }

        const multipartUpload = env.NEW_VIDEO_BUCKET.resumeMultipartUpload(r2Key, uploadId);
        await multipartUpload.complete(normalizedParts);

        return jsonResponse({ success: true, r2Key: r2Key });
      } catch (err) {
        return jsonResponse({ error: err.message }, 500);
      }
    }

    // --- Route: PUT /api/upload-proxy ---
    if (path === "/api/upload-proxy" && method === "PUT") {
      if (!(await verifyPassword(request))) return jsonResponse({ error: 'Unauthorized' }, 401);
      const key = url.searchParams.get("key");
      if (!key) return new Response("Missing key", { status: 400, headers: corsHeaders });

      const contentType = key.endsWith(".jpg") ? "image/jpeg" :
                      key.endsWith(".mov") ? "video/quicktime" :
                      (request.headers.get("Content-Type") || "video/mp4");

      await env.NEW_VIDEO_BUCKET.put(key, request.body, {
        httpMetadata: { contentType: contentType }
      });

      return jsonResponse({ success: true });
    }

    // --- Route: GET /api/admin/upload-logs ---
    if (path === "/api/admin/upload-logs" && method === "GET") {
      if (!(await verifyPassword(request))) return jsonResponse({ error: 'Unauthorized' }, 401);
      try {
        const limit = parseInt(url.searchParams.get('limit') || '50');
        const list = await env.UPLOAD_LOGS_KV.list({ prefix: 'upload:', limit });
        const logs = [];
        for (const key of list.keys) {
          const value = await env.UPLOAD_LOGS_KV.get(key.name);
          if (value) logs.push(JSON.parse(value));
        }
        logs.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
        return jsonResponse(logs);
      } catch (err) {
        return jsonResponse({ error: err.message }, 500);
      }
    }

    // --- Default: Proxy everything else to the old worker ---
    // Never forward credentials or identity headers to a third-party worker.
    const forwardedHeaders = new Headers(request.headers);
    ['authorization', 'x-upload-password', 'x-user-email', 'x-user-name', 'x-admin-key', 'cookie'].forEach(header => {
      forwardedHeaders.delete(header);
    });
    return fetch(`${OLD_WORKER_URL}${path}`, {
      method: method,
      headers: forwardedHeaders,
      body: request.body
    });
  }
}
