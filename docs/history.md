# History

## 2026-08-30 — TestFlight is staging only

TestFlight never builds `main` and never connects to production. Every feature/develop TestFlight uses the persistent develop Supabase project and staging API. Production binaries belong only to the future App Store flow when Marc explicitly asks to ship.

## 2026-08-30 — one-object HealthKit pipeline

One HealthKit sync now creates one protected NDJSON archive and one private Storage object, identified everywhere by one UUID-v4 `upload_id`. TUS can resume the transfer without creating FitFight-level pieces. The server verifies size and SHA-256, commits raw events/canonical observations/frozen daily values/exact Fight aggregates, deletes the object, and only then lets the phone save its HealthKit anchor. Scheduled TestFlight explicitly builds `develop` against staging; the protected Fight closer runs once daily for Vercel Hobby.

## 2026-08-27 — recreate persistent develop

The old staging host `jldjgftoxmluiswpebbd` was a preview branch and died when `develop` merged to `main`. Recreate staging as a **persistent** Supabase branch named `develop` so that does not happen again. New host: `zstzbfocunthczzubggz`. GitHub `develop` was never deleted.

## 2026-08-26 — production + Start fight lock

`develop` merged to `main` (#32). Production TestFlight talks to prod Supabase. Start fight shows Starting… and ignores extra taps so one tap cannot insert duplicate fights.

## 2026-08-24 — freeze marketing version for TestFlight

Apple beta-reviews the first build of each marketing version for external testers. We were bumping `0.4.1`, `0.5.0`, `0.8.0` on every user-facing PR, so friends waited every time. Rule: keep `MARKETING_VERSION` at `0.8.0`; CI still increments the build number; Changelog rows reuse `0.8.0`. Bump marketing version only for an App Store ship or if Marc asks.

## 2026-08-25 — phone writes the fight

Create / accept / HealthKit upload / standings no longer wait on Vercel. The phone writes to Supabase. Username onboarding. Design tab removed. Version line shows version and build. Cron is optional later, not required.

## 2026-08-25 — status map

[`status.md`](status.md) is the works / fake / dead / next list. Merge #30 into `develop` only. Do not invent Ask-first screens.

## 2026-08-25 — welcome gate

Signed-out Users see FitFight, one line of copy, and Sign in with Apple. The five tabs stay hidden until they are in.

## 2026-08-25 — date on the version line

Every TestFlight ship adds a Changelog row and puts that date on the top version line (`0.9.0 (n) · staging · 25 Aug`). Stay on `0.9.0` — phones already have it; TestFlight will not replace it with `0.8.0`.

## 2026-08-25 — version label shows prod vs staging

TestFlight that is not `main` compiles the persistent develop project. The top version label ends in `prod` or `staging`. Production is only `main`.

## 2026-08-25 — Fight duration closer

A 3 / 7 / 14 day fight can now finish without waiting those days in real time: tests pass a fake clock. Opening the app closes due fights. A Vercel cron hits `/api/internal/close-fights` so a fight still settles if nobody opens. Steps after `ends_at` do not count. 24h grace, then final even if someone never uploaded.

## 2026-08-24 — Live Steps Fight

New fight and fight detail talk to the server: add friends by handle, start a real Steps fight, Accept/Join a live invite. Apple Health uploads; standings come from the database. Fights are no longer the fixture people. Marketing version stays `0.8.0`; CI bumps the build number.

## 2026-08-24 — Sign in with Apple + HealthKit Steps read

First slice of a real Steps Fight, still on the fixture Fights tab. You signs in with Apple (Supabase Auth), shows the `profiles` handle, reads today’s Apple Health aggregate Steps on Data sources, and can delete the account from Settings. HealthKit is not uploaded yet. Marketing version `0.8.0`.

## 2026-08-24 — delete feature branches on merge

CI deletes the merged PR’s head branch. `main` and `develop` are kept. GitHub’s repo toggle stays off so shipping `develop` → `main` cannot delete `develop`.

## 2026-08-24 — develop is staging, main is production

GitHub `develop` is the testing branch. Feature PRs merge into `develop`. Production is merging `develop` into `main`. The persistent Supabase branch is also named `develop`.

## 2026-08-24 — hosted project + no-nuke rules

Production project URL is `https://pvqntpteehdvhqyctwum.supabase.co`. GitHub Integration deploys migrations on merge to `main`. CI blocks destructive SQL. Secret/service keys stay out of GitHub.

## 2026-08-24 — system design and empty platform

Approved architecture lives in `docs/system-design.md` (golden guide, not a build-all checklist). `supabase/` is the empty Steps-only schema plus Ubuntu CI. Hosted US East project is still Marc, once. No HealthKit and no Next.js yet.

## 2026-08-23 — Talk to the boss

Requests tab gained a private chat with Marc. Messages are emailed to him until
there is a backend. Marketing version `0.7.0`.

## 2026-08-22 — TestFlight on every app push

Any app push (PR branch or `main`) uploads to TestFlight. Marc tests with TestFlight → Update. No GitHub tap. Daily 18:00 UTC stays as a safety net.

## 2026-08-22 — TestFlight on merge

App pushes to `main` upload to TestFlight without a second “Run workflow” tap. Daily 18:00 UTC and manual branch runs stay. Marc tests by opening TestFlight → Update.

## 2026-08-22 — approved design ported

`docs/design/source/` dump from fitfight-v2. SwiftUI now has four tabs matching that kit. Arena/Pulse/Locker/Rogue retired. Marketing version `0.3.0`.

## 2026-08-22 — design system

Tokens in `FitFight/DesignSystem/themes.json` (later replaced). Four placeholder themes (Arena, Pulse, Locker, Rogue). Marketing version `0.2.0`.

## 2026-08-22 — loop proven

Cloud agent (not Marc’s Mac) created the SwiftUI app, Fastlane, and GitHub Actions in https://github.com/marclelamy/FitFight.

Marc (Account Holder) did the one-time Apple side:

- Registered App ID `com.fitfight.mvp` (explicit, no capabilities).
- App Store Connect app: listing name **FitFight MVP** (plain FitFight taken), SKU `fitfight`.
- App Store Connect API: Request Access, then key **FitFight GitHub** (Admin). Secrets added on the GitHub repo.
- Merged pipeline PR #1, then **Run workflow**.

CI failures before the first successful upload:

1. `xcodebuild: option '-authenticationKeyPath' may only be provided once` — Fastlane gym concatenated `xcargs` + `export_xcargs`. Fix: `xcargs` only.
2. App Store Connect 409: built with iOS **18.5** SDK (runner `macos-15` / Xcode 16.4). Required iOS **26** SDK. Fix: `runs-on: macos-26`.

Successful upload: [TestFlight run #32580212460](https://github.com/marclelamy/FitFight/actions/runs/32580212460) on `main` (`c32176a`), ~4m40s. First binary: **0.1.0 (1)**.

## Don’t repeat

- Do not scaffold on `/Users/marclamy/...` or treat any local Mac folder as source of truth.
- Do not add a home runner “because Marc has a Mac.”
- Do not send Marc through App Store Connect documentation while he’s in a voice loop.
