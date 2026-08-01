// Kindred server-side helper (Cloudflare Worker, free tier)
//
// Routes (all require a Firebase Auth ID token in `Authorization: Bearer <token>`):
//   POST /verify  -> AI kindness-act verification via Anthropic
//   POST /push    -> FCM push notification to a user (reads their token from Firestore)
//
// Setup:
//   1. Free Cloudflare account (no credit card).
//   2. Workers & Pages -> Create -> Worker -> paste this file -> Deploy.
//   3. Settings -> Variables and Secrets -> add two secrets:
//        SERVICE_ACCOUNT      (paste the whole JSON from Firebase:
//                              Console -> Project settings -> Service accounts -> Generate new private key)
//        ANTHROPIC_API_KEY    (sk-ant-api03-...)
//   4. Use the *.workers.dev URL in the app (kServerBaseUrl).

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === 'POST' && url.pathname === '/verify') {
      return handleVerify(request, env);
    }
    if (request.method === 'POST' && url.pathname === '/push') {
      return handlePush(request, env);
    }
    return json({ error: 'Not found' }, 404);
  },
};

// ─── Helpers ─────────────────────────────────────────────────────────────────

function json(obj, status) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
    },
  });
}

function requestAuthHeader(request) {
  const h = request.headers.get('Authorization') || '';
  return h.startsWith('Bearer ') ? h.slice(7) : '';
}

// ─── Base64 / JWT helpers ────────────────────────────────────────────────────

function base64UrlDecode(s) {
  s = String(s).replace(/-/g, '+').replace(/_/g, '/');
  while (s.length % 4) s += '=';
  const bin = atob(s);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

function bytesToBase64Url(bytes) {
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function strToBase64Url(str) {
  return bytesToBase64Url(new TextEncoder().encode(str));
}

function decodeJson(segment) {
  return JSON.parse(new TextDecoder().decode(base64UrlDecode(segment)));
}

// ─── Firebase ID token verification ──────────────────────────────────────────

const FIREBASE_JWKS_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

let jwksCache = { keys: null, fetchedAt: 0 };

async function getSigningKey(kid) {
  const now = Date.now();
  if (!jwksCache.keys || now - jwksCache.fetchedAt > 3600000) {
    const resp = await fetch(FIREBASE_JWKS_URL);
    if (!resp.ok) return null;
    const data = await resp.json();
    jwksCache = { keys: data.keys || [], fetchedAt: now };
  }
  return jwksCache.keys.find((k) => k.kid === kid) || null;
}

async function verifyFirebaseIdToken(idToken, projectId) {
  try {
    const parts = String(idToken || '').split('.');
    if (parts.length !== 3) return null;

    const header = decodeJson(parts[0]);
    if (header.alg !== 'RS256') return null;

    const jwk = await getSigningKey(header.kid);
    if (!jwk) return null;

    const cryptoKey = await crypto.subtle.importKey(
      'jwk',
      { kty: 'RSA', n: jwk.n, e: jwk.e, alg: 'RS256', use: 'sig' },
      { name: 'RS256', hash: 'SHA-256' },
      false,
      ['verify']
    );

    const data = new TextEncoder().encode(parts[0] + '.' + parts[1]);
    const valid = await crypto.subtle.verify('RS256', cryptoKey, base64UrlDecode(parts[2]), data);
    if (!valid) return null;

    const payload = decodeJson(parts[1]);
    const now = Math.floor(Date.now() / 1000);
    if (payload.exp < now) return null;
    if (payload.aud !== projectId) return null;
    if (payload.iss !== 'https://securetoken.google.com/' + projectId) return null;
    return payload;
  } catch (e) {
    return null;
  }
}

// ─── Service account + OAuth2 token ──────────────────────────────────────────

let saCache = null;
let oauthCache = { token: null, expiresAt: 0 };

function getServiceAccount(env) {
  if (saCache) return saCache;
  if (!env.SERVICE_ACCOUNT) return null;
  try {
    saCache = JSON.parse(env.SERVICE_ACCOUNT);
    return saCache;
  } catch (e) {
    return null;
  }
}

function pemToBinary(pem) {
  const b64 = String(pem)
    .replace(/-----BEGIN [^-]*-----/g, '')
    .replace(/-----END [^-]*-----/g, '')
    .replace(/\s+/g, '');
  return base64UrlDecode(b64);
}

async function getOAuthToken(sa) {
  if (oauthCache.token && Date.now() < oauthCache.expiresAt) return oauthCache.token;

  const now = Math.floor(Date.now() / 1000);
  const tokenUri = sa.token_uri || 'https://oauth2.googleapis.com/token';
  const header = { alg: 'RS256', typ: 'JWT' };
  const claims = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/cloud-platform',
    aud: tokenUri,
    iat: now,
    exp: now + 3600,
  };
  const unsigned = strToBase64Url(JSON.stringify(header)) + '.' + strToBase64Url(JSON.stringify(claims));

  const privateKey = await crypto.subtle.importKey(
    'pkcs8',
    pemToBinary(sa.private_key),
    { name: 'RS256', hash: 'SHA-256' },
    false,
    ['sign']
  );
  const sig = await crypto.subtle.sign('RS256', privateKey, new TextEncoder().encode(unsigned));
  const jwt = unsigned + '.' + bytesToBase64Url(new Uint8Array(sig));

  const resp = await fetch(tokenUri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body:
      'grant_type=' +
      encodeURIComponent('urn:ietf:params:oauth:grant-type:jwt-bearer') +
      '&assertion=' +
      encodeURIComponent(jwt),
  });
  if (!resp.ok) {
    const t = (await resp.text()).slice(0, 200);
    throw new Error('OAuth failed: ' + resp.status + ' ' + t);
  }
  const data = await resp.json();
  oauthCache.token = data.access_token;
  oauthCache.expiresAt = Date.now() + (data.expires_in - 60) * 1000;
  return oauthCache.token;
}

// ─── Firestore + FCM ─────────────────────────────────────────────────────────

async function readFirestoreDoc(token, projectId, docPath) {
  const url =
    'https://firestore.googleapis.com/v1/projects/' +
    projectId +
    '/databases/(default)/documents/' +
    docPath;
  const resp = await fetch(url, { headers: { Authorization: 'Bearer ' + token } });
  if (!resp.ok) return null;
  const data = await resp.json();
  return data.fields || {};
}

// ─── /verify ─────────────────────────────────────────────────────────────────

async function handleVerify(request, env) {
  const sa = getServiceAccount(env);
  if (!sa) {
    return json({ error: 'SERVICE_ACCOUNT is not configured on this Worker' }, 500);
  }
  const auth = await verifyFirebaseIdToken(requestAuthHeader(request), sa.project_id);
  if (!auth) {
    return json({ error: 'Unauthorized' }, 401);
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'Invalid JSON body' }, 400);
  }

  if (!env.ANTHROPIC_API_KEY) {
    return json({ error: 'ANTHROPIC_API_KEY is not configured on this Worker' }, 500);
  }

  const description = String(body.description || '').slice(0, 2000);
  const imageBase64 = body.imageBase64 ? String(body.imageBase64) : null;

  if (!description.trim()) {
    return json({ error: 'Missing description' }, 400);
  }
  if (imageBase64 && imageBase64.length > 5 * 1000 * 1000) {
    return json({ error: 'Image too large' }, 400);
  }

  const content = [];
  if (imageBase64) {
    content.push({ type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: imageBase64 } });
  }
  const prompt =
    `A user is logging a kindness act. They described what they did as: "${description}".` +
    (imageBase64
      ? ' They also attached a photo as evidence — check that it plausibly matches the description (it might show groceries, a yard, a dog, a meal, a car, etc.). Be lenient on photo quality, but reject clear mismatches.'
      : '') +
    ' Decide if the description (and photo, if provided) is a genuine, plausible act of kindness or community help, not self-serving, vague, or an obvious cheat. Be generous but not gullible. Reply ONLY with JSON: {"approved": true or false, "reason": "short explanation", "category": "one of: Grocery Run, Lawn Care, Moving Help, Pet Care, Meal Prep, Give a Ride, Other"}';
  content.push({ type: 'text', text: prompt });

  try {
    const resp = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': env.ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: 'claude-sonnet-4-6',
        max_tokens: 300,
        messages: [{ role: 'user', content }],
      }),
    });

    if (!resp.ok) {
      const errText = (await resp.text()).slice(0, 300);
      return json({ error: 'Anthropic error: ' + resp.status + ' ' + errText }, 502);
    }

    const data = await resp.json();
    const text = (data.content || []).map((block) => block.text || '').join('');
    const clean = text.replace(/```json/gi, '').replace(/```/g, '').trim();
    const start = clean.indexOf('{');
    const end = clean.lastIndexOf('}');
    if (start === -1 || end === -1) {
      return json({ error: 'Bad AI response' }, 502);
    }
    const result = JSON.parse(clean.slice(start, end + 1));

    return json({
      approved: result.approved === true || result.approved === 'true',
      reason: String(result.reason || ''),
      category: String(result.category || 'Other'),
    });
  } catch (e) {
    return json({ error: 'Verification failed: ' + (e && e.message) }, 500);
  }
}

// ─── /push ───────────────────────────────────────────────────────────────────

async function handlePush(request, env) {
  const sa = getServiceAccount(env);
  if (!sa) {
    return json({ error: 'SERVICE_ACCOUNT is not configured on this Worker' }, 500);
  }
  const auth = await verifyFirebaseIdToken(requestAuthHeader(request), sa.project_id);
  if (!auth) {
    return json({ error: 'Unauthorized' }, 401);
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'Invalid JSON body' }, 400);
  }

  const targetUid = String(body.targetUid || '');
  const title = String(body.title || 'Kindred').slice(0, 200);
  const messageBody = String(body.body || '').slice(0, 500);

  if (!targetUid) {
    return json({ error: 'Missing targetUid' }, 400);
  }

  try {
    const oauth = await getOAuthToken(sa);
    const fields = await readFirestoreDoc(
      oauth,
      sa.project_id,
      'users/' + encodeURIComponent(targetUid) + '/private/data'
    );
    const targetToken = fields && fields.fcmToken && fields.fcmToken.stringValue;
    if (!targetToken) {
      return json({ sent: false, message: 'No FCM token for target user' }, 200);
    }

    const resp = await fetch(
      'https://fcm.googleapis.com/v1/projects/' + sa.project_id + '/messages:send',
      {
        method: 'POST',
        headers: { Authorization: 'Bearer ' + oauth, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: { token: targetToken, notification: { title, body: messageBody } },
        }),
      }
    );
    if (!resp.ok) {
      const t = (await resp.text()).slice(0, 200);
      return json({ sent: false, error: 'FCM error: ' + resp.status + ' ' + t }, 502);
    }
    return json({ sent: true });
  } catch (e) {
    return json({ error: 'Push failed: ' + (e && e.message) }, 500);
  }
}
