# FitFight App Store first-review readiness

Research date: **30 August 2026**

Repository baseline: **`e02526b`**, identical to `origin/develop` when audited

Source standard: current Apple first-party material, current repository and CI evidence, live production endpoint checks, and the FTC/Washington primary sources identified below.

This is a launch-readiness audit, not a promise of approval or legal advice. Apple's App Review Guidelines page was last updated **8 June 2026** at the time of research; it is a living document, so refresh the policy links immediately before submission.

## Executive verdict

**Do not submit the current build.** It can be signed and processed by App Store Connect—`0.9.0 (90)` processed as `VALID`—but it is not ready for App Review.

The first-review strategy should be a narrow, honest **1.0**:

- Sign in with Apple, username, friends/invitations, Apple Health **Step Count**, Steps-only fights, standings/history, and complete account deletion.
- **Bragging rights only.** No money, pot, payout, custom forfeit, prize, or wager language.
- No fake Requests board, internal Design system, unsupported metrics, dead buttons, beta copy, or staging data.
- A deliberately minimized and clearly disclosed Health upload, with explicit consent before off-device collection and participant sharing.
- A production archive path, production backend, public privacy/support pages, a compliant reviewer-access path, and a completed real-device test matrix.

The current highest-probability rejection reasons are:

1. **App completeness:** production contains fake fixture content, unsupported choices, and visible controls that do nothing. Apple says more than 40% of unresolved review issues relate to Guideline 2.1 completeness. [Apple: Avoiding common issues](https://developer.apple.com/app-store/review/)
2. **Broken required surfaces:** `https://fitfight.app/privacy` and `/support` return 404, and the in-app Privacy row is a no-op.
3. **Production functionality:** there is no production App Store lane, and the checked-in Release configuration has no API base URL, disabling Health upload and account deletion.
4. **Health privacy:** FitFight prompts without a contextual disclosure and uploads all accessible raw Step samples plus extensive device/source metadata—far more than a simple fight score needs.
5. **Deletion:** the current implementation removes the most sensitive tables but retains stable identifiers/relationships, does not revoke Sign in with Apple, and does not purge local Health state.
6. **Money and UGC:** the app defaults to a `$10` stake, shows pots/payouts, accepts arbitrary obligations, exposes searchable user profiles, and has no report/block/filter/moderation system.
7. **Review access and proof:** the core two-person flow is not immediately reviewable, and the repository's required two-phone, three-day production-like test is not complete.

### Direct answer on notifications

**Push notifications are not required for App Store approval. Do not build them solely for review.** Apple says push must not be required for the app to function, sensitive personal or confidential information should not be sent in push, and promotional push requires explicit opt-in and an in-app opt-out. FitFight should adopt the stricter product rule that no Health detail appears on a lock screen. [Guidelines 4.5.4 and 5.1.2(i)](https://developer.apple.com/app-store/review/guidelines/)

FitFight's HealthKit Background Delivery entitlement is separate from APNs and is already present. For 1.0, remove the dead Notifications row, make no notification claims in metadata, and explain in Review Notes that opening the app or Health background delivery updates scores.

## What is already in good shape

These foundations reduce risk and should be preserved:

- The latest cloud archive signed, uploaded, processed as `VALID`, and verified the HealthKit Background Delivery entitlement. Simulator, database, screenshot, and TestFlight CI were green at the audited commit.
- Health access is limited to **read-only Step Count**: `toShare: []`, read `.stepCount` in [HealthKitStepsStore.swift](../../FitFight/HealthKitStepsStore.swift#L64-L80).
- HealthKit and background-delivery entitlements are present in [FitFight.entitlements](../../FitFight/FitFight.entitlements#L5-L12).
- Temporary Health archives use file protection and are excluded from backup in [HealthKitStepArchive.swift](../../FitFight/HealthKitStepArchive.swift#L35-L42) and [HealthKitUploadState.swift](../../FitFight/HealthKitUploadState.swift#L45-L48).
- Sign in with Apple uses Apple's native control and requests only name/email in [AppleSignInControl.swift](../../FitFight/AppleSignInControl.swift#L8-L18).
- Delete Account is easy to find and already deletes raw Health rows, score snapshots, observations, uploads, and daily scores in [delete-account-supabase-query.ts](../../web/lib/supabase/queries/delete-account-supabase-query.ts#L14-L34).
- No native ad, tracking, analytics, or ATT code was found. Keep it that way for the first release.
- The 1024×1024 icon is RGB with no alpha. iPhone-only, English-only, portrait-only, and iOS 17 minimum are all acceptable choices.
- Standard HTTPS plus hashing appears consistent with the present `ITSAppUsesNonExemptEncryption = NO`, subject to a final dependency/export audit.

## Common Apple rejection causes mapped to FitFight

| Apple review concern | Current FitFight evidence | Status before submission |
| --- | --- | --- |
| **2.1 App Completeness**: crashes, placeholders, incomplete content, inaccessible features | Fake public Requests data, local-only votes, empty plus button, dead Settings/actions, unsupported metrics | **STOP** — remove or fully implement every visible surface |
| **Broken links / support** | Production root, privacy, terms, and support returned 404 on 30 August 2026 | **STOP** — privacy and support must be live; terms is strongly recommended for this product |
| **Incomplete review information/access** | A fresh Sign in with Apple account has no second participant or history | **STOP** — provide durable reviewer access or obtain prior approval for a built-in demo mode, with precise Review Notes |
| **Misleading metadata or functionality** | Public-looking fixture board; “Private beta”; “FitFight MVP”; money UI with no payment/legal model | **STOP** — the binary, screenshots, name, description, and web pages must tell the same true story |
| **Privacy / unclear permission requests** | Health prompt follows username save without explaining upload, retention, processors, or opponent visibility | **STOP** — add explicit contextual disclosure and consent |
| **Account deletion** | Good partial server erasure, but stable handle/UUID/relationships and local data remain; no Apple revocation | **STOP** — complete and test end-to-end deletion |
| **UGC / social abuse controls** | User handles and custom obligations are shared; no filter, report, block, or operating response process | **STOP if retained** — remove arbitrary content and add the full safety stack for remaining social content |
| **Contests / gambling / safety** | `$10` is the default; “settle up,” pots, projected payouts, arbitrary forfeits | **STOP if retained** — launch with no money/prizes and answer the contest rating honestly |
| **Privacy manifests / required-reason APIs** | No app `PrivacyInfo.xcprivacy`; direct `UserDefaults` use | **STOP** — add a valid manifest with `CA92.1`; verify the exact archive with Xcode's privacy report |
| **Correct submitting entity** | Developer enrollment type is not visible in the repo; Health data is sensitive | **VERIFY** — confirm the legal entity/account posture before review |
| **Current SDK/toolchain** | CI uses `macos-26`; the uploaded build processed successfully | **READY**, but validate the exact final archive |
| **Minimum functionality** | Native Health integration, persistent fights, invitations, and standings are meaningful when working | **LIKELY READY** after fake/dead surfaces are removed and the production path is proven |

Apple's own current guidance emphasizes testing on device, complete and accurate metadata, live backends, valid reviewer access, and explanations for non-obvious features. [App Review Guidelines: Before You Submit and 2.1](https://developer.apple.com/app-store/review/guidelines/)

## P0 stop-ship work

### 1. Cut the public product to what actually works

The safest first public scope is:

- Keep: Welcome, Sign in with Apple, username, invitations/friends, Steps-only fights, Apple Health connection, standings/history, Night/Day, Versions, sign out, and delete account.
- Remove from 1.0 UI: Requests/public board, Design system, Active Minutes, Workout Count, money/custom stakes, payout/pot panels, custom forfeit text, Payouts, Notifications, Units & goals until real, and all empty icon/buttons/rows.

Confirmed current issues:

- Production always loads the request fixtures in [AppModel.swift](../../FitFight/AppModel.swift#L225-L237). They impersonate users, votes, comments, bugs, Strava behavior, and shipped features in [AppModel.swift](../../FitFight/AppModel.swift#L1355-L1433).
- The Requests plus button does nothing, votes are memory-only, and the screen claims posts are public even though posting does not exist in [RequestsView.swift](../../FitFight/RequestsView.swift#L16-L49).
- Units & goals, Notifications, Privacy, and Payouts are empty actions; the internal Design system is user-accessible in [YouView.swift](../../FitFight/YouView.swift#L346-L367).
- “I challenge you” and the fight More menu do nothing in [FightDetailView.swift](../../FitFight/FightDetailView.swift#L55-L75).
- Active Minutes and Workout Count are selectable even though the CTA only starts Steps in [NewFightView.swift](../../FitFight/NewFightView.swift#L49-L84).
- New Fight defaults to `$10`, says users “settle up,” offers arbitrary money/actions, and explains how the pot settles in [NewFightView.swift](../../FitFight/NewFightView.swift#L14-L45) and [NewFightView.swift](../../FitFight/NewFightView.swift#L195-L255). Fight detail prominently presents money in [FightDetailView.swift](../../FitFight/FightDetailView.swift#L31-L36).

Acceptance gate: on the exact production build, every visible control works, every value is real or clearly labeled demo data, and no copy promises an unavailable feature.

### 2. Publish and wire the privacy, support, and legal surfaces

Live checks on 30 August 2026 returned:

- `https://fitfight.app/` → **404**
- `https://fitfight.app/privacy` → **404**
- `https://fitfight.app/terms` → **404**
- `https://fitfight.app/support` → **404**
- `https://fitfight.app/api/health` → **200**

Apple requires a public privacy policy in App Store Connect **and inside the app**. It requires a Support URL with real contact information. The policy must explain collection, uses, recipients/processors, retention/deletion, consent withdrawal, and how to request deletion. [Guideline 5.1.1(i)](https://developer.apple.com/app-store/review/guidelines/) and [App Store Connect platform information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)

Before submission:

1. Deploy working `/privacy` and `/support` pages without login. A working homepage and `/terms` are strong product/legal recommendations; remove “Private beta” from [page.tsx](../../web/app/page.tsx#L4-L11) for public launch.
2. Make Privacy easily accessible in the app and at or before the Health consent flow. Link Terms and Support from Settings and preferably from the pre-account/sign-in surface.
3. Publish a real contact email and response process. “Talk to the boss” currently behaves like a mail composer and can show a local acknowledgement even when delivery did not occur; do not present it as reliable server chat.
4. Identify the actual service operator and subprocessors, including Supabase, Vercel where applicable, and the support-email provider.
5. State exactly what accepted fight participants see and what remains private.
6. Use concrete retention periods and honest deletion timing. Avoid absolute security promises.

Apple does not universally require a separate Terms URL, but FitFight needs clear account, acceptable-use, safety, no-prize/no-wager, and fight-rule terms. Keep the Apple-required privacy/support fields distinct from that recommendation.

### 3. Add a real Health consent and privacy flow

FitFight currently requests Health access as a side effect of saving a username in [OnboardingView.swift](../../FitFight/OnboardingView.swift#L57-L64), then can sync on signed-in app launch in [FitFightApp.swift](../../FitFight/FitFightApp.swift#L52-L56). There is no preceding explanation of server upload or what opponents see.

The first-review-safe flow is:

1. Ask only when the user deliberately taps **Connect Apple Health** or starts their first Steps fight.
2. Before Apple's system sheet, say in plain language:
   - FitFight asks only for Apple Health **Step Count**;
   - the date range it reads;
   - the data uploaded to FitFight;
   - why it is uploaded and how long it is retained;
   - only accepted participants see the stated fight total/rank, not raw samples;
   - no sale, advertising, marketing, research, data brokerage, or cross-app tracking;
   - how to withdraw and delete FitFight's copy;
   - where to read the full policy.
3. Offer **Connect and upload Steps** and **Not now**. Record the consent version/time as operational evidence.
4. At fight acceptance, identify the participants and the exact aggregate that becomes visible.
5. Add **Disconnect and delete FitFight's Apple Health copy**. Explain separately that the system permission is managed in Apple Health/Settings; do not imitate Apple's permission UI.

Apple permits HealthKit only for an evident health/fitness purpose, requires disclosure of the specific Health data collected, and restricts advertising, marketing, data mining, sale, and undisclosed third-party sharing. [Guidelines 5.1.1–5.1.3](https://developer.apple.com/app-store/review/guidelines/), [HealthKit privacy](https://developer.apple.com/documentation/healthkit/protecting-user-privacy), and [HealthKit HIG](https://developer.apple.com/design/human-interface-guidelines/healthkit)

One interpretation remains unresolved: Apple says HealthKit-derived information may be shared only with express permission and with a third party providing a health/fitness service to the user. A user-directed, minimal fight total is integral to FitFight's social fitness service, but an opponent is not obviously a service provider under that wording. Before making participant-visible totals the public 1.0 core, obtain written Apple guidance or adjust the design to the minimum user-directed derived score Apple confirms is permitted. Treat this as an external policy question, not as a finding that social Steps sharing is categorically prohibited.

### 4. Minimize the Health upload

The current archive reads anchored changes with no date predicate and, on initial sync or deletion, rebuilds statistics from the earliest accessible sample in [HealthKitStepArchive.swift](../../FitFight/HealthKitStepArchive.swift#L53-L101). For every raw sample it sends:

- sample UUID/value/start/end/day/time zone;
- source name, bundle ID, version, product type, and OS;
- device name/manufacturer/model/hardware/firmware/software;
- device local identifier and UDI;
- every arbitrary HealthKit metadata key/value;
- user-entered status.

See [HealthKitStepArchive.swift](../../FitFight/HealthKitStepArchive.swift#L302-L335). The permanent Versions screen also tells users that every field is sent through the backend for “diagnostics and future features,” which is not a valid blanket purpose for today's Steps game.

Recommended launch boundary:

- Upload fight-window daily/aggregate Steps plus only the minimum fields needed for current correction/fraud rules.
- If raw reconciliation is genuinely required, constrain it to active fight windows plus a defined grace period and retain only justified fields such as UUID, value, time window, source bundle, and user-entered flag.
- Remove device local/UDI identifiers, arbitrary metadata, firmware/hardware details, and pre-FitFight lifetime history unless a documented current requirement survives privacy/legal review.
- Delete temporary local and object-storage archives immediately after verified processing; expire abandoned uploads on a documented schedule.
- Retain completed-fight derived results only as long as users are told; do not keep raw provenance indefinitely by default.

Declaring excessive collection in an App Privacy label does not cure Apple's minimization and purpose-limitation concerns.

### 5. Correct Health purpose strings and the privacy manifest

The app is read-only, but both build configurations declare:

- `NSHealthShareUsageDescription`: “FitFight securely stores your Apple Health step history and sources to calculate Steps fights.”
- `NSHealthUpdateUsageDescription`: “FitFight does not write to Apple Health. iOS requires this sentence because HealthKit is on.”

See both build configurations in [project.pbxproj](../../FitFight.xcodeproj/project.pbxproj#L448-L451) and [project.pbxproj](../../FitFight.xcodeproj/project.pbxproj#L484-L487), plus the read-only request in [HealthKitStepsStore.swift](../../FitFight/HealthKitStepsStore.swift#L73-L76).

Before submission:

- Keep `NSHealthUpdateUsageDescription` with truthful no-write copy. Although Apple documents it as the write-purpose key and FitFight passes an empty `toShare` set, App Store Connect rejected the signed read-only archive with error 90683 when the key was absent.
- Rewrite the read string after minimization. A suitable direction is: “FitFight reads and uploads your Apple Health step count to score Steps fights. Accepted participants see only your fight totals and rank.”
- Avoid “securely” unless the implementation and policy substantiate the claim.
- Use **Apple Health**, not the developer term HealthKit, in user-facing Versions entries and marketing copy.
- Add an app-owned `PrivacyInfo.xcprivacy` to the target's Resources. Direct first-party `UserDefaults` use requires `NSPrivacyAccessedAPICategoryUserDefaults` with the fitting app-only reason **`CA92.1`**.
- Declare actual app collection and `NSPrivacyTracking = false` only if the final behavior remains nontracking.
- Generate and inspect the Xcode privacy report from the exact release archive; audit Supabase, TUSKit, swift-crypto, and every transitive package. The app's manifest cannot stand in for an SDK's own required declarations.

Apple has required approved reasons for required-reason APIs since 1 May 2024. [Required-reason API guidance](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api), [approved UserDefaults reason](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons), and [privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)

The valid manifest and approved reason are submission requirements. Generating and reconciling Xcode's aggregate privacy report is a FitFight verification gate, not a separate App Store Connect form field.

### 6. Finish account deletion

The backend already deletes the most sensitive Health and score data. It remains incomplete:

- The profile is renamed, but the unique handle is retained in [delete-account-supabase-query.ts](../../web/lib/supabase/queries/delete-account-supabase-query.ts#L46-L53).
- A stable profile/auth UUID is retained whenever fight or friendship history exists; friendships remain, and `data_sources` stays linked to the user ID in [delete-account-supabase-query.ts](../../web/lib/supabase/queries/delete-account-supabase-query.ts#L35-L83).
- The app forwards only the Apple identity token at sign-in; no Apple authorization-code/refresh-token revocation path was found in [AppleSignInControl.swift](../../FitFight/AppleSignInControl.swift#L36-L45).
- `SessionStore.deleteAccount()` clears the session and handle preference but not local Health archives/anchors, pending background uploads, Health consent state, or local support messages in [SessionStore.swift](../../FitFight/SessionStore.swift#L196-L211).

Before submission:

1. Revoke Sign in with Apple server-side as part of account deletion. Apple explicitly calls this out for apps using Sign in with Apple.
2. Delete/randomize handles, friendships, nonessential linked rows, and re-linking identifiers. Preserve shared fight results only if truly anonymized or legally required and disclosed.
3. Cancel uploads/background work and purge local Health archives, anchors, consent state, and support data.
4. Tell the user what is deleted, what genuinely anonymous data remains, why, and the completion time.
5. Test deletion during an interrupted upload, then sign in again with the same Apple identity and verify a clean new account.

Apple requires deletion initiation inside the app and deletion of the complete account and associated personal data; ordinary apps cannot substitute deactivation or a support-email process. [Apple account-deletion guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app/) and [Guideline 5.1.1(v)](https://developer.apple.com/app-store/review/guidelines/)

### 7. Remove arbitrary content or complete the social-safety stack

Removing the fake Requests board and custom loser obligations substantially reduces risk, but handles, display names, search, friendships, and opponent interaction remain social/user-created content.

Current issues:

- Handles fall back to substring search, exposing discoverable profiles in [FriendshipStore.swift](../../FitFight/FriendshipStore.swift#L50-L68).
- Adding a handle immediately inserts an **accepted** friendship without the other user's consent in [FriendshipStore.swift](../../FitFight/FriendshipStore.swift#L70-L90).
- No report, block, remove-friend, content filter, published community contact, or operational moderation path was found.

Apple-required controls if Guideline 1.2 applies:

- filter objectionable submissions;
- let users report offensive content/users and provide a timely operational response;
- let users block abusive users;
- publish contact information.

Additional first-release privacy/product recommendations for FitFight:

- Use exact-handle invitations and a pending accept/decline flow; do not auto-accept or offer partial public discovery.
- Add remove-friend in addition to Apple's required block control.
- Publish community/acceptable-use rules.
- Remove arbitrary fight/action text unless it is covered by the same controls.

Apple Guideline 1.2 requires UGC/social apps to provide filtering, reporting with timely response, blocking, and published contact information. [Guideline 1.2](https://developer.apple.com/app-store/review/guidelines/)

### 8. Build and prove a production App Store candidate

The current cloud automation deliberately produces staging TestFlight builds only. [ios-testflight.yml](../../.github/workflows/ios-testflight.yml#L5-L29) excludes `main`, while its environment step injects staging values in [ios-testflight.yml](../../.github/workflows/ios-testflight.yml#L65-L99). Fastlane has only a `beta` lane and `upload_to_testflight` in [Fastfile](../../fastlane/Fastfile#L141-L209).

A checked-in Release build falls back to production Supabase, but [BuildEnv.swift](../../FitFight/Generated/BuildEnv.swift#L4-L7) leaves `apiBaseURL` empty. Empty disables backend features in [APIConfig.swift](../../FitFight/APIConfig.swift#L3-L9), including Health upload and account deletion.

Before submission:

- Add a cloud-only production archive/upload lane that injects and validates the production Supabase configuration **and** `https://fitfight.app` API URL.
- Never promote the current staging TestFlight binary to review. The exact App Store candidate must say `prod`, use production data/services, and contain no staging credentials or labels.
- At the actual App Store ship, bump `MARKETING_VERSION` to **1.0.0** and add the required `Changelog.swift` release note. This is FitFight's project rule and good public-release signaling, not an Apple rule.
- Replace the App Store listing name **FitFight MVP** if a truthful available name can be secured; “MVP” and “Private beta” unnecessarily signal an unfinished app under Guideline 2.2.
- Keep the production backend and linked pages live throughout review.

Do not merge `develop` to `main` or submit until Marc explicitly asks to ship.

### 9. Give App Review immediate full access

FitFight uses Sign in with Apple, so sharing ordinary username/password credentials is not a clean reviewer solution. A fresh reviewer account also has no opponent or fight history.

Apple's default requirement is an active demo account. Guideline 2.1 permits a built-in demo mode in lieu of an account when legal or security obligations prevent providing one, but says to obtain prior Apple approval. Because sharing an Apple ID is inappropriate, choose one of two compliant paths before coding around the problem:

- obtain Apple's prior approval for a clearly disclosed demo mode with fictional pending, active, and completed two-person fights; or
- provide a durable reviewer-account/seeded-data path compatible with the shipped authentication and explain it precisely.

Either path must let one reviewer exercise every major state without recruiting another human, waiting days, or sharing an Apple ID password, while preserving a real Sign in with Apple + Apple Health path for functional testing.

Review access must include:

- pending invitation and accept/decline;
- live and completed Steps fights;
- a populated standings/history view;
- real Apple Health connect/deny/no-data behavior;
- privacy/withdrawal/deletion paths;
- exact navigation instructions and any demo caveats in Review Notes.

Apple requires an active demo account, or a prior-approved built-in demo mode where its stated exception applies, plus a live backend and any additional resources/instructions needed for review. [Guideline 2.1 and Before You Submit](https://developer.apple.com/app-store/review/guidelines/)

### 10. Complete the real-device validation gate

The product list still requires watching a real two-phone three-day fight close before App Store submission ([Notion Product Backlog](https://app.notion.com/p/3d38907c7ecf816facdff36cb59f463e)). App Store Connect processing proves packaging, not product correctness.

Run the exact production candidate through:

- fresh install, Sign in with Apple, username, sign-out/in, and relaunch;
- Health full access, limited history, no data, denial, later revocation, and reconnect;
- solo fight plus two-phone invite/accept/live/close/history;
- background upload, interrupted/resumed upload, app killed, network loss, and backend failure;
- matching standings on both phones and immutable final result after the grace period;
- delete account with and without existing fights and during an upload;
- clean re-registration after deletion;
- latest public iOS, oldest supported iOS/device class, small screen, dark/light, VoiceOver, large text, Reduce Motion, and offline states;
- IPv6-only DNS64/NAT64 networking, as Apple requires IPv6 compatibility. [Apple IPv6 guidance](https://developer.apple.com/support/ipv6/)

An external TestFlight pass with two real accounts is strong evidence. The latest build was internal-only with one tester.

## P1 review-hardening work

These are less likely than the P0 items to cause a standalone rejection, but they materially improve the reviewer's experience:

- Do not swallow friendship/fight-load failures into honest-looking empty arrays. Show a clear failed state and retry so a production outage does not look like “No fights yet.”
- Make support delivery truthful. The current local “Talk to the boss” thread can append an acknowledgement when no email was sent.
- Pin and commit the exact Swift package resolution used for the final privacy/export audit; the project currently permits Supabase to float within major version 2 even though the latest archive resolved 2.55.1.
- Add native tests around Health consent/withdrawal, deletion cleanup, and production configuration. Current CI compiles the app but there is no native XCTest target.
- Run accessibility QA. The design uses fixed custom-font sizes, several icon-only controls lack explicit labels, and press animations do not appear to honor Reduce Motion. VoiceOver and Dynamic Type problems are quality risks even when they are not the primary policy blocker.
- Select manual release for the first App Store version if Marc wants a final control point after approval.

## Draft App Privacy answers

Do not copy this blindly into App Store Connect. Reconcile it against the **final** binary, Xcode privacy report, production database, processors, CDN/server logs, backups, and support mailbox.

| App Privacy type | Why it applies | Linked | Purpose | Tracking |
| --- | --- | ---: | --- | ---: |
| **Health** | Step Count and any derived/raw HealthKit data sent to the server | Yes | App Functionality | No |
| **Name** | Full name requested through Sign in with Apple and stored as display name | Yes | App Functionality / Account Management | No |
| **Email Address** | Real or private-relay Apple email processed by auth | Yes | App Functionality / Account Management | No |
| **User ID** | Apple/provider subject, Supabase UUID, and public handle | Yes | App Functionality / Account Management | No |
| **Gameplay Content** | Fights, membership/matching, rules, scores, and outcomes | Yes | App Functionality | No |
| **Contacts** | The persisted in-app friendship/social graph; this is not an address-book claim | Yes | App Functionality | No |
| **Other User Content** | Fight/action text if retained | Yes | App Functionality | No |
| **Customer Support** | User-authored support email/content if retained | Usually | App Functionality | No |
| **Device ID** | Required only if current Health device local/UDI identifiers remain; the recommendation is to remove them | Yes | App Functionality | No |
| **Other Data Types** | Detailed source/device metadata and time-zone data if retained outside clearer categories | Yes | App Functionality | No |
| **Diagnostics / Product Interaction / IP-derived data** | Only if the app, Supabase, Vercel, CDN, or another processor retains it | Verify | Exact real purpose | No unless practices change |
| **Search History** | Handle searches if Supabase/Vercel/CDN logs retain the submitted queries beyond servicing the request | Verify | App Functionality | No |

Use **Health**, not merely Fitness, for HealthKit API data. Account-keyed Health data is linked even if opponents see only aggregates. “Tracking: No” is correct only if FitFight does not combine/share data for targeted advertising or measurement and does not use a data broker. Do not add an ATT prompt when there is no tracking. [Apple App Privacy definitions](https://developer.apple.com/app-store/app-privacy-details/)

## App Store Connect submission answers and assets

Complete and verify all of these against the final build:

- **App name:** remove “MVP”/beta signaling if an available truthful name is chosen. App name and subtitle each have a 30-character limit.
- **Version:** 1.0.0 for the actual first public ship; accurate “What's New”; no staging label.
- **Category:** Health & Fitness is the clearest primary fit, with Sports as a plausible secondary category. If Health & Fitness is selected, complete the new regulated-medical-device declaration.
- **Regulated medical device:** likely **No**—FitFight neither diagnoses nor treats disease. This declaration is required for Health & Fitness/Medical apps in US, UK, and EU/EEA availability. [Apple declaration guidance](https://developer.apple.com/help/app-store-connect/manage-app-information/declare-regulated-medical-device-status)
- **Age rating:** Apple's 2026 definition includes sport/fitness competitions. Since fights are the recurring core, **Frequent Contests**, producing a likely **13+** rating, is the defensible answer after removing money. [Apple age-rating definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions)
- **Gambling:** answer No only after every real-money wager/settlement mechanic and claim is removed. A noncash prize is not automatically gambling, but it can trigger contest rules, rating answers, and Guideline 5.3; the recommended 1.0 has no prizes at all. Do not present off-app settlement as a workaround.
- **Kids:** do not select Made for Kids or market “for kids.”
- **Privacy:** enter the live policy URL and the final label answers above.
- **Support:** live Support URL with contact details and response path.
- **Screenshots:** create them from the exact production UI with fictional identities and no real Health data. Do not use the current fixture screenshots showing staging, fake requests, unsupported metrics, Strava, pots, or payouts.
- **Description/keywords/subtitle:** describe only private Steps fights, Apple Health Step Count, standings, and the real business model. Avoid medical, measurement-accuracy, prize, real-time alert, or unbuilt-feature claims.
- **Review contact/notes:** reachable name, international phone/email, precise reviewer-access path, and Health/deletion explanation.
- **Price/business model:** free, no IAP, no ads, no prizes/wagering. IAP is not required when no paid digital functionality exists.
- **Content rights:** confirm all fonts, images, names, demo content, and trademarks are owned/licensed.
- **Export compliance:** verify the exact archive and all linked libraries before retaining `ITSAppUsesNonExemptEncryption = NO`. France can add documentation obligations when non-Apple standard encryption is embedded. [Apple export overview](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)
- **DSA:** declare trader/non-trader status. If distributing in the EU as a trader, complete Apple's public business-contact verification. [Apple DSA requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/)
- **Territories:** a US-only first launch matches the current product design and reduces regional scope. Expand only after privacy/consumer/contest review for each region.
- **Seller entity:** verify whether the developer membership is Individual or Organization and whether it is the legal entity providing FitFight. Apple flags incorrect-entity submission, especially for sensitive data. [Guideline 5.1.1(ix)](https://developer.apple.com/app-store/review/guidelines/)
- **Toolchain:** submissions have required Xcode 26 and the iOS 26 SDK since 28 April 2026; CI already uses `macos-26`. [Apple upcoming requirements](https://developer.apple.com/news/upcoming-requirements/)

## External health-privacy launch obligations

These are not merely App Store form fields, and this section is not legal advice.

- The FTC's updated Health Breach Notification Rule explicitly covers many health apps outside HIPAA and can require notice to users, the FTC, and sometimes the media after a breach of unsecured identifiable health data. FitFight combines identity/user input with connected Step data, so counsel should assess coverage and build an incident-response/breach-notification plan. [FTC rule](https://www.ftc.gov/legal-library/browse/rules/health-breach-notification-rule) and [FTC health-app guidance](https://www.ftc.gov/business-guidance/resources/mobile-health-apps-interactive-tool)
- If FitFight is offered to Washington consumers, the My Health My Data Act broadly regulates consumer Health collection/sharing. It requires a separate, conspicuous consumer-health-data privacy policy, affirmative consent for collection/sharing beyond what is necessary, deletion rights, and reasonable security; violations have a private right of action. [Washington Attorney General guidance](https://www.atg.wa.gov/protecting-washingtonians-personal-health-data-and-privacy) and [RCW 19.373](https://app.leg.wa.gov/RCW/default.aspx?cite=19.373&full=true)
- Health information can be sensitive personal information under California privacy law when applicability thresholds are met. [California Attorney General CCPA overview](https://oag.ca.gov/privacy/ccpa)
- Do not claim HIPAA compliance unless counsel confirms FitFight is actually covered and the implementation meets it. Do not call FitFight a medical device or medical advice.
- If any money, prize, entry fee, off-app settlement, or custom obligation returns later, pause for jurisdiction-specific contest/gambling, consumer, tax, age, KYC/AML, dispute, and App Review analysis. For 1.0, removing it is the materially safer decision.

## App Review Notes template

Use this only after every statement is true:

> FitFight is a free social fitness app for private Steps competitions. It has no in-app purchases, advertising, tracking, wagering, entry fees, money settlement, cash/physical prizes, medical diagnosis/treatment, or push-notification requirement.
>
> Account sign-in is required because the core service stores a private identity, invitations, two-person fights, synchronized scores, and history. Sign in with Apple is the only production login.
>
> Review path: `[exact durable reviewer path, or Apple-approved demo-mode instructions]`. Any disclosed fictional demo includes a pending invitation, active fight, completed fight, standings, and history. It does not write demo values to Apple Health. The real path remains available through Sign in with Apple.
>
> Apple Health: You → Data sources → Apple Health → Connect. FitFight requests read access only to Step Count and never writes to Apple Health. After explicit consent, it uploads `[final minimized data]` for scoring. Accepted fight participants see only `[exact totals/rank]`; raw Health data is not visible to them. Denying access does not crash the app and shows “No accessible Steps.” No Apple Watch is required.
>
> Disconnect/delete Health copy: `[exact path]`. Delete account: You → Settings → Delete account. This deletes the FitFight account and associated uploaded data and revokes Sign in with Apple as described in the policy.
>
> Privacy policy: `[live URL]`
>
> Support: `[live URL/email]`
>
> Review contact: `[name, international phone, email]`

Explain any limited-history behavior, the lack of push notifications, and how to refresh an incoming request. Never tell the reviewer that a visible dead or mock feature is “coming later”; remove it from the submitted binary.

## Final go/no-go gate

Do not press Submit for Review until every P0 box is true:

### Binary and product

- [ ] Steps-only and bragging-rights-only public scope.
- [ ] No fake Requests content, Design system, unsupported metrics, money/payout/custom-forfeit UI, beta/staging copy, or dead control.
- [ ] Every failure state is visible and retryable; backend errors do not look like an honest empty state.
- [ ] Current `Changelog.swift` release note and public version label are correct.

### Privacy, Health, and safety

- [ ] Live Apple-required privacy/support pages, an easily accessible in-app Privacy link, and Privacy available before Health consent.
- [ ] Project/legal launch gate: approved Terms/fight/safety rules and their final in-app placement.
- [ ] Explicit Health upload/participant-sharing consent; clear withdrawal/disconnect.
- [ ] Written Apple confirmation for participant-visible Health-derived scores, or a design changed to the confirmed permitted boundary.
- [ ] Health upload minimized and retention documented.
- [ ] Accurate read purpose string; truthful no-write update string retained because App Store Connect requires it for this signed archive.
- [ ] Valid app privacy manifest with `CA92.1`; exact archive privacy report reconciled.
- [ ] Accurate App Privacy label; no hidden analytics/tracking collection.
- [ ] Complete account deletion, Apple revocation, local purge, and clean re-registration.
- [ ] Apple-required filter/report/block/contact/moderation controls for retained social content.
- [ ] FitFight privacy hardening: exact-handle pending relationships and remove-friend.
- [ ] Concise safety/no-medical/no-prize rules in the app or linked terms.

### Production and testing

- [ ] Cloud-only production archive lane injects and validates production Supabase + API.
- [ ] Exact production candidate passes fresh-install, Health allow/limit/deny/revoke, sync, offline, deletion, and IPv6 tests.
- [ ] Two phones complete a real three-day fight with matching standings and a stable final result.
- [ ] Production Auth, API, database, Storage, cron, deletion, and public URLs are live.
- [ ] Review can exercise pending/live/completed two-person states without another person through a durable account path or prior-approved demo mode.

### App Store Connect

- [ ] Final name/version/category/description/keywords/screenshots/support/privacy fields match the binary.
- [ ] Frequent Contests / likely 13+ rating answered accurately; no gambling after scope cut.
- [ ] Regulated-medical-device answer completed, likely No.
- [ ] App Privacy, export compliance, content rights, DSA, territories, seller contact/entity, price, and release method verified.
- [ ] Specific Review Notes, a durable reviewer-access path or prior-approved demo mode, and a reachable review contact supplied.

## Work ownership

Agents can implement the product cut, Health consent/minimization, deletion, UGC controls, web pages, privacy manifest, production CI lane, tests, screenshots, and draft metadata without using a home Mac.

Marc/account-holder decisions remain:

- approve the first-release scope and legal text;
- confirm the developer membership/legal entity and seller details;
- choose launch territories and DSA status;
- obtain privacy/contest/export counsel where needed;
- approve the 1.0 name/metadata/screenshots and final production ship;
- complete any App Store Connect fields Apple restricts to the Account Holder.

No merge to `main` or App Store submission should happen until Marc explicitly asks.

## Primary-source index

- Apple: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [Avoiding common issues](https://developer.apple.com/app-store/review/), [App Privacy details](https://developer.apple.com/app-store/app-privacy-details/), [App Store Connect version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
- Apple Health: [HealthKit privacy](https://developer.apple.com/documentation/healthkit/protecting-user-privacy), [authorization](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data), [HealthKit HIG](https://developer.apple.com/design/human-interface-guidelines/healthkit), [Health and fitness apps](https://developer.apple.com/health-fitness/)
- Apple privacy manifests: [manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files), [required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api), [third-party SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/)
- Apple accounts/metadata: [account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/), [age ratings](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions), [regulated medical declaration](https://developer.apple.com/help/app-store-connect/manage-app-information/declare-regulated-medical-device-status), [DSA](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/), [export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)
- United States: [FTC Health Breach Notification Rule](https://www.ftc.gov/legal-library/browse/rules/health-breach-notification-rule), [FTC mobile health app tool](https://www.ftc.gov/business-guidance/resources/mobile-health-apps-interactive-tool), [Washington My Health My Data](https://www.atg.wa.gov/protecting-washingtonians-personal-health-data-and-privacy), [California CCPA](https://oag.ca.gov/privacy/ccpa)
