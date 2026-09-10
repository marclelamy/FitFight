# FitFight remote push (APNs) — research plan

Research date: **10 September 2026**  
Scope: requirements to add **alert** remote notifications to the existing TestFlight app `com.fitfight.mvp`. **No application code in this document.**

Notifications are authorized only for the **final-sync cadence**. Product + forfeit + UI: [`pending-final-sync-plan.md`](pending-final-sync-plan.md). This file is the Apple/APNs vertical slice. Do not build friend pokes, paid nudges, daily AI status, or rank-change spam.

Push is **not** required for App Store review. Do not add it only to look complete. [Guideline 4.5.4](https://developer.apple.com/app-store/review/guidelines/)

---

## Bottom line for FitFight

| Fact | FitFight today |
| --- | --- |
| Bundle ID | `com.fitfight.mvp` |
| Team ID | `C92DPD8ME2` (already in GitHub `APPLE_TEAM_ID`, AASA, docs) |
| TestFlight | Production APNs. Sandbox is only for Xcode-debug devices. |
| Entitlements | Sign in with Apple, HealthKit, HealthKit background delivery, Associated Domains. **No** `aps-environment`. **No** `UIBackgroundModes`. |
| Info.plist | Generated. No `remote-notification` background mode. Keep it that way for alert pushes. |
| Signing | Automatic (`CODE_SIGN_STYLE = Automatic`) + Fastlane `-allowProvisioningUpdates` on GitHub-hosted `macos-26`. |
| Repo | Public. Never commit a `.p8`. |
| Backend | Vercel Node (`staging.fitfight.app` / `fitfight.app`). Daily cron `GET /api/internal/close-fights` at 03:00 UTC. Grace is already `final_sync_grace_seconds = 86400`. |
| Existing `.p8` keys | **Two already, both the wrong service.** Do not reuse them for APNs. |
| Local timers | **Cannot** be the sole 24-hour grace nudge. iOS will not reliably schedule or fire that work if the app is killed. |

HealthKit background delivery (already shipping) is **not** APNs. It can wake FitFight to read Steps. It cannot replace a server push that says “open the app.”

---

## 1. APNs Authentication Key (`.p8`)

Use a **token-based** APNs key, not a per-app TLS certificate. One key, JWT on every send. Apple: the key does not expire; it can be revoked. [Communicate with APNs using authentication tokens](https://developer.apple.com/help/account/capabilities/communicate-with-apns-using-authentication-tokens/) · [Create a private key](https://developer.apple.com/help/account/keys/create-a-private-key/) · [Establishing a token-based connection](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns)

### Marc creates it (Account Holder or Admin)

1. [developer.apple.com](https://developer.apple.com/account) → Certificates, Identifiers & Profiles → **Keys** → **+**.
2. Name: `FitFight APNs` (do not name it like the existing `FitFight GitHub` ASC key).
3. Enable **Apple Push Notification service** only. Do **not** tick Sign in with Apple or App Store Connect API on this key.
4. **Configure** APNs:
   - Prefer **Topic Specific** + topic `com.fitfight.mvp` + **Production**.
   - Acceptable: **Team Scoped** + **Production**.
   - Skip Sandbox. FitFight has no home Mac / Xcode device loop. TestFlight and the App Store both use production APNs.
5. Continue → Confirm → **Download** the `.p8` **now**. Apple does not store it. If Download is disabled later, the key was already downloaded and cannot be fetched again.
6. Write down the 10-character **Key ID** on that page.
7. Team ID is already `C92DPD8ME2` (Membership / App ID `C92DPD8ME2.com.fitfight.mvp`).
8. Paste the `.p8` **only** into Vercel env vars (below). Never git, never chat, never Xcode, never GitHub Actions.

February 2025: new keys can be limited to Production or Sandbox, and to specific topics. Legacy keys that work in both environments still work; Apple recommends environment-specific keys. [Apple news, 17 Feb 2025](https://developer.apple.com/news/?id=wy4tb0uo)

### JWT the Vercel backend will sign (later)

| JWT field | Value |
| --- | --- |
| `alg` | `ES256` only |
| `kid` | 10-character Key ID |
| `iss` | Team ID `C92DPD8ME2` |
| `iat` | Unix seconds; must be &lt; 1 hour old |

Refresh the JWT no more than once per 20 minutes and no less than once per 60 minutes on a given connection. Stale `iat` → `403 ExpiredProviderToken`. [Token connection](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns)

### Three keys. Do not mix them.

| Key | Apple service | Lives where | Used for |
| --- | --- | --- | --- |
| `FitFight GitHub` | App Store Connect API | GitHub `APP_STORE_CONNECT_*` | Fastlane archive / TestFlight / App Store upload |
| Sign in with Apple | SIWA | Vercel `APPLE_SIGN_IN_*` | Token exchange and account-deletion revoke |
| **`FitFight APNs` (new)** | APNs | **Vercel only** `APNS_*` | Sending pushes |

The ASC `.p8` cannot send pushes. The SIWA `.p8` cannot send pushes. The APNs `.p8` cannot upload builds or revoke Sign in with Apple. Xcode and `macos-26` CI never need the APNs key: they only need the **Push Notifications capability** so the signed IPA contains `aps-environment`.

---

## 2. Sandbox vs production — TestFlight is production

**Confirmed from current Apple docs.**

The `aps-environment` entitlement is `development` (sandbox) or `production`. Xcode sets it from the provisioning profile. Apple’s current entitlement page says a **production profile** and **Prerelease Versions and Beta Testers** use `production`. [aps-environment](https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment)

APNs hosts ([Sending notification requests to APNs](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)):

| Environment | Host | Who gets those tokens |
| --- | --- | --- |
| Sandbox / development | `api.sandbox.push.apple.com:443` | Xcode-run Debug on a registered device |
| Production | `api.push.apple.com:443` | TestFlight **and** App Store |

Apple: “Use the production server for your shipping apps and the development server for testing.” TestFlight is a shipping/prerelease binary signed with an App Store distribution profile. A TestFlight token sent to sandbox returns `400 BadDeviceToken` (“token matches the environment”).

**FitFight footgun:** the TestFlight binary talks to the **staging** Supabase/Vercel backend (`staging.fitfight.app`), but its APNs tokens are **production**. Tag the stored token with:

- `apns_environment`: `production` \| `sandbox` (from the entitlement / host you must use)
- `fitfight_channel`: `staging` \| `prod` (from `BuildEnv` / API origin)

Do not treat “staging TestFlight” as sandbox APNs.

Same bundle ID means one install per phone. Staging vs production are two FitFight accounts, but only one binary is installed. Register the token to whichever API that binary uses. When someone replaces TestFlight with an App Store build, the staging row goes stale until `410`.

---

## 3. App capability and entitlements

### Required for alert pushes

1. Developer account → Identifiers → App ID `com.fitfight.mvp` → enable **Push Notifications**. [Enable app capabilities](https://developer.apple.com/help/account/identifiers/enable-app-capabilities/)
2. Xcode target → Signing & Capabilities → **+ Push Notifications**. That adds `aps-environment` to [FitFight.entitlements](../../FitFight/FitFight.entitlements). [Registering your app with APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns)
3. Do **not** hand-write `aps-environment=development` in the entitlements file. Automatic signing on `macos-26` + App Store export must stamp **`production`**. A `development` value fails TestFlight asset validation (90046).
4. After the App ID changes, old provisioning profiles are invalid. FitFight already regenerates them: Fastlane automatic signing with `APP_STORE_CONNECT_*` and `-allowProvisioningUpdates`. Marc does not open Xcode.

### Do **not** add for the first slice

`UIBackgroundModes` → `remote-notification` is **only** for silent/`content-available` background pushes. [Pushing background updates](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app)

Prefer **alert** pushes (`apns-push-type: alert`, priority `10`). Silent pushes are low priority, throttled (Apple: don’t send more than two or three per hour), discarded if the app was force-quit, and **not guaranteed**. FitFight already has HealthKit observer wake-ups for Steps. A silent APNs “please sync” is a bad second timer.

Keep HealthKit background delivery as it is. Do not confuse it with APNs.

---

## 4. Permission UX

Apple: request authorization **in context**, not automatically on first launch. Subsequent calls do not re-prompt. [Asking permission to use notifications](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)

FitFight already does this for Health (username → Connect Apple Health). Do the same for push.

**First-slice context (when building):** after the person joins or starts their first fight, or on the fight screen once it is `live` / near `ends_at`. One sentence: FitFight can tap you when a fight ends so you can open the app and finish the Steps upload. Not on Welcome, not beside Sign in with Apple.

**Provisional / quiet notifications:** Apple will grant them without a prompt; they **do not appear on the Lock Screen**, do not sound, and only show in Notification Center with Keep / Turn Off. [Asking permission](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)

**Skip provisional for the grace nudge.** The point is a Lock Screen alert: “Open FitFight to sync your steps.” Quiet trial delivery hides that. Use explicit `.alert, .sound, .badge`. If denied, the app still works (Fights, Feed, pull-to-refresh). Guideline 4.5.4 and 5.1.2(i): push must not be required to use the app.

Settings later: You → Settings mute per fight / per category, plus the system Settings link. Don’t invent that screen until the backlog item moves.

English and French: either send localized `title`/`body` from the server (preferred; the app already follows per-app language) or use `title-loc-key` / `loc-key` in the payload. [Generating a remote notification](https://developer.apple.com/documentation/usernotifications/generating-a-remote-notification)

---

## 5. Payload — Lock Screen must stay boring

Apple payload: `aps.alert.title` / `body`, `thread-id`, `category`, plus custom keys **beside** `aps` (not inside it). Max 4 KB. [Generating a remote notification](https://developer.apple.com/documentation/usernotifications/generating-a-remote-notification)

Apple also: “Don’t include customer information or any sensitive data … in a notification’s payload.” Encrypt if you must. Guideline **4.5.4**: push “should not be used to send sensitive personal or confidential information.” Health/fitness data is called out again in **5.1.3**. [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

FitFight Lock Screen **must not** contain:

- Step counts, gaps, ranks, charts, calories, workouts
- Money, pots, “you owe”
- Loser action text (UGC; can be humiliating)
- Opponent display names if they imply a health result (“Alex is 2,400 ahead”)
- Invite tokens, APNs tokens, user IDs in visible text

Safe first-slice copy (already in the backlog): **“Open FitFight to sync your steps.”** Title can be the fight **title** only if that title is not itself a health claim. Prefer a fixed string: “Your fight ended”.

Recommended payload shape (when coding later):

```json
{
  "aps": {
    "alert": {
      "title": "Your fight ended",
      "body": "Open FitFight to sync your steps."
    },
    "thread-id": "<fight-uuid>",
    "category": "FF_FINAL_SYNC",
    "sound": "default"
  },
  "fight_id": "<fight-uuid>"
}
```

Headers: `apns-topic: com.fitfight.mvp`, `apns-push-type: alert`, `apns-priority: 10`, `apns-collapse-id` = `final-sync:<fight-uuid>` so a second reminder replaces the first.

**Deep link:** notification tap is **not** a Universal Link. Handle `fight_id` in `UNUserNotificationCenter` and set `model.openFightID` the same way Fights/Feed already do. AASA today only allows `/j/*` and `/r/*` ([apple-app-site-association](../../web/app/.well-known/apple-app-site-association/route.ts)). Do not put `/fights/<uuid>` in the payload as a public URL until AASA and the site route exist. Do not put health query params on any URL.

Review Notes today say “FitFight has no push notifications.” Update that file when this ships. [`docs/app-store/review-notes.md`](../app-store/review-notes.md)

---

## 6. Token registration

Apple: call `UIApplication.shared.registerForRemoteNotifications()` (after permission, or anytime; it does not prompt). On success, `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` gives `Data`. Forward it to the provider. Register **every launch**. Never treat a locally cached token as authoritative — restore, new device, reinstall OS, and some updates issue a new token. [Registering your app with APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns)

FitFight already has `FitFightAppDelegate`. That is where the two callbacks go. The SwiftUI `.onOpenURL` path is for Universal Links, not APNs.

Hex: encode the raw `Data` as lowercase hex (Apple’s `:path` is `/3/device/<hex bytes>`). Do not Base64 it to APNs.

POST to a new authenticated API (when building), e.g. `POST /api/v1/device-installations`, body: hex token, `apns_environment`, app version/build. Bind to the signed-in User. System design name: `private.device_installations`. Encrypt or at least keep the table out of client RLS. On sign-out / delete account, delete or detach that User’s rows (deletion already wipes the account).

Simulator: not the FitFight test path. Prove it on TestFlight.

---

## 7. HTTP/2 APNs API, JWT, `410 Unregistered`

[Sending notification requests](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns) · [Handling responses](https://developer.apple.com/documentation/usernotifications/handling-notification-responses-from-apns)

```
POST https://api.push.apple.com/3/device/<hex-token>
authorization: bearer <jwt>
apns-topic: com.fitfight.mvp
apns-push-type: alert
apns-priority: 10
apns-collapse-id: final-sync:<fight-uuid>
```

TLS 1.2+. HTTP/2 required (legacy binary protocol dead since 31 Mar 2021). Port `2197` is an optional alternate.

Vercel serverless cannot keep Apple’s preferred all-day HTTP/2 connection. Apple also says a once-a-day sender may open a new connection each day. FitFight’s first slice is the existing daily close-fights cron plus a grace reminder — volume is tiny. Use Node’s HTTP/2 client per invocation. Do not use HTTP/1.1 `fetch` to APNs.

| Status / reason | FitFight action |
| --- | --- |
| `200` | Record accepted `apns-id`. Not proof the person saw it. |
| `410` `Unregistered` or `ExpiredToken` | Stop sending. Revoke that token row. `timestamp` is when APNs confirmed invalidity. Not proof of uninstall. |
| `400` `BadDeviceToken` | Almost always sandbox/production mismatch. Fix host vs `apns_environment`. Do not retry that token as-is. |
| `403` `ExpiredProviderToken` / `InvalidProviderToken` | Refresh or fix JWT / `.p8`. |
| `429` `TooManyRequests` | Back off that token. |
| `5xx` | Retry after ≥15 minutes with backoff. |

Do not retry `Unregistered`, `ExpiredToken`, `BadDeviceToken`, `DeviceTokenNotForTopic`, `Forbidden`, `PayloadTooLarge`.

Never log hex tokens, JWTs, or `.p8` material. System design already forbids APNs tokens in logs.

---

## 8. Where secrets live (public GitHub + `macos-26` + Vercel)

| Item | Git | GitHub Actions | Vercel Preview (`staging.fitfight.app`) | Vercel Production | Signed IPA / Xcode |
| --- | --- | --- | --- | --- | --- |
| APNs `.p8` | **Never** | **Never** (CI does not send pushes) | `APNS_PRIVATE_KEY` | `APNS_PRIVATE_KEY` | **Never** |
| APNs Key ID | No | No | `APNS_KEY_ID` | `APNS_KEY_ID` | No |
| Team ID | Already documented | Already `APPLE_TEAM_ID` | Reuse `APPLE_SIGN_IN_TEAM_ID` or `APNS_TEAM_ID=C92DPD8ME2` | Same | Signing only |
| Push capability / `aps-environment` | Entitlements file **without** a hardcoded environment if automatic signing fills it; or let Xcode capability add the key | Fastlane already signs with ASC key | n/a | n/a | `production` on TestFlight and App Store archives |
| Device tokens | Never | Never | `private.device_installations` on develop Supabase | Same table on production Supabase | Memory / register every launch |
| `CRON_SECRET` | Never | Never | Already required for close-fights | Already required | n/a |

Same APNs key can serve Preview and Production **if** it is Production-scoped: both TestFlight and App Store tokens hit `api.push.apple.com`. Topic-specific to `com.fitfight.mvp` is enough isolation.

Do **not** add `APNS_*` to GitHub so a workflow can “just test a push.” That copies the private key into a public-repo Actions environment for no reason.

CI **should** (when the capability ships) extend Fastlane’s existing `codesign -d --entitlements` check (today it asserts HealthKit background delivery) to require `aps-environment` = `production` on TestFlight and App Store IPAs.

---

## 9. Local `UNNotificationRequest` is not the first slice

Apple can deliver an **already scheduled** local notification at a calendar/time trigger even if the app is not in the foreground. [Scheduling a notification locally](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)

That is **not** a server timer.

| Need | Local `UNNotificationRequest` | Server APNs alert |
| --- | --- | --- |
| Schedule while the phone is killed | **No.** Nothing new can be added. | Yes (Vercel cron already runs). |
| Know the server `ends_at` / grace / who still lacks a final snapshot | No, unless the app was open to reschedule | Yes (`closeDueFights`, `final_sync_grace_seconds`) |
| Reminder at `ends_at + 24h` if they never opened after join | **Unreliable.** Never scheduled, or stale. | Yes |
| Force-quit / Low Power / iOS throttling | Local fire of an old request may still happen; **new** work will not | Alert still shows if APNs delivers |
| Silent / `BGAppRefresh` / HealthKit observer as the only closer | Apple does not guarantee any of these | Fight already finalizes on open **or** the 03:00 UTC cron |

[`backlog.md`](../backlog.md): “If the app is closed or killed, iOS will not reliably run timers, settle a month, or notice that HealthKit never uploaded.” The parked nudge text: “the phone cannot schedule them while killed.”

Apple background remote notifications are also **not guaranteed** and are discarded after a force-quit. [Background updates](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app)

**Do not ship a local notification as the sole grace timer.** Optional local “fight ends tonight” is a nice extra only after a server alert exists. Finalization stays on the server.

---

## First slice (when Marc authorizes)

Hook the existing close path, do not invent a second clock:

1. `closeDueFights` moves a fight to `awaiting_final_sync` at `ends_at`.
2. Same transaction: outbox rows for accepted members with a registered production token and alerts allowed.
3. Worker (same Node process as today’s cron, or a follow-up cron) sends one alert APNs.
4. One reminder before grace expiry if that member still has no exact end snapshot.
5. Finalize as today. A dropped push must not block close. Opening the app remains the sync.

No friend pokes, rank-change spam, or paid nudges in this slice.

---

## Marc checklist (Apple / GitHub / Vercel clicks only)

Agents cannot do these. Do not paste the `.p8` into chat.

1. Apple Developer (Account Holder or Admin) → Identifiers → `com.fitfight.mvp` → enable **Push Notifications** → Save.
2. Keys → **+** → name `FitFight APNs` → APNs only → Topic Specific + `com.fitfight.mvp` + **Production** (or Team Scoped + Production) → Confirm → **Download `.p8` once** → copy Key ID.
3. Store the `.p8` in a password manager. Apple will not give it again.
4. Vercel → Project → Settings → Environment Variables, **Preview and Production**:
   - `APNS_PRIVATE_KEY` = full `.p8` text (keep `-----BEGIN PRIVATE KEY-----` lines; `\n` escaping is fine, same pattern as `APPLE_SIGN_IN_PRIVATE_KEY`)
   - `APNS_KEY_ID` = the 10-character id
   - `APNS_TEAM_ID` = `C92DPD8ME2` if you do not want to reuse `APPLE_SIGN_IN_TEAM_ID`
5. Do **not** add those three to GitHub Actions secrets.
6. Do **not** create an APNs TLS certificate unless someone later insists. Token key is enough.
7. After the first push-capable TestFlight: TestFlight → **Update**. Look for `1.0.0 · build N · staging`. Grant alerts when the in-context prompt appears. Confirm a staging fight-end nudge on two phones.
8. When that build is real: App Store Connect Review Notes no longer say there are no push notifications. Privacy page / App Privacy answers: device token is used to send optional fight alerts; not sold; deleted with the account.
9. Leave GitHub `APP_STORE_CONNECT_*` and Vercel `APPLE_SIGN_IN_*` alone.

---

## Agent checklist (code / CI — only after Marc moves the backlog item)

Do not implement from this research alone.

**iOS**

1. Add Push Notifications capability; keep `FitFight.entitlements` in the pbxproj (already listed). Do not add `UIBackgroundModes` `remote-notification`.
2. In-context `UNUserNotificationCenter.requestAuthorization` (not first launch). Then `registerForRemoteNotifications`.
3. `didRegister` / `didFailToRegister` on `FitFightAppDelegate`. Hex-encode the token. POST to the API with `apns_environment` + version/build. Register every launch / sign-in.
4. Notification tap → `openFightID` from `fight_id`. No health numbers in copy. Register category `FF_FINAL_SYNC` if actions are needed.
5. `ReleaseNote` in `Changelog.swift` at `1.0.0`. Do not bump `MARKETING_VERSION`.
6. Update [`docs/app-store/review-notes.md`](../app-store/review-notes.md) and privacy copy so they no longer claim “no push.”

**Backend / DB**

7. Migration: `private.device_installations` (user, hex token unique, `apns_environment`, channel, timestamps). No app-facing RPC. Delete on account deletion / sign-out.
8. `POST /api/v1/device-installations` through `apiRoute` + Zod in `web/lib/types/…`. Query file under `web/lib/supabase/queries/`.
9. Outbox written in the same transaction as close / grace. Worker uses HTTP/2 to `api.push.apple.com` (TestFlight + App Store) or `api.sandbox.push.apple.com` only for true sandbox tokens.
10. JWT ES256 from Vercel `APNS_*`. Handle `410` by revoking the row. No token in logs.
11. Hook `closeDueFights` / the 03:00 UTC cron. Do not use local notifications as the only timer.

**CI**

12. Fastlane `verify_healthkit_background_delivery`: also require `aps-environment` contains `production` on TestFlight and App Store IPAs.
13. Simulator workflow stays `CODE_SIGNING_ALLOWED=NO`; it cannot prove APNs.
14. No APNs `.p8` in GitHub secrets. No third-party push vendor (FCM, OneSignal) — health data + public repo.

**Verify**

15. Two TestFlight phones, staging backend, production APNs host. Deny-permission path still uses the app. Delete account removes the token. Wrong-host send must not happen.

---

## Official Apple URLs

- [Create a private key](https://developer.apple.com/help/account/keys/create-a-private-key/)
- [Communicate with APNs using authentication tokens](https://developer.apple.com/help/account/capabilities/communicate-with-apns-using-authentication-tokens/)
- [Enable app capabilities / Push Notifications](https://developer.apple.com/help/account/identifiers/enable-app-capabilities/)
- [aps-environment entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment)
- [Registering your app with APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns)
- [Asking permission to use notifications](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)
- [Generating a remote notification](https://developer.apple.com/documentation/usernotifications/generating-a-remote-notification)
- [Sending notification requests to APNs](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)
- [Handling notification responses from APNs](https://developer.apple.com/documentation/usernotifications/handling-notification-responses-from-apns)
- [Setting up a remote notification server](https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server)
- [Pushing background updates](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app)
- [Scheduling a notification locally](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)
- [Establishing a token-based connection to APNs](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns)
- [APNs token key environments (17 Feb 2025)](https://developer.apple.com/news/?id=wy4tb0uo)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) (4.5.4, 5.1.2, 5.1.3)
- [Archive: Communicating with APNs](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/CommunicatingwithAPNs.html)
