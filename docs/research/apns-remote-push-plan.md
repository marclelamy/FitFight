# APNs — final-sync reminders

Companion to [`pending-final-sync-plan.md`](pending-final-sync-plan.md). **Do not implement tonight.** Slice D–G tomorrow, after the pending UI is honest.

Nothing in this repo sends push today. `docs/status.md` blocked notifications until the backlog said so. The backlog now says so **only** for this cadence.

---

## Locked cadence

Anchored to **`ends_at`**, not “when the closer first noticed.”

| Slot | When | Audience | `copy_key` idea |
|---|---|---|---|
| `t0` | `ends_at` | Every accepted member | Fight ended. Open FitFight. Pending variant: sync your steps. |
| `t12` | `ends_at + 12h` | Still `final_steps_complete = false` | 12 hours left. Open or you lose. |
| `t18` | `ends_at + 18h` | Still pending | 6 hours left. Open or you lose. |
| `t23` | `ends_at + 23h` | Still pending | Last hour. Open or you lose. |
| `final` | Fight becomes `final` | Every accepted member | Result is in. Open FitFight. |

Skip `t12` / `t18` / `t23` if that person already submitted. Cancel leftover grace intents when the fight finals early. One visible alert per `(fight_id, user_id, slot)`.

**“Open or you lose” is true** once Slice B (forfeit) ships. Do not send that line to people who already submitted.

---

## Lock-screen rules

Never interpolate:

- Step counts, gaps, ranks
- Fight title (`100$ openrouter` is user text and looks like a wager)
- Loser action
- Handles / names
- Money / € / $

Title = **FitFight**. Body = one sentence. Tap = `/fights/{uuid}` only.

Suggested bodies:

| Slot | EN | FR |
|---|---|---|
| t0 everyone | A fight ended. Open FitFight. | Un défi est terminé. Ouvrez FitFight. |
| t0 pending | A fight ended. Open FitFight to sync your steps. | Un défi est terminé. Ouvrez FitFight pour synchroniser vos pas. |
| t12 | 12 hours left. Open FitFight or you lose. | 12 heures restantes. Ouvrez FitFight ou vous perdez. |
| t18 | 6 hours left. Open FitFight or you lose. | 6 heures restantes. Ouvrez FitFight ou vous perdez. |
| t23 | Last hour. Open FitFight or you lose. | Dernière heure. Ouvrez FitFight ou vous perdez. |
| final | The result is in. Open FitFight. | Le résultat est tombé. Ouvrez FitFight. |

Do **not** put W/L or step totals on the lock screen even at `final`.

---

## What exists vs missing

| Exists | Missing |
|---|---|
| Closer + `awaiting_final_sync` + 24h grace | `aps-environment` in `FitFight.entitlements` |
| `CRON_SECRET` on `/api/internal/close-fights` | `UNUserNotificationCenter`, token register |
| AES-256-GCM pattern on `private.apple_sign_in_tokens` | `device_installations`, outbox |
| AASA `/j/*`, `/r/*` | AASA + `handleOpenURL` `/fights/*` |
| Daily Vercel cron 03:00 UTC | 15-minute worker |
| Review notes: “no push” | Must change before App Store, not before staging try |

---

## Tables (`private` only)

No `anon` / `authenticated` grants. Same as referrals / Apple tokens. Not granted to `fitfight_backend_reader`.

### `private.device_installations`

- `user_id` → profiles cascade
- `token_fingerprint` unique (SHA-256 of token)
- `encrypted_token` + `encryption_iv` + `encryption_tag` (AES-256-GCM)
- `apns_environment` `sandbox` \| `production`
- `bundle_id` default `com.fitfight.mvp`
- `locale` `en` \| `fr`
- `permission_status`
- `revoked_at` / `revoke_reason`

TestFlight = **production** tokens even when `FITFIGHT_API_URL` is staging. Store environment on the row. Sending a TestFlight token to sandbox → `BadDeviceToken`.

### `private.notification_intents` (outbox)

- Unique `idempotency_key` = `{fight_id}:{user_id}:{kind}:{slot}`
- `kind`: `fight_ended` \| `grace_reminder` \| `fight_finalized`
- `slot`: `t0` \| `t12` \| `t18` \| `t23` \| `final`
- `not_before`, `expires_at` (grace slots expire in ~2h so “6 hours left” does not send at T+20)
- `route` = `/fights/{id}`
- `copy_key`
- `status` pending / skipped / sent / failed / expired
- `skip_reason` already_complete / no_token / muted / superseded / fight_cancelled

### `private.notification_deliveries`

APNs status, reason, `apns-id`. Never store the raw token or a body that contains health numbers.

Preferences + per-fight mute tables may ship empty (no UI). Worker honors them if present.

**Indexes:** pending `(status, not_before)`; active tokens `(user_id) where revoked_at is null`; incomplete accepted members on awaiting fights.

---

## When to insert intents

Same transaction as `recalculateFight` when state **first** becomes `awaiting_final_sync`:

- Insert `t0`, `t12`, `t18`, `t23` for each accepted member (`ON CONFLICT DO NOTHING`).
- `not_before` is computed from **`ends_at`**, not `now()`.

When state becomes `final`:

- Insert `final` for each accepted member.
- Skip remaining grace intents (`superseded`).

HealthKit upload that sets `final_steps_complete` should skip that user’s leftover grace intents. Upload today does **not** call `recalculateFight`; the worker/closer still needs a tick for early finalize.

Do **not** enqueue on every closer tick of an already-awaiting fight.

---

## Worker

Daily Vercel Hobby cron cannot do this.

**Primary:** Supabase Cron every **15 minutes** → `POST /api/internal/close-fights` (or a renamed `/api/internal/run-scheduled-work`) with `Authorization: Bearer CRON_SECRET`.

Each tick:

1. `closeDueFights(now)` (existing, batch 25)
2. Drain due intents (`not_before <= now`, `expires_at > now`)
3. For grace slots, skip if `final_steps_complete`
4. Send APNs if secrets exist; otherwise mark `skipped` / leave `pending`

Keep `0 3 * * *` as backup until the 15-minute job is proven.

Do not use silent push as the timer. Do not set `*/15` in `web/vercel.json` on Hobby — it will not run.

---

## APNs send

- Host from the **installation row**: production `https://api.push.apple.com`, sandbox `https://api.sandbox.push.apple.com`
- HTTP/2 `POST /3/device/{token}`
- JWT ES256, `iss` = Team `C92DPD8ME2`, `kid` = key id, `iat` < 1h
- `apns-topic: com.fitfight.mvp`
- `apns-push-type: alert`
- `apns-priority: 10`
- Payload: `aps.alert` + `{ fitfight: { route } }`
- **410 / Unregistered / BadDeviceToken** → revoke that installation
- **429** → leave pending, next tick
- **403 InvalidProviderToken** → ops, do not wipe all tokens

Never log the raw token, `.p8`, or alert body with PII.

---

## iOS

1. Enable Push on the App ID (Marc). Xcode automatic signing adds `aps-environment`.
2. Do **not** add `UIBackgroundModes: remote-notification` for v1.
3. In-app card first, then system sheet. Not at launch. Not with Health. No provisional auth.
4. After allow: `registerForRemoteNotifications()` every launch.
5. `POST /api/v1/device-installations` with hex token, environment, locale.
6. Sign-out / delete account / 410 → revoke.
7. Denied: fights still work. In-fight banner during grace: open the app to lock your steps.
8. Tap + Universal Link `/fights/{id}` — add AASA path and `handleOpenURL` (today only `/j/*` and `/r/*`).
9. Cold start: store pending route like join/referral codes.

Ask permission once the person has a live fight, **before** `ends_at`, or the T+0 push never arrives. Do not show the system sheet until Slice F can send.

---

## Marc-only secrets

Three different Apple keys. Do not reuse them.

| Key | Where | Use |
|---|---|---|
| App Store Connect `.p8` | GitHub Actions | TestFlight upload (already) |
| Sign in with Apple | Vercel | Login / delete (already) |
| **FitFight APNs** (new) | Vercel Preview + Production only | This feature |

Vercel names: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_TOPIC=com.fitfight.mvp`, `APNS_TOKEN_ENCRYPTION_KEY` (32-byte, **not** the Sign in with Apple encryption key).

Never put the `.p8` in git, chat, or the iOS bundle.

---

## Failure modes

| Failure | What must still happen |
|---|---|
| No token / denied | Fight still finals at T+24. In-app P / settlement UI still true. |
| Push dropped | Same. Open app → closer + HealthKit upload. |
| Cron miss | Next 15-minute tick. Grace copy has `expires_at`. |
| Daily cron only | Worst case: transition/finalize lag ~24h. Why G exists. |
| User opens without a tap | Sync + closer run. Skip leftover grace intents. |
| Account deleted | Cascade installations + intents. No post-delete send. |

---

## Files to add (when building)

- `supabase/migrations/YYYYMMDDHHMMSS_notification_outbox.sql`
- `supabase/tests/push_notifications.sql`
- `web/lib/types/notifications/*`
- `web/lib/apns/apns-client.ts`, `apns-jwt.ts`
- `web/lib/notifications/notification-copy.ts`
- `web/lib/supabase/queries/device-installations-supabase-query.ts`
- `web/lib/supabase/queries/notification-intents-supabase-query.ts`
- `web/lib/supabase/queries/process-notification-outbox-supabase-query.ts`
- `web/app/api/v1/device-installations/route.ts`
- `FitFight/PushNotificationService.swift`

Hook enqueue inside `recalculate-fight-supabase-query.ts`. Extend `delete-account-supabase-query.ts`. Add `/fights/*` to `web/app/.well-known/apple-app-site-association/route.ts`.

---

## Privacy / review (before App Store, not before staging)

- Privacy page: we store a device token for optional fight-end reminders; lock screen has no step counts; disable in iOS Settings; deleted with the account.
- `PrivacyInfo.xcprivacy`: Device ID, linked, not tracking, App Functionality.
- Review notes currently say FitFight has no push — change that when F ships.
- App must work if the reviewer taps Don’t Allow.

---

## Not this slice

Friend poke / custom nudge (needs filter, report, block). Daily AI status. Rank-change alerts. Silent HealthKit wake as the only closer. Notification inbox. Mute UI (tables may exist unused).
