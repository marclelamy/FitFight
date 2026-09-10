# Backend

Production Metric is **Steps**. Phone vs server status: [`status.md`](status.md). Fights, memberships, scores, and data sources are writable only by the backend. Native Accept and Decline use authenticated commands; database grants deny direct client mutations. For Apple Health, it asks HealthKit for Apple's merged cumulative total over each exact Fight window and sends those totals to one authenticated Next.js endpoint. It may also send Apple's merged daily buckets for the active Fight days needed by charts; those buckets never determine the Fight score. The same request may include private activity totals and workout summaries that are not used for scoring. The backend validates the User, Fight membership, server-issued windows and cutoffs, then stores the exact-window snapshots and updates standings in a TypeScript-owned Postgres transaction. There are no app-facing database RPCs.

[`system-design.md`](system-design.md) is the golden guide. This folder is the first slice of it, not the whole thing. Do not add Active Minutes, Workout Count, WHOOP, Strava, payments, notifications, or a website until the backlog says so. Fight posts and photo uploads go through the API below.

Hosted production (no secrets): https://pvqntpteehdvhqyctwum.supabase.co  
Hosted staging / git `develop` (no secrets): https://zstzbfocunthczzubggz.supabase.co

## Application database boundary (prepared 9 Sep 2026; not deployed)

The native app uses Supabase directly only for Auth. All application database reads
and writes use the authenticated FitFight API. `GET /api/v1/me` returns
`user_id`, `handle`, `display_name`, nullable `handle_set_at`, `referral_code`,
and nullable `avatar` (the shared media object).
`PATCH /api/v1/me` accepts a handle, display name, `avatar_media_id`, or any mix;
omitted fields stay unchanged. `POST /api/v1/media` mints a private signed upload
for a photo or short video; `POST /api/v1/media/{id}/commit` verifies size and checksum.
`GET /api/v1/feed` and `GET/POST /api/v1/fights/{id}/posts` are the fight feed.
Listing a fight includes posts from other windows in the same recurring series.
Roster members (`accepted` or `deferred`) can read and post. Invited-only
members cannot. Delete own posts; report or hide another author.
The verified session owns the operation. TypeScript normalizes and validates handles,
sets their timestamp, and translates uniqueness conflicts to `409 handle_taken`.
Missing/deleted profiles return `401 profile_missing`; account deletion remains `DELETE`.

The Fight snapshot assumes `fitfight_backend_reader`, a restricted no-login role with
no RLS bypass or client write privileges. Only the server's `postgres` connection can
assume it. Verified user claims and the existing SELECT policies preserve row visibility.
Self-profile operations use explicit fields and owner filters through the server admin
client. Response schemas and shared Swift/TypeScript fixtures define the API independently
of table layout; extra database columns never automatically become API fields.

First apply `20260909132922_backend_profile_reads.sql`, then deploy the backend and verify
`/api/health` reports `profile_api: true`, then distribute the native build. Both
distribution workflows require this readiness marker. Existing client grants remain
through this stage. The separate cutoff in [`supabase/deferred-migrations`](../supabase/deferred-migrations/README.md)
must stay outside automatic migrations until the compatible build is installable and
required, all admitted review builds are compatible, and old backend instances have drained.
The cutoff includes column grants and global/per-schema future-object defaults. Keep the
server Data API and Auth/signup working; do not globally disable the Data API.

Internal database changes can ship independently of Apple when the supported API and
running backend versions remain compatible. Dropping or renaming a column requires a
safe backend migration, not automatically an iOS release. Removing information or API
behavior an admitted app still requires waits for that app to be retired. Destructive
SQL and hosted deployment still follow Marc's authorization rules.

## Friend referrals (pending deployment)

Profiles carry a stable, read-only `referral_code`; there is no link-generation endpoint.
Authenticated `POST /api/v1/referrals` accepts `{ code }` and records the first referrer
in `private.referrals`. Self-referrals and duplicates do nothing. Relationships use
account IDs and cascade on deletion of either account. This counts attributed accounts,
including existing accounts, not clicks or installs. Deploy the referral migration and
backend before the native build. See the install handoff in [`status.md`](status.md).

## Loop

A cloud agent writes SQL in `supabase/migrations` and tests in `supabase/tests`, then opens a PR **into `develop` only when Marc explicitly asks for a PR**. Marc merges that. The persistent Supabase branch `develop` picks it up. TestFlight is a later merge to `preview`. Production only changes when Marc merges `preview` → `main`. Agents do not get the database password or `sb_secret_...` key, and they do not merge unless Marc asked.

GitHub-hosted **Ubuntu** starts disposable Supabase Postgres, Auth, and the Data API, lints the schema, runs pgTAP and TypeScript transaction tests, and rejects `DROP TABLE` / `TRUNCATE` / `DROP COLUMN` unless the **first line** of the file is exactly `-- allow-destructive`. The same backend tests run again after applying the deferred client-permission cutoff, including real signed-in Data API denials and signup. Agents do not run this stack on Marc's Mac or a hosted project.

iOS TestFlight is unchanged and still ignores this folder. iOS simulator and screenshot jobs skip when the PR does not touch the app.

## GitHub Integration fields

In the project: **Project Settings → Integrations → GitHub**.

| Field | Value |
| --- | --- |
| GitHub repository | `marclelamy/FitFight` (same repo as `slooowshutter/FitFight`) |
| Working directory | `.` |
| Deploy to production | On |
| Production branch | `main` |
| Automatic branching | On |
| Branch limit | `3` (preview branches cost extra; do not raise this) |
| Supabase changes only | On |

Then **Enable integration**. Do not paste a secret key, `service_role` key, or database password into GitHub. Those are legacy for this loop. Deploys go through the GitHub app, not a key in Actions.

GitHub branches:

| GitHub branch | Meaning | Hosted database |
| --- | --- | --- |
| Feature (`cursor/…`) | One piece of work | Preview (only if `supabase/` changed, max 3) |
| `develop` | Integration / staging site | Persistent Supabase branch named **`develop`** |
| `preview` | TestFlight cut | Same persistent `develop` project |
| `main` | Production | The main project |

In **Branching**, create one long-lived branch named **`develop`** (not `staging`). It tracks the GitHub `develop` branch. Feature PRs merge into `develop`. GitHub `preview` only cuts TestFlight binaries; it must not become an extra hosted database. When Marc wants a TestFlight, he merges `develop` → `preview`. When he wants production, he merges `preview` into `main`.

## So an agent cannot nuke production

- Production changes only by merging `preview` into `main`. Agents open PRs into `develop` only when Marc explicitly asks. They do not merge unless Marc said so in that chat.
- CI refuses destructive SQL (`DROP TABLE`, `DROP SCHEMA`, `TRUNCATE`, `DROP COLUMN`) unless Marc approved it and the **first line** of the migration is exactly `-- allow-destructive`.
- Agents never receive `sb_secret_...`, the old `service_role` JWT, or the database password. Never put those in git, chat, or iOS.
- Never run `supabase db reset`, `supabase db push`, or `DROP DATABASE` against the hosted project.
- Prefer additive migrations (expand → migrate → contract).
- Keep the preview branch limit at 3.

Marc’s extra lock (GitHub ruleset **Protect main**): target **`main`, `develop`, and `preview`** → require a pull request, required approvals **0**, require status check **Migrations and RLS**, block force pushes. That stops a push onto those branches without the database check. You still tap merge. You cannot approve your own PR, which is why approvals stay at 0. If the ruleset still lists only `main` and `develop`, add `preview`.

## Commands (disposable cloud CI)

```bash
python3 scripts/forbid-destructive-sql.py
npx supabase@2.115.0 start -x studio,meta,analytics,vector,imgproxy,realtime,storage,edge-runtime
npx supabase@2.115.0 db lint --local --schema public,private --fail-on error
npx supabase@2.115.0 test db --local
```

Pin the CLI to **2.115.0** until you mean to bump it (`config.toml` was generated with that version).

The iOS publishable key (`sb_publishable_...`) production fallback lives in `FitFight/SupabaseConfig.swift`. The secret key is not.

Vercel holds `DATABASE_URL`, using Supavisor transaction mode on port `6543`, separately for develop and production. It is a server-only database password and never belongs in GitHub, chat, or iOS. `private` stays absent from the Data API's exposed schemas.

Vercel also holds the server-only Supabase URL and secret used to authenticate requests and perform reviewed admin operations. Neither value belongs in iOS or chat.

Native Sign in with Apple sends its short-lived authorization code to authenticated
`POST /api/v1/auth/apple`. The server exchanges it with Apple, checks the returned Apple
subject against the User's Supabase Apple identity, encrypts the refresh token, and stores
it in `private.apple_sign_in_tokens`. Vercel holds the Sign in with Apple Team ID, key ID,
private `.p8`, client ID, and a separate 32-byte encryption key. `DELETE /api/v1/me`
loads any revocation token, removes pending private Storage objects, deletes Fights owned by
the User, removes the User from other Fights, and hard-deletes the full auth account before
making a bounded Apple revocation request. Apple cannot block FitFight deletion. Legacy
accounts without a stored Apple token still delete; the app gives the manual Apple Settings
disconnect path.

`GET /api/v1/provider-uploads/context` temporarily remains the context route and returns the server time plus exact live/awaiting-final-sync Fight windows. `POST /api/v1/healthkit/steps` accepts one strict JSON document with `complete_through`, the User's `time_zone`, `merged_days`, and `fight_aggregates`. `fight_aggregates` are Apple's merged cumulative totals from each server-authoritative `starts_at...cutoff_at` interval and are the only input to standings. `merged_days` are limited to relevant active Fight days and serve charts only. The request contains no raw sample, deletion, per-source statistic, device/source metadata, anchor, NDJSON, object path, or upload capability.

`POST /api/v1/healthkit/diagnostics` retains the latest private operational snapshot and accepts an optional batch of completed timing attempts. Old native payloads that omit empty timestamp/error fields remain accepted. Attempts contain a random trace ID, trigger, outcome, elapsed stage timings, app version/build, optional counts/encoded payload size, and optional stage errors with a fixed kind and numeric system code or HTTP status. They contain no Steps values, Fight IDs, device identifier, free-form errors, or raw HealthKit data. `private.healthkit_sync_attempts` is inaccessible to app clients and Fight peers and cascades on account deletion. Reports keep at most the newest 100 attempts per User; that User's rows older than seven days are pruned on their next report. An inactive account's older rows can remain until then or account deletion.

Fight peers can read only `fight_members.final_steps_complete`, which indicates an available snapshot from that member's selected source at the exact Fight end. A source-wide watermark alone cannot establish this. It describes query coverage, not a guarantee that Apple has received all delayed device data.

The older one-object archive migrations, `private.provider_uploads` / `private.provider_events` tables, `provider-inbox` bucket, archive contract, and provider-upload create/status/process routes remain legacy infrastructure during the additive rollout so older builds and migration history are not rewritten. The aggregate-only sync does not create new archive rows or Storage objects and does not use TUS. Remove that legacy surface separately only after incompatible TestFlight builds no longer need it.

Every TestFlight binary talks to the develop project. The workflow runs on push to `preview`, or manual `workflow_dispatch` on that branch, and rejects `main` and `develop`. CI writes `FitFight/Generated/BuildEnv.swift` before archive. GitHub variables `SUPABASE_STAGING_*` override if set; otherwise the known develop URL and publishable key are compiled in. Production configuration belongs only to the future App Store flow. See [`shipping.md`](shipping.md). What is live on the phone: [`status.md`](status.md).

## Security and finalization boundary (5 Sep 2026)

`POST /api/v1/fights/{fightID}/decline` requires an invited membership belonging to
the signed-in User. It locks the Fight and membership, declines it, and revokes its
invitations in one transaction. Repeating a successful decline is harmless.

Recalculation locks the Fight, then accepted memberships, before reading the latest
selected-source exact-window snapshots. It freezes scores, completeness, selected
snapshots (`is_final`), and Fight state in the same transaction. It never substitutes
raw observations or daily chart totals. The existing policy remains: finalize when
every accepted participant has an end-cutoff snapshot, or after the 24-hour grace
period with missing data marked incomplete. The choice of a full 24-hour provisional
period remains a product decision; Apple provides no historical immutability deadline.

The snapshot fingerprint includes the read's `complete_through` timestamp. Replaying
the same reading is idempotent, but a later reading that returns to an earlier total
creates a new snapshot and can become the latest correction at the same Fight end.

## Request performance and timing (5 Sep 2026)

`POST /api/v1/fights/refresh` accepts `{ "time_zone": "Europe/Paris" }`, performs the User's due maintenance, and returns `{ fights, members, profiles, series, step_days }` together. The snapshot uses one data query inside a read-only transaction with `SET LOCAL ROLE fitfight_backend_reader` and transaction-local claims for the verified User. Existing RLS governs every returned row, including invited/declined membership limits and day-specific peer Steps access. Role and claims reset on commit or rollback before the pooled connection is reused. Maintenance checks the User's memberships and due recurring series in one query; ordinary refreshes no longer scan every account's series through REST. Separate due Fights are still finalized sequentially, and recurring creation retains its existing roster-copy logic.

An aggregate upload uses at most eight SQL statements, excluding BEGIN/COMMIT, independent of Fight/member count. Finalizing one Fight uses at most six. TypeScript still owns scoring; batched writes preserve the existing transaction and lock boundaries. Snapshot inserts remain separate from reads of the latest snapshot, preserving corrections that return to an earlier total.

Each foreground/manual refresh and observer opportunity owns a trace. Native `ContinuousClock` measures permission prompts separately, today's HealthKit read, context retrieval, merged-day and each exact-window HealthKit query, upload, and final Fights refresh. The total ends after the final requested app work and mapping/cache updates. Observers omit the screen refresh they do not perform; expiry records a cancelled attempt once. Routine token retrieval uses the SDK's valid session accessor; account deletion still explicitly renews its session.

The native API sends `X-FitFight-Trace-ID` for context, upload, and Fights refresh. Their responses include `Server-Timing` for `auth`, `db`, optional `maintenance`, and `total`, including failures. Structured `fitfight_request` Vercel logs contain the same trace ID, fixed operation name, status and durations only. Server `db` includes pool acquisition, locks, and the whole database operation; it is not an isolated query execution time. Server `total` starts at handler entry and excludes earlier cold-start time. Compare each stage's client duration with its server timing; never subtract phone and server wall-clock timestamps.

One immutable completed attempt is logged locally under OSLog category `HealthKitPerformance` and sent through the existing diagnostics endpoint after product work completes. Reporting is best effort and is excluded from the attempt's own duration, avoiding recursive timing reports. Network loss, suspension, or termination can prevent server delivery; there is no background retry queue. The underlying HealthKit callback may still finish after observer expiry, but cancellation prevents a subsequent upload from that expired attempt.

Failed stages preserve HealthKit/URL/Cocoa numeric errors, HTTP status, decoding/configuration failures, and the app's unavailable/invalid Steps errors. Unknown error domains are reduced to `unknown`; messages, URLs, query predicates and `NSError.userInfo` are never logged. The existing `stages` JSON stores these details without another migration. After authentication and validation, the diagnostics route emits `fitfight_healthkit_failure` to Vercel logs before database persistence, with trace ID, app version/build, trigger, outcome and failed stages. Legacy reports such as build 153 emit their coarse error only; discarded device errors cannot be recovered retroactively.

You → Apple Health retains a per-account error reference containing the trace ID's first eight characters, stage and safe error code, including when diagnostic delivery fails. Match that prefix against `fitfight_healthkit_failure` and the full trace ID against `fitfight_request`. Delivery failures also log locally under `HealthKitDiagnostics`; the next successful Steps sync clears the phone's reference. Deploy this expanded diagnostics schema before distributing the native build.

Apply `20260905090813_healthkit_sync_timing_history.sql`, deploy the backend, then distribute the native build. The new app requires the refresh endpoint. Legacy diagnostics remain compatible after migration/backend deployment. This change has not been deployed from the workspace.

An absent HealthKit sum is unavailable, not a measured zero. The current native batch
stops without overwriting saved data if any Fight window has no accessible sum. Daily
buckets without a quantity are omitted. A future per-Fight availability contract can
allow unaffected windows to progress without manufacturing complete zero results.

Deploy the API (including Decline) before the server-owned-write migration, and use
the new TestFlight build. Older builds that directly accept or decline through
Supabase will receive a permission error after the migration. Feature-branch pushes
alone do not apply the hosted migration. No existing finalized scores or hosted
previously-deleted accounts are rewritten by this change.
