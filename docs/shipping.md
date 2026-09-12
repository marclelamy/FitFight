# Shipping

```
Marc (phone) → cloud Cursor agent → PR into develop
  → merge develop → preview when you want a TestFlight
  → merge preview → main when it should be production
  → App Store flow only when Marc asks
```

Not: agent on Marc’s laptop or home Mac → local Xcode.

## Workflows

| Workflow | File | When | Runner |
| --- | --- | --- | --- |
| Simulator | `.github/workflows/ios-build.yml` | PR + push to `main`, `develop`, or `preview` | `macos-26` |
| Screenshots | `.github/workflows/ios-screenshots.yml` | PR + push to `main`, `develop`, or `preview` | `macos-26` |
| TestFlight | `.github/workflows/ios-testflight.yml` | push to `preview` (app/fastlane paths), plus optional `workflow_dispatch` on that branch. No cron. Feature branches and `develop` do not upload. | `macos-26` |
| App Store candidate | `.github/workflows/ios-app-store.yml` | app push to `main`; uploads only and never submits for review | `macos-26` |
| Database | `.github/workflows/database.yml` | PR + push to `main`, `develop`, or `preview` | `ubuntu-latest` |
| Delete merged branch | `.github/workflows/delete-merged-branch.yml` | PR merged | `ubuntu-latest` |

The iOS workflows **must** stay GitHub-hosted. Never `self-hosted`. Apple requires **Xcode 26 / iOS 26 SDK** to upload (Xcode 16.4 / iOS 18.5 is rejected).

Fastlane: `fastlane/Fastfile` lane `beta` uploads staging TestFlight builds. Lane `app_store_candidate` is CI- and `main`-only, archives Release with production configuration, and uploads the binary to App Store Connect without selecting it or submitting it for review. Both use automatic signing + App Store Connect API key (`-allowProvisioningUpdates`) and share one non-cancelling concurrency group so signing and build-number allocation cannot race. The production lane does not revoke team certificates; it fails safely if automatic signing cannot create one. Do **not** also set `export_xcargs` to the same `-authenticationKeyPath` flags — gym passes `xcargs` into export and duplicates the flag.

Build number is not committed; CI sets `CURRENT_PROJECT_VERSION` at archive time from TestFlight (`latest + 1`). Ordinary TestFlight changes keep the current marketing version. The first App Store release is `1.0.0`; do not change it again until the next App Store version or Marc asks.

## Versions vs builds (why friends wait)

External TestFlight builds must be submitted for beta review and distributed to their tester groups. Apple fully reviews the first submitted build; later builds of the same marketing version may receive a shorter review, but approval is not guaranteed or immediate. Keeping `1.0.0` avoids unnecessary new-version reviews. See [Apple's external testing rules](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers).

That is why we do **not** bump `MARKETING_VERSION` on ordinary ships. We used to (0.4.1, 0.4.2, 0.5.0…) and every feature made testers wait for Apple again.

| What | Who sets it | When it changes |
| --- | --- | --- |
| Marketing version (`1.0.0`) | `MARKETING_VERSION` in `project.pbxproj` | App Store ship, or Marc asked |
| Build number (`105`) | CI / Fastlane at archive time | Every distribution upload |
| Versions list | `FitFight/Changelog.swift` | Every user-facing change; reuse the current marketing version |

The first release-candidate label is `1.0.0 · build N · staging`. Testers tap Update; ordinary follow-up builds keep `1.0.0` and only increment the build number.

### Internal-only uploads (default)

The beta lane waits for build processing, then **stops**. It does not assign the public join link (`https://testflight.apple.com/join/wcZKdwVZ`) or any other external group, does not submit beta review, and does not notify external testers. App Store Connect Internal testers receive each processed build automatically. Missing external groups do not fail CI. Uploaded builds are registered separately from the latest *installable* (external) release. The mandatory version still advances only after a build is `IN_BETA_TESTING` on every external group — so an internal-only upload does not push friends off the last public build (184 is already out and cannot be recalled).

Marc must be on **Internal Testing** in App Store Connect (Users and Access) to see new preview uploads. To send a specific build to the public join link later: App Store Connect → TestFlight → that build → add it to Friends Beta (or the public group) → Submit for Review / Start Testing, and notify testers if he wants. Do not re-enable CI auto-distribution unless he asks.

Apple allows only one build per version in beta review at a time and up to six beta review submissions in 24 hours. Upload limits are separate: the 5 Sep runs failed with `Upload limit reached` after build **153** uploaded successfully. Creating more builds does not release one already waiting for external review.

For the 5 Sep invitation report, build **114** (`d1a3534`, uploaded 2 Sep) still writes directly to `fight_members` when accepting or declining a username invitation. The server-owned-writes migration now denies those operations. Build **153** (`bc3795a`, uploaded 4 Sep) uses the authenticated backend commands. Historical unblock for friends was TestFlight → Friends Beta, Submit Review or Start Testing, Automatically notify testers. Friends then open TestFlight → FitFight → Update. Apple approval and each phone's installation timing remain outside CI's control.

Before a future migration removes an operation used by installed apps, verify that a compatible build is actually available to the external group. An uploaded internal-only build is insufficient. Preserve compatibility during rollout; do not reopen direct membership or score writes to support an old binary.

Run the release regression checks with `bundle exec ruby fastlane/testflight_test.rb`. They execute the beta lane with Apple and signing actions replaced by test doubles; they do not upload a build or verify a tester's live Apple account.

## Seeing the UI without a build

Every PR renders each screen in the simulator and uploads them as the `screens` artifact,
including `design-<name>.png` for each of the eleven design directions.
`FitFight/ScreenshotExport.swift` runs when the app is launched with `FF_SHOOT=1`, renders
each screen with `ImageRenderer` (scroll views stay blank in that renderer, so `FFScreen`
switches to a plain stack via `\.ffStaticRender`) and writes PNGs the workflow copies out
of the simulator container.

An agent can pull them and measure them against the design:

```bash
gh run list --branch <branch> --workflow Screenshots --limit 1
gh run download <run-id> -n screens -D /tmp/shots
```

That is the fidelity loop: measure `docs/design/source/screenshots/app/*.png`, change the
SwiftUI, push, download `screens`, compare the same numbers. Don't ask Marc to eyeball it.

## GitHub secrets (already set)

Names only. Never print values. Never ask Marc to paste the `.p8` into chat.

| Secret | What it is |
| --- | --- |
| `APP_STORE_CONNECT_KEY_ID` | Key ID for key named `FitFight GitHub` (Admin) |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID on Users and Access → Integrations |
| `APP_STORE_CONNECT_API_KEY` | Full `.p8` contents |
| `APPLE_TEAM_ID` | `C92DPD8ME2` |

There is a separate Expo EAS key in App Store Connect. Do not reuse it.

Do **not** add a Supabase `service_role` or `sb_secret_...` key to GitHub. Deploys use GitHub Integration. See [`backend.md`](backend.md).

## GitHub variables (TestFlight environment)

Names only. Never print values. Settings → Secrets and variables → Actions → Variables.

| Variable | Used when | What it is |
| --- | --- | --- |
| `SUPABASE_STAGING_URL` | every TestFlight | Persistent `develop` Supabase project URL |
| `SUPABASE_STAGING_PUBLISHABLE_KEY` | every TestFlight | Publishable key for that project (`sb_publishable_...`) |
| `FITFIGHT_API_URL` | every TestFlight | `https://staging.fitfight.app` |

Every TestFlight ships `https://zstzbfocunthczzubggz.supabase.co` (GitHub `SUPABASE_STAGING_*` variables override if set). The staging publishable key must be that project’s key, not production’s. Persistent `develop` must stay persistent so merging to `main` does not delete it. TestFlight CI builds the `preview` commit that triggered it. The top version label always shows `staging`. `main` never uploads to TestFlight.

## App Store production candidate

An app change merged to `main` starts `.github/workflows/ios-app-store.yml`. It waits until all four production routes are live and valid:

- `https://fitfight.app/api/health`
- `https://fitfight.app/api/app-release`
- `https://fitfight.app/privacy`
- `https://fitfight.app/support`

The workflow injects the production Supabase project, its iOS publishable key, and `https://fitfight.app` into `BuildEnv.swift`. Before upload it verifies the production Supabase URL/key, confirms its Apple provider is enabled, and requires the API health check to prove the production database, latest deletion migration, server key, and Apple server credentials are ready. It then checks the signed IPA for HealthKit background delivery, a valid privacy manifest, and the production configuration, and rejects any generated staging configuration. The public defaults match the values already compiled in the app; optional repository variables `SUPABASE_PRODUCTION_URL` and `SUPABASE_PRODUCTION_PUBLISHABLE_KEY` can rotate them, but the URL must remain the documented production project and the key must validate against it.

Fastlane increments only the build number. The workflow requires the project marketing version to equal `FITFIGHT_RELEASE_VERSION` (`1.0.0`) and requires a matching `1.0.0` release note. The reviewed App Store release PR into `develop` carries that version and launch note. Marc then merges `develop` → `preview` when he wants a TestFlight, and `preview` → `main` when he approves the production ship. The workflow does not change `MARKETING_VERSION`, upload metadata or screenshots, submit the build for review, or release it. After it succeeds, the candidate waits in App Store Connect for the separate metadata, review-information, build-selection, and submission steps.

Vercel also needs `CRON_SECRET` (Preview + Production). Vercel Cron sends it as `Authorization: Bearer …` to `/api/internal/close-fights` once daily at **03:00 UTC**, which is compatible with Hobby. **Hosted Supabase Cron** on develop and production should call the same route every **15 minutes** so fight-end sync reminders (T+0, 12h, 6h, 1h left) fire on time; the daily Vercel job stays a backup closer. Opening the app also closes due fights and drains the notification outbox, so neither cron is the only path. Never put this value in git or chat.

Vercel Preview + Production also need the FitFight APNs secrets from [`docs/research/apns-remote-push-plan.md`](research/apns-remote-push-plan.md): `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_TOPIC`, and `APNS_TOKEN_ENCRYPTION_KEY` (separate from Sign in with Apple). Without them the outbox enqueues intents but send stays a no-op.

## What Marc still does

- Be listed under App Store Connect **Internal Testing** so new `preview` uploads appear in TestFlight (no beta review).
- TestFlight → Update when a new *internal* build is ready (~10–20 min after a `preview` push). The public join link does **not** get that build automatically.
- Later, when friends should get a specific build: App Store Connect → TestFlight → that build → add to Friends Beta / the public group → Submit for Review or Start Testing. External: Apple may review; later builds of the same version may still need review. Friends can enable Automatic Updates inside TestFlight.
- Apple account / legal / new secrets if they rotate.
- After a production candidate passes: finish the App Store Connect metadata and review information, select the uploaded build, and explicitly submit it when ready.

He should **not** operate certificates day to day, open Xcode, or use a Mac for builds.

## Feature branches

After a feature PR merges, CI deletes that branch. `main`, `develop`, `preview`, and `testflight-latest` stay — we ship by merging `preview` into `main`, so GitHub’s “Automatically delete head branches” toggle must stay **off** (it would delete `develop`). `testflight-latest` stores public release metadata (`releases.json`), the builds that contain the update gate (`builds.json`), and `latest.json` for older TestFlight notices; it is not app code.

## Agent limits on GitHub

- `gh` here is effectively read-only for Actions (cannot `workflow_dispatch` or set secrets).
- Opening/updating PRs: use the PR tool, not `gh pr create`.
- Don’t merge unless Marc asks. Feature PRs go onto `develop`. TestFlight is merging `develop` → `preview`. Production is merging `preview` into `main`.

## After you push app changes

A push to `preview` that touches the app or Fastlane starts TestFlight. Feature-branch and `develop` pushes do not. Tell Marc only after that upload: wait for the TestFlight notification, then **Update** (internal testers only). Processing often takes ~10–20 minutes. Do not tell friends the public join link has a new build unless Marc promoted that build in App Store Connect. Check the workflow result before promising a build. Do not ask him to Run workflow.

Both staging and production binaries check `/api/app-release` at launch, on foregrounding, and every minute while active. Fights (or the last cached list) stay on screen. A new installable build shows a small dismissible popup with a TestFlight or App Store link. A failed or offline check does not lock the app. Known mismatches still survive relaunch.

## Mandatory updates and database rollout

**Always require the latest installable version/build.** There is no independently adjustable minimum. Marketing version remains `1.0.0` for TestFlight; build numbers distinguish releases.

`fastlane refresh_app_releases` reads Apple availability. A staging build must be valid, unexpired, in `IN_BETA_TESTING`, and assigned to every external group. Production uses only `READY_FOR_DISTRIBUTION` App Store versions and their exact build; `PROCESSING_FOR_DISTRIBUTION` is not installable yet. A registered staging build waiting for or in beta review is separately admitted. For production, the registered build selected in App Store Connect is admitted for review; uploading or submitting it never replaces the public release. The public registry contains only channel/version/build numbers, no Apple credentials.

Upload workflows register binaries that contain the update dialog. The first release containing it activates backend enforcement automatically; before that, the existing clients keep working without version headers. Once activated, enforcement cannot silently revert to a binary lacking the gate. App versions without the dialog cannot acquire it remotely: their backend requests will be rejected after the first gated release becomes mandatory, so they must install that release through the store.

`.github/workflows/app-releases.yml` refreshes availability every 15 minutes on GitHub-hosted Linux, using the existing App Store Connect secrets. Upload jobs also refresh it. All publishers share `ios-distribution` concurrency and preserve the pointer branch history. GitHub schedules only run once the workflow exists on the default branch; include it in the normal production promotion before relying on updates after Apple review. Scheduling and Apple's availability propagation can delay the requirement; the app does not pretend that upload success means installation is possible.

Deployment order:

1. Publish `releases.json` from the cloud workflow before deploying the new version checks. It initially records the existing installable release with enforcement off if that binary predates the gate. The server selects staging or production from the existing `NEXT_PUBLIC_SUPABASE_URL`; client headers cannot choose another release channel. Deploy `/api/app-release` and the compatible backend before distributing the new native build. A missing/invalid manifest or release-channel configuration blocks requests with `503`; it must not silently disable an active requirement.
2. Database changes must preserve supported API contracts and running backend versions. Internal column renames, constraints, and cleanup do not automatically wait for Apple; stage backend/database changes as needed. During review, preserve the API behavior and information required by both the live app and its candidate. New response fields must be ignored by old decoders; new request fields must not become required for supported clients.
3. After a production build is selected for submission, verify that `/api/app-release` identifies it as `review` before Apple tests it. The live public app keeps working. This check does not submit or release anything.
4. When Apple makes the update installable, the publisher makes that exact version/build the advertised latest automatically. Authenticated commands with missing or mismatched `X-FitFight-Version` / `X-FitFight-Build` receive `426 update_required` before business logic runs. The app keeps last Fights usable and shows a small update popup; it does not hide the home screen.
5. Retire API behavior needed by an older app only after verifying its replacement is installable and required, including compatibility of admitted review candidates. Internal database cleanup can happen sooner if supported APIs and running backends remain compatible. The update gate does not secure direct table access or replace RLS. Follow existing migration/merge authorization rules.

For the initial profile migration: apply `20260909132922_backend_profile_reads.sql`, deploy
`GET/PATCH /api/v1/me` and the backend using `fitfight_backend_reader`, verify readiness,
then distribute the native build. Preserve old client grants during this stage. Only
later promote the cutoff from [`supabase/deferred-migrations`](../supabase/deferred-migrations/README.md),
after installability, enforcement, review-candidate compatibility, staging checks, and
old-backend drainage are verified. CI tests both permission states on disposable Supabase.

Verification: Ruby release tests cover review, group availability, expiry, the first gated rollout, and production candidates. The GitHub-hosted macOS simulator workflow also runs `tests/AppUpdateCheckerTests.swift` for persistence, failed checks, exact matching, review access and concurrent checks. Check both English and French, launch/resume, that Fights shows immediately, a small update popup appears only when a new build is required, a failed check does not lock the app, and the store link works on a real staging build before shipping.
