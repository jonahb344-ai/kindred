// Kindred server-side helper (Cloudflare Worker, free tier)
//
// Routes:
//   POST /verify       -> AI kindness-act verification via Anthropic
//                         (requires a Firebase Auth ID token)
//   POST /push         -> FCM push notification to a user (reads their token from Firestore)
//                         (requires a Firebase Auth ID token)
//   POST /notifyNearby -> When a request is posted, push + in-app notify users whose
//                         saved location is within NEARBY_RADIUS_KM of the request
//                         (requires a Firebase Auth ID token)
//   GET  /verified     -> Public, friendly "email verified" page. Used as the continueUrl
//                         in the Firebase verification email link.
//   GET  /privacy      -> Public privacy policy page (used for the Google Play listing).
//
// Setup:
//   1. Free Cloudflare account (no credit card).
//   2. Workers & Pages -> Create -> Worker -> paste this file -> Deploy.
//   3. Settings -> Variables and Secrets -> add two secrets:
//        SERVICE_ACCOUNT      (paste the whole JSON from Firebase:
//                              Console -> Project settings -> Service accounts -> Generate new private key)
//        ANTHROPIC_API_KEY    (sk-ant-api03-...)
//   4. Use the *.workers.dev URL in the app (kServerBaseUrl).
//   5. Add your *.workers.dev domain to Firebase Console -> Authentication -> Settings ->
//      Authorized domains (needed so the verification email link can redirect here).

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === 'GET' && url.pathname === '/verified') {
      return verifiedPage();
    }
    if (request.method === 'GET' && url.pathname === '/privacy') {
      return privacyPage();
    }
    if (request.method === 'POST' && url.pathname === '/verify') {
      return handleVerify(request, env);
    }
    if (request.method === 'POST' && url.pathname === '/push') {
      return handlePush(request, env);
    }
    if (request.method === 'POST' && url.pathname === '/notifyNearby') {
      return handleNotifyNearby(request, env);
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

// ─── /verified (public friendly page) ────────────────────────────────────────

const VERIFIED_PAGE = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Email verified — Kindred</title>
<style>
  body{margin:0;font-family:Roboto,'Segoe UI',Arial,sans-serif;background:#f0fdf9;display:flex;align-items:center;justify-content:center;min-height:100vh;}
  .card{background:#fff;border-radius:24px;padding:48px 36px;max-width:380px;width:90%;box-shadow:0 20px 60px rgba(13,148,136,0.2);text-align:center;}
  .badge{width:80px;height:80px;border-radius:50%;background:#d1fae5;display:flex;align-items:center;justify-content:center;margin:0 auto 24px;font-size:38px;}
  h1{color:#0f172a;font-size:26px;margin:0 0 12px;}
  p{color:#475569;font-size:15px;line-height:1.7;margin:0 0 24px;}
  .steps{text-align:left;background:#f8fafc;border:1px solid #e2e8f0;border-radius:12px;padding:16px 20px;color:#334155;font-size:14px;line-height:2;}
  .step{display:flex;align-items:center;gap:8px;}
  .step b{color:#0d9488;}
</style>
</head>
<body>
  <div class="card">
    <div class="badge">&#10004;&#65039;</div>
    <h1>You&#39;re verified!</h1>
    <p>Your email is confirmed. You&#39;re officially part of the Kindred neighborhood.</p>
    <div class="steps">
      <div class="step"><b>1</b> Open the Kindred app</div>
      <div class="step"><b>2</b> Tap <b>&quot;I&#39;ve verified — Continue&quot;</b></div>
    </div>
    <p style="font-size:13px;color:#94a3b8;margin-top:24px;">Then start helping your neighbors! &#128591;</p>
  </div>
</body>
</html>`;

function verifiedPage() {
  return new Response(VERIFIED_PAGE, {
    status: 200,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
    },
  });
}

// ─── /privacy (public page) ───────────────────────────────────────────────────

const PRIVACY_PAGE = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Privacy Policy — Kindred</title>
<style>
  body{margin:0;font-family:Roboto,'Segoe UI',Arial,sans-serif;background:#f5f8fa;color:#0f172a;line-height:1.7;}
  .wrap{max-width:720px;margin:0 auto;padding:48px 24px 80px;}
  h1{font-size:30px;margin:0 0 8px;}
  .updated{color:#64748b;font-size:13px;margin-bottom:32px;}
  h2{font-size:19px;margin:32px 0 8px;color:#0d9488;}
  p,li{font-size:15px;color:#334155;}
  ul{padding-left:22px;}
  a{color:#0d9488;}
  .card{background:#fff;border:1px solid #e2e8f0;border-radius:16px;padding:20px 24px;margin-top:16px;}
</style>
</head>
<body>
  <div class="wrap">
    <h1>Privacy Policy</h1>
    <div class="updated">Last updated: August 3, 2026</div>

    <div class="card">
      <p>Kindred ("we", "our") is a neighborhood kindness app that lets neighbors post and
      claim small favors, chat, earn points, and celebrate acts of kindness. This policy explains
      what information we collect, why we collect it, and how we keep it safe. We keep things
      simple: <b>we never sell your data</b>.</p>
    </div>

    <h2>1. Information we collect</h2>
    <ul>
      <li><b>Account info</b>: your name, email address, and profile photo when you sign in with
      Google or email/password.</li>
      <li><b>Profile info you add</b>: your username, a short bio, and optional phone number.</li>
      <li><b>Location</b>: with your permission, your approximate location so we can show nearby
      requests and notify neighbors within ~8 km of a new request. You can turn this off anytime
      in your device settings or the app.</li>
      <li><b>Your activity</b>: kindness requests you post, chats you have with neighbors,
      acts you log, points and badges, and thank-you notes.</li>
      <li><b>Device info</b>: a push-notification token so we can alert you about new requests
      and messages.</li>
      <li><b>Content you submit for verification</b>: the description (and optional photo) of an
      act, which is checked by an AI to confirm it is genuine kindness. Your photo is used only
      for that check and is not stored.</li>
    </ul>

    <h2>2. How we use your information</h2>
    <ul>
      <li>To run the app: show requests, connect you with helpers, send messages and notifications.</li>
      <li>To verify kindness acts and reward points and badges.</li>
      <li>To keep the community safe: block users, review reported content, and prevent abuse.</li>
      <li>To improve the app and provide support.</li>
    </ul>

    <h2>3. How we share information</h2>
    <ul>
      <li>With your neighbors: your name, photo, username, and posted requests are visible to
      other app users so people can help each other.</li>
      <li>With service providers that run the app (Google Firebase for accounts, storage, and
      push notifications; Cloudflare for server-side helpers; Anthropic for AI kindness
      verification). They only access data as needed to provide these services.</li>
      <li>We never sell or rent your personal information.</li>
      <li>We may disclose information if required by law or to protect the rights and safety of
      users and the public.</li>
    </ul>

    <h2>4. Data you share with others</h2>
    <p>Chats, requests, and acts you post are shared with the people you interact with. Please
    only share what you're comfortable with.</p>

    <h2>5. Your choices and rights</h2>
    <ul>
      <li>Edit or remove profile info, delete your requests and chats at any time.</li>
      <li>Turn off location or push notifications in your device settings.</li>
      <li>Delete your account and data through the app (Settings &rarr; Delete Account).</li>
      <li>Request a copy of your data or ask questions by emailing us (below).</li>
    </ul>

    <h2>6. Data retention and security</h2>
    <p>We keep your data only as long as needed to run the app, and use industry-standard
    security (encryption in transit and at rest, restricted access). When you delete your
    account, your profile data is removed.</p>

    <h2>7. Children's privacy</h2>
    <p>Kindred is intended for users 13 and older. We don't knowingly collect personal
    information from children under 13. If you believe a child has provided us personal
    information, contact us and we'll delete it.</p>

    <h2>8. Changes to this policy</h2>
    <p>If we make significant changes, we'll update this page and note the new date above.</p>

    <h2>9. Contact us</h2>
    <p>Questions about this policy? Email:
    <a href="mailto:jonahb344+kindred@gmail.com">jonahb344+kindred@gmail.com</a></p>
  </div>
</body>
</html>`;

function privacyPage() {
  return new Response(PRIVACY_PAGE, {
    status: 200,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
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
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['verify']
    );

    const data = new TextEncoder().encode(parts[0] + '.' + parts[1]);
    const valid = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', cryptoKey, base64UrlDecode(parts[2]), data);
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
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  );
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', privateKey, new TextEncoder().encode(unsigned));
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

function fieldValue(fields, key) {
  const v = fields && fields[key];
  if (!v) return null;
  if (v.stringValue !== undefined) return v.stringValue;
  if (v.booleanValue !== undefined) return v.booleanValue;
  if (v.doubleValue !== undefined) return v.doubleValue;
  if (v.integerValue !== undefined) return Number(v.integerValue);
  if (v.mapValue) return v.mapValue.fields;
  if (v.arrayValue) return v.arrayValue.values;
  return null;
}

function arrayOfStrings(fields, key) {
  const v = fields && fields[key];
  if (!v || !v.arrayValue) return [];
  return (v.arrayValue.values || [])
    .map((x) => (x && x.stringValue) || '')
    .filter(Boolean);
}

function haversineKm(lat1, lon1, lat2, lon2) {
  const R = 6371;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
  return 2 * R * Math.asin(Math.sqrt(a));
}

async function listUsers(token, projectId) {
  const users = [];
  let pageToken = '';
  for (let page = 0; page < 20; page++) {
    const url =
      'https://firestore.googleapis.com/v1/projects/' +
      projectId +
      '/databases/(default)/documents/users?pageSize=300' +
      (pageToken ? '&pageToken=' + encodeURIComponent(pageToken) : '');
    const resp = await fetch(url, { headers: { Authorization: 'Bearer ' + token } });
    if (!resp.ok) return users;
    const data = await resp.json();
    for (const doc of data.documents || []) {
      const name = doc.name || '';
      const uid = name.slice(name.lastIndexOf('/') + 1);
      users.push({ uid, fields: doc.fields || {} });
    }
    pageToken = data.nextPageToken || '';
    if (!pageToken) break;
  }
  return users;
}

async function sendFcm(sa, token, title, body) {
  const oauth = await getOAuthToken(sa);
  const resp = await fetch(
    'https://fcm.googleapis.com/v1/projects/' + sa.project_id + '/messages:send',
    {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + oauth, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message: { token, notification: { title, body } },
      }),
    }
  );
  return resp.ok;
}

async function writeNotification(sa, notif) {
  const oauth = await getOAuthToken(sa);
  const id = crypto.randomUUID();
  const name =
    'projects/' +
    sa.project_id +
    '/databases/(default)/documents/notifications/' +
    id;
  const fields = {
    toUid: { stringValue: notif.toUid },
    fromName: { stringValue: notif.fromName },
    title: { stringValue: notif.title },
    body: { stringValue: notif.body },
    read: { booleanValue: false },
    createdAt: { timestampValue: new Date().toISOString() },
  };
  const resp = await fetch(
    'https://firestore.googleapis.com/v1/projects/' + sa.project_id + '/databases/(default)/documents:commit',
    {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + oauth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ writes: [{ document: { name, fields } }] }),
    }
  );
  return resp.ok;
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

// ─── /notifyNearby ────────────────────────────────────────────────────────────

const NEARBY_RADIUS_KM = 8;

async function handleNotifyNearby(request, env) {
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

  const requestId = String(body.requestId || '');
  if (!requestId) {
    return json({ error: 'Missing requestId' }, 400);
  }

  try {
    const oauth = await getOAuthToken(sa);

    const reqDoc = await readFirestoreDoc(oauth, sa.project_id, 'requests/' + encodeURIComponent(requestId));
    if (!reqDoc) {
      return json({ error: 'Request not found' }, 404);
    }
    const reqLat = reqDoc.lat && reqDoc.lat.doubleValue;
    const reqLng = reqDoc.lng && reqDoc.lng.doubleValue;
    if (reqLat === undefined || reqLng === undefined) {
      return json({ notified: 0, reason: 'Request has no location' });
    }

    const requesterId = fieldValue(reqDoc, 'requesterId');
    const requesterName = fieldValue(reqDoc, 'requesterName') || 'Someone';
    const category = fieldValue(reqDoc, 'category') || 'a request';

    const users = await listUsers(oauth, sa.project_id);
    let requesterBlocked = [];
    for (const u of users) {
      if (u.uid === requesterId) {
        requesterBlocked = arrayOfStrings(u.fields, 'blockedUsers');
        break;
      }
    }

    const title = 'New request near you!';
    let notified = 0;
    for (const u of users) {
      if (u.uid === requesterId) continue;
      if (fieldValue(u.fields, 'notifRequests') === false) continue;
      if (arrayOfStrings(u.fields, 'blockedUsers').includes(requesterId)) continue;
      if (requesterBlocked.includes(u.uid)) continue;

      const priv = await readFirestoreDoc(
        oauth,
        sa.project_id,
        'users/' + encodeURIComponent(u.uid) + '/private/data'
      );
      if (!priv) continue;
      const loc = fieldValue(priv, 'location');
      const token = fieldValue(priv, 'fcmToken');
      if (!loc || !token) continue;
      const lat = fieldValue(loc, 'lat');
      const lng = fieldValue(loc, 'lng');
      if (lat === null || lng === null) continue;
      if (haversineKm(reqLat, reqLng, lat, lng) > NEARBY_RADIUS_KM) continue;

      const bodyMsg = requesterName + ' needs ' + category + ' near you';
      try {
        await sendFcm(sa, token, title, bodyMsg);
        await writeNotification(sa, {
          toUid: u.uid,
          fromName: requesterName,
          title,
          body: requesterName + ' posted: ' + category,
        });
        notified++;
      } catch (e) {
        // keep going even if one user fails
      }
    }
    return json({ notified });
  } catch (e) {
    return json({ error: 'notifyNearby failed: ' + (e && e.message) }, 500);
  }
}
