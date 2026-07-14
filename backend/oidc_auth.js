const crypto = require('crypto');

const SSO_ISSUER_URL = (process.env.SSO_ISSUER_URL || '').trim().replace(/\/+$/, '');
const SSO_CLIENT_ID = (process.env.SSO_CLIENT_ID || '').trim();
const SSO_CLIENT_SECRET = (process.env.SSO_CLIENT_SECRET || '').trim();
const SSO_REDIRECT_URI = (process.env.SSO_REDIRECT_URI || '').trim().replace(/\/+$/, '');
const SSO_SESSION_SECRET = (
  process.env.SSO_SESSION_SECRET ||
  process.env.PGRST_JWT_SECRET ||
  'local-sso-session-secret-change-me'
).trim();
const SSO_SCOPES = (process.env.SSO_SCOPES || 'openid hku').trim();
const SSO_POST_LOGOUT_REDIRECT_URI = (
  process.env.SSO_POST_LOGOUT_REDIRECT_URI || SSO_REDIRECT_URI
).trim();

const SESSION_COOKIE = 'pt_session';
const STATE_COOKIE = 'pt_oauth_state';
const SESSION_MAX_AGE_SEC = 7 * 24 * 3600;

let discoveryCache = null;
let discoveryError = null;

function isConfigured() {
  return (
    SSO_ISSUER_URL.length > 0 &&
    SSO_CLIENT_ID.length > 0 &&
    SSO_CLIENT_SECRET.length > 0 &&
    SSO_REDIRECT_URI.length > 0
  );
}

function b64url(data) {
  return Buffer.from(data)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function b64urlJson(obj) {
  return b64url(JSON.stringify(obj));
}

function parseCookies(req) {
  const raw = String(req.headers.cookie || '');
  const out = {};
  for (const part of raw.split(';')) {
    const idx = part.indexOf('=');
    if (idx < 0) continue;
    const k = part.slice(0, idx).trim();
    const v = part.slice(idx + 1).trim();
    if (k) out[k] = decodeURIComponent(v);
  }
  return out;
}

function cookieHeader(name, value, maxAgeSec) {
  const parts = [
    `${name}=${encodeURIComponent(value)}`,
    'Path=/',
    'HttpOnly',
    'SameSite=Lax',
    `Max-Age=${maxAgeSec}`,
  ];
  if (process.env.NODE_ENV === 'production') {
    parts.push('Secure');
  }
  return parts.join('; ');
}

function clearCookieHeader(name) {
  return `${name}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0`;
}

function signSessionToken(payload) {
  const header = b64urlJson({ alg: 'HS256', typ: 'JWT' });
  const now = Math.floor(Date.now() / 1000);
  const body = b64urlJson({
    ...payload,
    iss: 'project-tracker-sso',
    iat: now,
    exp: now + SESSION_MAX_AGE_SEC,
  });
  const input = `${header}.${body}`;
  const sig = crypto
    .createHmac('sha256', SSO_SESSION_SECRET)
    .update(input)
    .digest('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
  return `${input}.${sig}`;
}

function verifySessionToken(token) {
  const t = String(token || '').trim();
  const parts = t.split('.');
  if (parts.length !== 3) return null;
  const [header, body, sig] = parts;
  const expected = crypto
    .createHmac('sha256', SSO_SESSION_SECRET)
    .update(`${header}.${body}`)
    .digest('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
  if (sig !== expected) return null;
  try {
    const payload = JSON.parse(
      Buffer.from(body.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8'),
    );
    if (!payload.exp || payload.exp < Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch (_) {
    return null;
  }
}

function parseIdTokenClaims(idToken) {
  const t = String(idToken || '').trim();
  const parts = t.split('.');
  if (parts.length < 2) return null;
  try {
    const json = Buffer.from(
      parts[1].replace(/-/g, '+').replace(/_/g, '/'),
      'base64',
    ).toString('utf8');
    return JSON.parse(json);
  } catch (_) {
    return null;
  }
}

async function getDiscovery() {
  if (discoveryCache) return discoveryCache;
  if (discoveryError) throw discoveryError;
  const url = `${SSO_ISSUER_URL}/.well-known/openid-configuration`;
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(15000) });
    const raw = await res.text();
    if (!res.ok) {
      throw new Error(`OIDC discovery HTTP ${res.status}: ${raw.slice(0, 300)}`);
    }
    discoveryCache = JSON.parse(raw);
    return discoveryCache;
  } catch (e) {
    discoveryError = e;
    throw e;
  }
}

function sessionFromRequest(req) {
  const cookies = parseCookies(req);
  const fromCookie = verifySessionToken(cookies[SESSION_COOKIE]);
  if (fromCookie) return fromCookie;

  const auth = String(req.headers.authorization || '');
  if (auth.startsWith('Bearer ')) {
    return verifySessionToken(auth.slice(7));
  }
  return null;
}

async function handleAuthLogin(req, res) {
  if (!isConfigured()) {
    res.writeHead(302, { Location: '/?sso_error=not_configured' });
    res.end();
    return;
  }
  try {
    const discovery = await getDiscovery();
    const state = crypto.randomBytes(24).toString('hex');
    const params = new URLSearchParams({
      client_id: SSO_CLIENT_ID,
      redirect_uri: SSO_REDIRECT_URI,
      response_type: 'code',
      scope: SSO_SCOPES,
      state,
    });
    res.setHeader('Set-Cookie', cookieHeader(STATE_COOKIE, state, 600));
    res.writeHead(302, { Location: `${discovery.authorization_endpoint}?${params}` });
    res.end();
  } catch (e) {
    console.error('handleAuthLogin:', e);
    res.writeHead(302, { Location: '/?sso_error=discovery_failed' });
    res.end();
  }
}

async function handleAuthCallback(req, res, sendJson, readBody) {
  if (!isConfigured()) {
    sendJson(req, res, 503, { error: 'SSO not configured on server' });
    return;
  }
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  try {
    const body = await readBody(req);
    const code = String(body.code || '').trim();
    const state = String(body.state || '').trim();
    if (!code) {
      sendJson(req, res, 400, { error: 'Missing authorization code' });
      return;
    }
    const cookies = parseCookies(req);
    const expectedState = cookies[STATE_COOKIE];
    if (!expectedState || !state || expectedState !== state) {
      sendJson(req, res, 400, { error: 'Invalid OAuth state' });
      return;
    }

    const discovery = await getDiscovery();
    const tokenRes = await fetch(discovery.token_endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'authorization_code',
        code,
        redirect_uri: SSO_REDIRECT_URI,
        client_id: SSO_CLIENT_ID,
        client_secret: SSO_CLIENT_SECRET,
      }),
      signal: AbortSignal.timeout(30000),
    });
    const tokenRaw = await tokenRes.text();
    if (!tokenRes.ok) {
      sendJson(req, res, 502, {
        error: 'Token exchange failed',
        detail: tokenRaw.slice(0, 500),
      });
      return;
    }
    const tokens = JSON.parse(tokenRaw);
    const claims = parseIdTokenClaims(tokens.id_token) || {};
    let email = String(claims.email || claims.preferred_username || '')
      .trim()
      .toLowerCase();
    if (email && !email.includes('@')) {
      email = `${email}@hku.hk`;
    }
    const sub = String(claims.sub || '').trim();
    const name = String(claims.name || claims.given_name || '').trim();
    const uid = String(claims.uid || '').trim();
    const hkuno = String(claims.hkuno || '').trim();
    const accountType = String(claims.account_type || '').trim();
    if (!email && !sub && !uid) {
      sendJson(req, res, 502, {
        error: 'OIDC token missing email/sub/uid claims (need scope openid hku)',
      });
      return;
    }

    const sessionJwt = signSessionToken({
      sub: sub || uid || email,
      email: email || (uid ? `${uid}@hku.hk` : ''),
      name,
      uid: uid || null,
      hkuno: hkuno || null,
      accountType: accountType || null,
      idToken: String(tokens.id_token || '').trim() || null,
      provider: 'hku-oidc',
    });
    res.setHeader('Set-Cookie', [
      cookieHeader(SESSION_COOKIE, sessionJwt, SESSION_MAX_AGE_SEC),
      clearCookieHeader(STATE_COOKIE),
    ]);
    sendJson(req, res, 200, {
      ok: true,
      email,
      name,
      accessToken: sessionJwt,
    });
  } catch (e) {
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

async function handleAuthSession(req, res, sendJson) {
  const session = sessionFromRequest(req);
  if (!session) {
    sendJson(req, res, 200, { authenticated: false });
    return;
  }
  const token =
    parseCookies(req)[SESSION_COOKIE] ||
    String(req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  sendJson(req, res, 200, {
    authenticated: true,
    email: session.email || null,
    name: session.name || null,
    sub: session.sub || null,
    accessToken: token || null,
  });
}

async function handleAuthLogout(req, res) {
  const session = sessionFromRequest(req);
  const idTokenHint = session?.idToken ? String(session.idToken).trim() : '';
  res.setHeader('Set-Cookie', clearCookieHeader(SESSION_COOKIE));
  if (isConfigured()) {
    try {
      const discovery = await getDiscovery();
      if (discovery.end_session_endpoint) {
        const params = new URLSearchParams({
          post_logout_redirect_uri: SSO_POST_LOGOUT_REDIRECT_URI,
        });
        if (idTokenHint) {
          params.set('id_token_hint', idTokenHint);
        }
        res.writeHead(302, {
          Location: `${discovery.end_session_endpoint}?${params}`,
        });
        res.end();
        return;
      }
    } catch (_) {}
  }
  res.writeHead(302, { Location: '/' });
  res.end();
}

function toAuthSession(session) {
  if (!session) return null;
  const email = String(session.email || '').trim().toLowerCase();
  const sub = String(session.sub || '').trim();
  return {
    uid: sub ? `oidc:${sub}` : `oidc:${email}`,
    email,
    name: session.name || null,
    authProvider: 'oidc',
  };
}

module.exports = {
  isConfigured,
  sessionFromRequest,
  toAuthSession,
  handleAuthLogin,
  handleAuthCallback,
  handleAuthSession,
  handleAuthLogout,
  getDiscovery,
};
