// One-time privacy migration for Kindred.
//
// Before v1.0.10, requests stored the poster's exact `lat`/`lng`. Since v1.0.10
// they store `approxLat`/`approxLng` (a random point within kAreaRadiusMi of the
// poster). This script finds every request that still has exact coordinates,
// writes an approximate point (if it has none yet) and deletes `lat`/`lng`.
//
// Auth: a Google OAuth access token with the cloud-platform scope for the
// kindred-app-2fe7a project. Get one with:
//   firebase projects:list        (refreshes the CLI token in configstore)
//   then copy tokens.access_token out of
//   %USERPROFILE%\.config\configstore\firebase-tools.json
//
// Usage:
//   $env:GOOGLE_ACCESS_TOKEN = "<token>"
//   node scripts/migrate_approx.js            # dry run, writes nothing
//   node scripts/migrate_approx.js --apply    # actually patch Firestore
//
// Kept deliberately small: one paged query, one batched :commit per page, so it
// costs a couple of Firestore reads per document and nothing else.

const PROJECT = process.env.FIRESTORE_PROJECT || 'kindred-app-2fe7a';
const TOKEN = process.env.GOOGLE_ACCESS_TOKEN;
const APPLY = process.argv.includes('--apply');
const AREA_RADIUS_MI = 0.25;
const PAGE = 300;

if (!TOKEN) {
  console.error('GOOGLE_ACCESS_TOKEN is not set. See the header of this file.');
  process.exit(1);
}

const DOCS = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
const HEADERS = { Authorization: 'Bearer ' + TOKEN, 'Content-Type': 'application/json' };

// Same maths as _approxSpot() in lib/main.dart: a uniform random point inside the
// area circle, so the map marker still lands inside the poster's real neighborhood.
function approx(lat, lng) {
  const angle = Math.random() * 2 * Math.PI;
  const dist = Math.sqrt(Math.random()) * AREA_RADIUS_MI;
  return {
    lat: lat + (dist * Math.cos(angle)) / 69.0,
    lng: lng + (dist * Math.sin(angle)) / (69.0 * Math.cos((lat * Math.PI) / 180)),
  };
}

function num(fields, key) {
  const v = fields && fields[key];
  return v && typeof v.doubleValue === 'number' ? v.doubleValue : null;
}

async function runQuery(offset) {
  const res = await fetch(`${DOCS}:runQuery`, {
    method: 'POST',
    headers: HEADERS,
    body: JSON.stringify({
      structuredQuery: {
        from: [{ collectionId: 'requests' }],
        limit: PAGE,
        offset,
      },
    }),
  });
  if (!res.ok) throw new Error(`runQuery ${res.status}: ${(await res.text()).slice(0, 300)}`);
  return res.json();
}

async function commit(writes) {
  const res = await fetch(`${DOCS}:commit`, {
    method: 'POST',
    headers: HEADERS,
    body: JSON.stringify({ writes }),
  });
  if (!res.ok) throw new Error(`commit ${res.status}: ${(await res.text()).slice(0, 300)}`);
  return res.json();
}

async function main() {
  let offset = 0;
  let seen = 0;
  let fixed = 0;
  let stripped = 0;

  for (;;) {
    const rows = await runQuery(offset);
    const docs = rows.filter((r) => r.document).map((r) => r.document);
    if (docs.length === 0) break;

    const writes = [];
    for (const doc of docs) {
      seen++;
      const f = doc.fields || {};
      const lat = num(f, 'lat');
      const lng = num(f, 'lng');
      if (lat === null || lng === null) continue;

      const hasApprox = num(f, 'approxLat') !== null && num(f, 'approxLng') !== null;
      const fields = {};
      if (!hasApprox) {
        const p = approx(lat, lng);
        fields.approxLat = { doubleValue: p.lat };
        fields.approxLng = { doubleValue: p.lng };
        fixed++;
      }
      stripped++;
      // lat/lng are in the update mask but absent from `fields`, which deletes
      // them. Everything not listed in the mask is left untouched.
      writes.push({
        update: { name: doc.name, fields },
        updateMask: { fieldPaths: [...Object.keys(fields), 'lat', 'lng'] },
      });
    }

    if (writes.length) {
      if (APPLY) {
        await commit(writes);
        console.log(`page @${offset}: patched ${writes.length}`);
      } else {
        console.log(`page @${offset}: would patch ${writes.length} (dry run)`);
      }
    }

    if (docs.length < PAGE) break;
    offset += PAGE;
  }

  console.log(
    `${APPLY ? 'DONE' : 'DRY RUN'} - scanned ${seen} requests, ` +
      `stripped exact coords from ${stripped}, added approx coords to ${fixed}`,
  );
  if (!APPLY) console.log('Re-run with --apply to write the changes.');
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
