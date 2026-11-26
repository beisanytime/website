/**
 * Google Identity Services ID-token verification for the Beis Anytime workers.
 *
 * The browser holds a Google ID token; it is only a hint until it is verified.
 * This module checks the RS256 signature against Google's published JWKS with
 * WebCrypto, then enforces issuer, audience, expiry and the verified-email claim,
 * so a token's email can be trusted for authorization decisions. No client secret
 * is needed, because ID tokens are public-key signed.
 */

const GOOGLE_CERTS_URL = 'https://www.googleapis.com/oauth2/v3/certs';
const VALID_ISSUERS = new Set(['accounts.google.com', 'https://accounts.google.com']);
const SIGNING_KEY_TTL_MS = 60 * 60 * 1000;
const CLOCK_SKEW_SECONDS = 60;

// The public OAuth client id shipped in the web app. Public by design, not a secret.
export const DEFAULT_GOOGLE_CLIENT_ID =
  '248585696121-67ecvsoqhtbpc0b2qt5f486864p0uvnq.apps.googleusercontent.com';

const DEFAULT_ADMIN_EMAILS = ['joshuacalvert1@gmail.com'];

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

export const getAdminEmails = (env) => {
  const configured = String((env && env.ADMIN_EMAILS) || '');
  const emails = configured.split(',').map(email => email.trim().toLowerCase()).filter(Boolean);
  return emails.length ? emails : DEFAULT_ADMIN_EMAILS;
};

export const isAdminEmail = (email, env) =>
  typeof email === 'string' && getAdminEmails(env).includes(email.trim().toLowerCase());

// Constant-time-ish string compare so password checks do not leak length/prefix.
export const timingSafeEqual = (a, b) => {
  const left = String(a ?? '');
  const right = String(b ?? '');
  let mismatch = left.length === right.length ? 0 : 1;
  const length = Math.max(left.length, right.length);
  for (let i = 0; i < length; i += 1) {
    mismatch |= (left.charCodeAt(i) || 0) ^ (right.charCodeAt(i) || 0);
  }
  return mismatch === 0;
};

export const bearerToken = (request) => {
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
export const verifyGoogleIdToken = async (token, audience) => {
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
 * Admin access requires the upload password AND a verified admin Google identity.
 * Returns { ok: true, email, name } or { ok: false, status, error }.
 */
export const authenticateAdmin = async (request, env) => {
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
