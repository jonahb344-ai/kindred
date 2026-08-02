# AGENTS.md — Kindred project memory

## What this is
Kindred is a neighborhood kindness app (Flutter + Firebase) where users post/claim small
favors, chat, earn points/levels, and verify acts with AI. Built by Jonah (8th grader),
public on GitHub as `jonahb344-ai/kindred`. **This file contains NO secrets** (repo is
public); secret values live only in the files/locations referenced below.

## SAVING-MEMORY RULES (CRITICAL — follow every session)
- At the END of every user command where anything meaningful happened (code change, build,
  deploy, decision, fix, verification), UPDATE THIS FILE so nothing is lost.
- Cadence: ~every hour of active conversation. Since the AI only acts when prompted, saving
  happens at the end of commands, not on a timer — there is no background execution.
- Refresh: Current status, latest version/APK, decisions, new gotchas, and the work log below.
- NEVER write secrets/values here (password, API keys, tokens, service-account JSON). Point to
  their file locations instead.
- Keep the work log (below) as an append-only history of significant changes with dates.

## Current status
- Released v0.5.0 with signed APK on GitHub Releases; download link verified (byte-identical
  SHA-256). APK kept in `apks\v0.5.0\kindred.apk` (55.6 MB). App version (pubspec + Android
  versionName) is now 0.5.0; prior releases are v0.1.0 (history).
- Email/password sign-up ADDED with email verification: LoginScreen now has a Google button +
  a "Sign In / Create Account" tabbed email form (name, email, password). New email users get a
  Firebase verification email (`sendEmailVerification`); unverified email/password users are
  blocked by a VerifyEmailScreen gate in AuthGate (resend + "I've verified" + sign out). Requires
  the Email/Password provider to be ENABLED in Firebase Console Authentication → Sign-in method.
- Share features are intentionally GATED for beta: Share app / Share Profile show a snackbar
  "Sharing comes with the full app release — Kindred is in beta!". The QR code image was
  removed (it was a share feature); the QR icon still opens a restored profile sheet showing
  the user's @name plus the gated Share Profile button.
- Push notifications fully wired end-to-end (see "Push" below).
- Google Sign-In release fingerprint was ADDED by the user (confirm fresh-install works).
- App store readiness NOT finished: package id is still `com.example.kindred_app` (rejected by
  Google Play), app label is `kindred_app`, no custom icon, no privacy policy.

## Build & commands
- Release APK: `flutter build apk --release`
- Output: `build\app\outputs\flutter-apk\app-release.apk`; saved copies in `apks\<version>\kindred.apk`
- Analyze: `flutter analyze` (baseline is ~15 info-level style lints; no errors/warnings)
- Tests: `flutter test` (test/widget_test.dart — 2 tests, pass)
- This machine: Windows PowerShell. Git installed at `C:\Program Files\Git\cmd\git.exe`
  (not on PATH in fresh shells). Node/firebase CLI needs
  `NODE_OPTIONS=--dns-result-order=ipv4first` (IPv6 timeouts). winget is available.
- flutter_local_notifications v22 API uses NAMED params: `initialize(settings:)`,
  `show(id:, title:, body:, notificationDetails:)`.

## Signing (Android)
- Keystore: `android\app\upload-keystore.jks` (alias `upload`)
- Config: `android\key.properties` — contains the keystore password IN PLAINTEXT.
- Both are gitignored — **back them up; losing them makes future app updates impossible.**
- Release cert SHA-1: `E9:CD:30:F8:BD:98:DC:1F:11:0C:A5:54:F1:12:E4:8F:C5:7F:D7:BA`
  (registered in Firebase Console for Google Sign-In in release builds).
- Debug SHA-1 was already registered (debug sign-in works).
- `android/app/src/main/AndroidManifest.xml` now has INTERNET, POST_NOTIFICATIONS,
  ACCESS_FINE/COARSE_LOCATION. The release APK previously had NO network permission (only the
  debug manifest had INTERNET) — that was fixed and verified via `aapt dump permissions`.

## Backend
- Firebase project `kindred-app-2fe7a` (display "kindred-app"), owner jonahb344@gmail.com,
  **Spark free plan (no Blaze)** — no Cloud Functions (abandoned; Blaze needs a card), no App
  Distribution, no Storage. All logic on a free Cloudflare Worker.
- Worker URL: `https://kindred.jonahb344.workers.dev` (source: `worker/worker.js`).
  DEPLOY NOW VIA WRANGLER CLI (dashboard editor was read-only on Jonah's account):
  `npx.cmd wrangler deploy worker/worker.js --name kindred --compatibility-date 2026-08-02`
  (account id `c9e624deea5ecde4a88898133608c639`, auth via `npx.cmd wrangler login`). Secrets
  live in Cloudflare dashboard (never in code) and survive code-only deploys.
- Worker secrets (in Cloudflare dashboard, never in code): `ANTHROPIC_API_KEY`,
  `SERVICE_ACCOUNT` (Firebase service-account JSON). Routes require a valid Firebase ID token
  in `Authorization: Bearer ...` (verified 401 without). `/verify` = AI kindness check
  (Anthropic claude-sonnet-4-6); `/push` = FCM HTTP v1 send using service-account OAuth
  (RS256 JWT signed with WebCrypto) + Firestore REST read of the target's fcmToken;
  `/notifyNearby` = after a request is posted, push + in-app notify users within
  NEARBY_RADIUS_KM (8) using each user's saved `users/{uid}/private/data.location`.
- App calls the Worker via `kServerBaseUrl` const in `lib/main.dart` and sends the user's ID
  token via `_authHeaders()`. Tokens are verified RS256 against Google's securetoken JWKS.
- Firestore rules deployed from `firestore.rules` (users/requests/chats/notifications locked
  to owners/participants; `users/{uid}/private/data` holds PII + fcmToken). `firebase.json`
  references firestore only; `storage.rules` exists but Storage was never enabled.
- Report-email feature uses FormSubmit → reporter address `jonahb344+kindred@gmail.com`
  (formsubmit.co one-time confirm was clicked).

## Push notifications
- Client: `lib/main.dart` — permission request + channel "kindred_notifications",
  `FirebaseMessaging.onBackgroundMessage`, `onMessage` → flutter_local_notifications show.
  FCM token saved to `users/{uid}/private/data.fcmToken` at sign-in.
- Triggers: claim request (:1653 area), act confirmed (:1711 area), chat message (:2033 area)
  → `_sendPushNotification(targetUid, title, body)` → Worker `/push` → FCM to recipient.

## GitHub / git
- Repo: `https://github.com/jonahb344-ai/kindred` (public, branch `main`, GPL-3.0 license).
- Commit identity: Jonah Boyd <jonahb344@gmail.com>.
- GitHub CLI not installed; auth via Git Credential Manager. A stored OAuth token can be
  retrieved with `git credential fill` (used for GitHub API calls if needed).
- Release v0.5.0 is now the LATEST release (release id 363900688, not draft/prerelease) with
  asset `kindred.apk` (SHA-256 `ED717A2C10BF98D37B9721399A3AF87B97C7C05CC7FE4859DBAB7BA2D95A2877`).
  The README "Download the APK" button links to
  `/releases/latest/download/kindred.apk` (verified byte-identical to `apks\v0.5.0\kindred.apk`).
  Older release v0.1.0 (id 363639925) kept as history.
- README is consumer-focused (intro, features, download, license) — user does NOT want the
  technical sections (architecture/security, build-from-source, worker deploy) or images in it.

## Work log (append-only)
- 2026-08-02 SESSION SAVED (Jonah restarting VS Code). Everything committed + pushed; working
  tree clean at commit 5bca369. Current release: v0.5.0 (see Current status above). All session
  work (chat Done button, chat presence, dialog button layout, Messages-tab merge fix, map-claim
  notify, version bump) is in the log below + on origin/main. No secrets in repo.
- 2026-08-02 Bumped app version to 0.5.0 everywhere: pubspec.yaml `version: 0.5.0+1`
  (drives Android versionName via flutter.versionName), `_appVersion` fallback in
  lib/main.dart -> 'bv0.5.0'. Rebuilt release APK (versionName verified 0.5.0 via aapt;
  versionCode 1), installed on phone (adb -r Success, running), saved to
  `apks\v0.5.0\kindred.apk` (SHA-256
  `ED717A2C10BF98D37B9721399A3AF87B97C7C05CC7FE4859DBAB7BA2D95A2877`). Tag v0.5.0 pushed;
  GitHub release v0.5.0 created (id 363900688) with asset `kindred.apk` (asset 499293319);
  README `/releases/latest/download/kindred.apk` verified byte-identical. Old release
  v0.1.0 kept as history. Committed ab70b9c + pushed. NOTE: a `flutter build` hung once
  (Gradle daemon 546s CPU) — killed the java process and rebuilt cleanly.
- 2026-08-01 Chat Done button + real dialog button fix. (1) ChatScreen now has a check-circle
  "Done" action (AppBar) that ONLY appears for the VOLUNTEER while the request is `claimed`:
  tapping it shows a "Done helping?" thank-you dialog, marks the request `completed` (new rule:
  either participant may set status -> completed; deployed to Firestore), writes a thank-you
  note volunteer->requester, awards the volunteer points, push + in-app notifies the requester,
  confetti. NOTE: the 2026-08-01 "dialog button rule" entry was WRONG — buttons were still
  stacking. Root cause: `AlertDialog.actions` renders via `OverflowBar`; two direct children
  wrap onto separate rows (Delete landed below Cancel) when they don't fit one row. REAL fix:
  every two-button dialog now puts both buttons inside a single `FittedBox(scaleDown) >
  Row(min)` child, so they're always ONE line, never wrapped/clipped. Destructive dialogs:
  Cancel LEFT + action RIGHT; non-destructive: action LEFT + Cancel/Skip RIGHT. Applied to
  `_KindredDialog`, the "Send a Thank You" dialog, and the new "Done helping?" dialog.
  Analyze clean (18 info style lints — 3 new from the if/else level chain, same pattern as
  existing code), tests pass, rules deployed, release APK rebuilt (SHA-256
  `BD0FA41A9FD1E68386D95BB8AB0D11AC13CA46FDC1D9E2B98A420E8F7C199237`), installed on phone
  (adb -r Success, launched), saved to apks\v0.1.0\kindred.apk. NOT yet committed.
- 2026-08-01 Chat presence + dialog button order. (1) In-app chat presence: ChatScreen now
  writes `chats/{chatId}` `presence.{myUid}` = serverTimestamp on open and deletes it on
  dispose; `_send()` skips the FCM push AND the in-app notification when the receiver's
  presence timestamp for that chat is < 60s old (so the person reading the chat isn't
  pinged). Uses the existing `chats/{chatId}` participant read/write rule — no rules change.
  (2) Dialog button rule: destructive dialogs (Delete chat/request/account, Block) show
  Cancel LEFT + action RIGHT; non-destructive confirmations (e.g. "I'll help" claim, Send
  a Thank You) show the action/OK LEFT + Cancel/Skip RIGHT. `_KindredDialog` now orders by
  the `destructive` flag; the "Send a Thank You" AlertDialog flipped to Send LEFT/Skip RIGHT.
  Analyze clean (15 info lints), tests pass, release APK rebuilt (SHA-256
  `42BC4ABFAD52C43DCBF53F6EDDFB4724A691EDA1BBBD80BCF06B9FFFD9AF2A11`), installed on phone
  (adb -r Success), saved to apks\v0.1.0\kindred.apk. NOT yet committed.
- 2026-08-01 Fixed Messages-tab visibility bug: `_chatStreams` merged the requester and
  volunteer request-queries by pushing EACH raw snapshot into a StreamController, so the
  list only ever showed ONE query's snapshot at a time (whichever arrived last). The
  requester's empty volunteer-query could override and hide their claimed conversation —
  only the claimer saw it. Rewrote to keep both latest snapshots and emit a deduped
  combined `List<QueryDocumentSnapshot>`. Also: the map-detail "I'll Help" claim path now
  notifies the requester (push + in-app notification) via a shared `_completeClaim()`
  helper (previously only the feed claim path notified). Analyze clean (15 info lints),
  tests pass, release APK rebuilt (SHA-256
  `17815469BCA54D6F114FF2B9BA41F14D80D51C6B8324C3E4CAB43ABDF8EC7E65`), installed on phone
  (adb -r Success), saved to apks\v0.1.0\kindred.apk. Emulator not connected during this
  install — re-install there from the saved APK when it is.
- 2026-08-01 Deployed worker via WRANGLER CLI (dashboard editor is read-only on Jonah's
  account). `npx.cmd wrangler login` (account c9e624deea5ecde4a88898133608c639) then
  `npx.cmd wrangler deploy worker/worker.js --name kindred --compatibility-date 2026-08-02`.
  Live-verified: /notifyNearby and /push both return 401 without a token (route live + secrets
  intact), /verified 200. New version id 7fd2763e-86ea-485a-aec1-7d573fc4c5ab.
- 2026-08-01 Notification UX + nearby requests: (a) Messages tab now clears its unread
  chat bubble just by opening the tab — ChatsListScreen became a StatefulWidget that marks
  all chat notifications (`chatId != null`) read when visible (and keeps clearing new ones
  while the tab is shown); (b) Help tab clears its non-chat bubble the same way
  (`_clearHelpNotificationBadge` in _HelpOthersScreenState); (c) nearby-request
  notifications: requests now store `lat`/`lng` at post time, users' locations are saved to
  `users/{uid}/private/data.location` on sign-in (`_ensureUserDoc`) and map load, and after
  posting the app calls new Worker route `POST /notifyNearby` which lists all users, keeps
  those within NEARBY_RADIUS_KM (8), skips the requester / mutual blocks / `notifRequests`
  off / no-location users, then FCM-pushes "New request near you!" + writes an in-app
  notification (chatId null → shows on Help bubble). NOTE: worker.js MUST be redeployed
  (paste into Cloudflare) for /notifyNearby to work; app tolerates a 404/error silently.
  Analyze clean (15 info lints), tests pass, release APK rebuilt (SHA-256
  `A253C2E7E352E0C8E6FC4A2406394688F1D078923BEEAA372D4DEEB967D11809`), installed on phone
  (adb -r Success) + saved to apks\v0.1.0\kindred.apk. Committed pending user decision.
- 2026-08-01 CHAT/MESSAGING FIXED (major): root cause was Firestore rules using `.exists`
  on `get()` results in `chatParticipant()`/`notifChatParticipant()` — `.exists` ALWAYS
  evaluates to false on this project, so every chat message read/write was 403 DENIED
  (sent messages vanished, nobody received them) and notification cleanup failed
  (chat deletion broken). Diagnosed live with a throwaway-user REST harness (created
  real users via Auth REST with the Android-restricted API key — note: the key's cert
  fingerprint is registered WITHOUT colons, e.g. `E9CD30F8...`, so spoof
  `X-Android-Cert` accordingly). Proved `.exists`→false even for existing docs while
  `.data.field`→works; removed `.exists`, now compare `.data.requesterId`/`.data.volunteerId`
  directly (missing doc → null → deny, intended). Live-tested: create/claim/send/read all
  pass, outsiders 403, orphaned-chat writes 403, both participants can delete messages and
  chat notifications. Client fixes: `_send()` no longer clears input before the write and
  shows "Message not sent" snackbar on failure; ChatScreen gained a block guard (hides chat
  if either user blocked the other) + "conversation no longer available" error state.
  Analyze clean (15 info lints), tests pass, release APK rebuilt (55.6 MB, SHA-256
  `10DE9A6BE6680E1E3C09A89C4772F48F05896CA27AC861B130C316EBFA3CB9C1`) and `adb install -r`
  Success; app launches (MainActivity foreground). Committed 04a4d49 + pushed; rules deployed.
  NOT yet uploaded to the GitHub release (waiting on user's hand-test of two-account messaging).
- 2026-08-01 Security overhaul: removed leaked Anthropic API key from client; moved PII
  (email/phone/fcmToken) to `users/{uid}/private`; wrote+deployed `firestore.rules`;
  set up release signing (keystore, key.properties, build.gradle.kts signingConfig).
- 2026-08-01 Abandoned Cloud Functions (Spark/no Blaze); built Cloudflare Worker; `/verify`
  live-tested; later implemented `/push` (FCM HTTP v1) + auth on both routes.
- 2026-08-01 Fixed release manifest: added INTERNET + POST_NOTIFICATIONS (+ normalized
  location perms). Verified with aapt. This made release APK actually network-capable.
- 2026-08-01 Wired push on the client: permission request, background handler, foreground
  local notifications, flutter_local_notifications v22 named-param API.
- 2026-08-01 Git for Windows installed via winget; repo initialized; public repo created;
  branch master→main; stale remote master deleted; GPL-3.0 LICENSE preserved; README written
  then simplified for end users; AGENTS.md added.
- 2026-08-01 Tag v0.1.0 pushed; release created; APK asset replaced via GitHub API with the
  current 55.5 MB build; download byte-verified. Worker endpoints re-verified 401.
- 2026-08-01 Share features gated for beta (Share app, Share Profile, QR) with snackbar;
  QR image removed; profile sheet restored with gated button; share_plus + qr_flutter imports
  removed; analyze clean; APK rebuilt + saved to `apks\v0.1.0\kindred.apk`.
- 2026-08-01 Email/password auth added: LoginScreen has a Google button + Sign In/Create Account
  email form (shared `_ensureUserDoc` helper for both flows, friendly error mapping). New users
  get a Firebase verification email; AuthGate blocks unverified email/password users behind a
  new VerifyEmailScreen (resend, "I've verified" reload+continue, sign out). Requires
  Email/Password provider enabled in Firebase Console. Analyze clean, tests pass, APK rebuilt
  (SHA-256 `1D97249743C83BA3AE61C11FA3368F4D334B3105DC45E2F91E7EB8DF0BBC4ABE`).
- 2026-08-01 "App not installed" FIXED on Jonah's Android 11 phone via adb: root cause was a
  stale debug-signed copy of the app installed in the phone's GUEST user profile (user 10).
  Android blocks a differently-signed install even across users, which manual uninstall
  (user 0 only) never removed. Fixed with `adb uninstall --user 10 com.example.kindred_app`,
  then `adb install apks\v0.1.0\kindred.apk` → Success. App verified running in foreground
  (mCurrentFocus = com.example.kindred_app/.MainActivity). Committed as fc7d7d4 + pushed.
- 2026-08-01 Re-uploaded `kindred.apk` to the v0.1.0 GitHub release (asset id 498487304, replaced
  old 498446948). README `releases/latest/download/kindred.apk` verified byte-identical to
  `apks\v0.1.0\kindred.apk` (SHA-256 `1D97249743C83BA3AE61C11FA3368F4D334B3105DC45E2F91E7EB8DF0BBC4ABE`).
- 2026-08-01 GitHub secret-scanning alert #1 (google_api_key in `android/app/google-services.json#L31`,
  present since initial commit 3d07b11) RESOLVED: the Firebase Android API key was restricted in
  Google Cloud Console to the Kindred Android app (package com.example.kindred_app + RELEASE SHA-1
  E9:CD:30:F8:BD:98:DC:1F:11:0C:A5:54:F1:12:E4:8F:C5:7F:D7:BA) by the user. Debug SHA-1
  (D6:49:C4:41:F5:67:6A:71:FC:7E:F7:6C:7F:08:FB:1B:9C:97:F4:54) was added later the same day, so
  debug `flutter run` builds work too. Note: google-services.json MUST stay committed (build
  requirement); the key is client-side, restriction is the correct mitigation.
- 2026-08-01 Fixed a CRITICAL Worker auth bug: `crypto.subtle.importKey`/`verify`/`sign` used the
  invalid WebCrypto algorithm name `'RS256'` (throws NotSupportedError; correct name is
  `'RSASSA-PKCS1-v1_5'`). This made Firebase ID token verification ALWAYS fail -> `/verify` returned
  401 for every real user, and `/push` (OAuth JWT signing) would fail too. Verified locally that
  Node/WebCrypto rejects `'RS256'`. Worker MUST be re-deployed (paste worker/worker.js into Cloudflare).
- 2026-08-01 Friendly verification emails: worker.js now serves a public `GET /verified` success
  page (on-brand HTML). App sends verification emails with
  `ActionCodeSettings(url: 'https://kindred.jonahb344.workers.dev/verified', handleCodeInApp: false)`
  so tapping the email link lands on that page. Requires: (a) redeploy worker, (b) add
  kindred.jonahb344.workers.dev to Firebase Console Authentication -> Settings -> Authorized domains.
  NOTE: Firebase LOCKS the verification-email body (anti-spam, since 2019) — only Sender name and
  Subject are editable in the template; custom body would need sending emails ourselves via an
  email service (e.g., Resend) from the Worker (deferred). APK rebuilt (SHA-256
  BC154004392F027BFB1A207531564E63DB3802657547458EA94BBDEFD1042A78), installed on phone (adb -r),
  uploaded to release (asset 498514290), verified byte-identical.

## Known gotchas / decisions
- User decision: Spark plan only (no card/billing), Cloudflare Worker free tier, public repo,
  GPL-3.0 license, beta-gate the share features, consumer-friendly README.
- App name shows as `kindred_app` and package is `com.example.kindred_app` — must be fixed
  before any app-store submission (Play auto-rejects `com.example`).
- Old Anthropic key (leaked earlier) should be revoked in the Anthropic console.
- Worker push uses FCM HTTP v1 (legacy API deprecated). Requires the service account secret.
- WebCrypto algorithm names in worker.js MUST be `RSASSA-PKCS1-v1_5` — `'RS256'` throws
  NotSupportedError and silently breaks ALL auth (do not reintroduce).
- Firestore rules: NEVER use `.exists` on `get()` results — it always evaluates to false on
  this project (proven live 2026-08-01) and silently breaks any rule relying on it. Use
  `.data.field` comparisons instead; a missing doc makes `.data` null and the comparison
  fails closed (deny).
- Dialog buttons: NEVER put two buttons as direct children of `AlertDialog.actions` — it
  renders via `OverflowBar` and wraps them onto separate rows when they don't fit one line.
  Always wrap both in a single `FittedBox(fit: scaleDown, alignment: centerRight) >
  Row(mainAxisSize: min)` so they stay on one line. Destructive dialogs = Cancel LEFT +
  action RIGHT; non-destructive = action LEFT + Cancel/Skip RIGHT.
- The `assets/*.jpg` images are used by the onboarding screens — do NOT delete.
- When worker.js changes, redeploy with `npx.cmd wrangler deploy worker/worker.js
  --name kindred --compatibility-date 2026-08-02` (dashboard editor is read-only on Jonah's
  account; secrets are preserved on code-only deploys).

## TODO / next steps
- Confirm fresh-install Google Sign-In works on the release build (fingerprint was added).
- If a new APK is built, re-upload it as `kindred.apk` to the release (API token via
  `git credential fill`) so the README button serves the latest.
- App store prep: change package id, app label, custom icon, privacy policy.
- Revoke the old leaked Anthropic key.
