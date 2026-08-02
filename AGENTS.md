# AGENTS.md — Kindred project memory

## What this is
Kindred is a neighborhood kindness app (Flutter + Firebase) where users post/claim small
favors, chat, earn points/levels, and verify acts with AI. Built by Jonah (8th grader),
public on GitHub as `jonahb344-ai/kindred`. **This file contains NO secrets** (repo is
public); secret values live only in the files/locations referenced below.

## Current status
- Released v0.1.0 with signed APK on GitHub Releases (download works, byte-verified).
- Share features are intentionally GATED for beta: tapping Share app / Share Profile / QR
  shows a snackbar "Sharing comes with the full app release — Kindred is in beta!".
  QR code image was removed; the QR icon still opens a profile sheet (name + gated button).
- Push notifications fully wired end-to-end (see "Push" below).
- App store readiness NOT finished: package id is still `com.example.kindred_app`
  (rejected by Google Play), app label is `kindred_app`, no custom icon, no privacy policy.

## Build & commands
- Release APK: `flutter build apk --release`
- Output: `build\app\outputs\flutter-apk\app-release.apk`; saved copies in `apks\<version>\kindred.apk`
- Analyze: `flutter analyze` (baseline is ~15 info-level style lints; no errors/warnings)
- Tests: `flutter test` (test/widget_test.dart — 2 tests, pass)
- This machine: Windows PowerShell. Git installed at `C:\Program Files\Git\cmd\git.exe`
  (not on PATH in fresh shells). Node/firebase CLI needs
  `NODE_OPTIONS=--dns-result-order=ipv4first` (IPv6 timeouts).

## Signing (Android)
- Keystore: `android\app\upload-keystore.jks` (alias `upload`)
- Config: `android\key.properties` — contains the keystore password IN PLAINTEXT.
- Both are gitignored — **back them up; losing them makes future app updates impossible.**
- Release cert SHA-1: `E9:CD:30:F8:BD:98:DC:1F:11:0C:A5:54:F1:12:E4:8F:C5:7F:D7:BA`
  (must be registered in Firebase Console Android app for Google Sign-In in release builds).
- Debug SHA-1 was already registered (debug sign-in works).

## Backend
- Firebase project `kindred-app-2fe7a` (display "kindred-app"), owner jonahb344@gmail.com,
  **Spark free plan (no Blaze)** — no Cloud Functions; all logic on a free Cloudflare Worker.
- Worker URL: `https://kindred.jonahb344.workers.dev` (source: `worker/worker.js`,
  deployed by pasting into Cloudflare dashboard).
- Worker secrets (in Cloudflare dashboard, never in code): `ANTHROPIC_API_KEY`,
  `SERVICE_ACCOUNT` (Firebase service-account JSON). Routes require a valid Firebase ID
  token in `Authorization: Bearer ...` (401 without). `/verify` = AI kindness check
  (Anthropic claude-sonnet-4-6); `/push` = FCM HTTP v1 send using service account OAuth.
- App calls the Worker via `kServerBaseUrl` const in `lib/main.dart` and sends the user's
  ID token via `_authHeaders()`. Tokens are verified with RS256 against Google's securetoken
  JWKS.
- Firestore rules deployed from `firestore.rules` (users/requests/chats/notifications
  locked to owners/participants; `users/{uid}/private/data` holds PII + fcmToken).
- `storage.rules` exists but Firebase Storage was never enabled in the project.
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
- Current git state is clean on `main`.

## Known gotchas / decisions
- Google Sign-In fingerprint: user was reminded multiple times; confirm it's added and that
  fresh-install release builds can log in before publicizing.
- App name shows as `kindred_app` and package is `com.example.kindred_app` — must be fixed
  before any app-store submission.
- Old Anthropic key (leaked earlier) should be revoked in the Anthropic console.
- Worker push uses FCM HTTP v1 (legacy API deprecated). Requires the service account secret.
- The `assets/*.jpg` images are used by the onboarding screens — do NOT delete.
