# Pending result, 24h forfeit, final-sync reminders

**Tonight (10 Sep 2026): docs + Notion only. No app, backend, or SQL.**
**Implement tomorrow from this file.** APNs deep-dive: [`apns-remote-push-plan.md`](apns-remote-push-plan.md).

Notion: [Finished list shows Won](https://app.notion.com/p/3d78907c7ecf81ab9841de8bb8cfcc4c) (P0 Bug) · [Pending result epic](https://app.notion.com/p/3d78907c7ecf811e8190f2fef3953e4a) (P0 Feature).

---

## What Marc saw (build 175)

1. **Fights → Finished** showed **W** on `100$ openrouter` and `20k€ crédit FlexoAi`.
2. Opening `100$ openrouter` showed the fight **already ended** (22:00, 10 Sep).
3. Standings: Marc **Final steps synced · Just now · 81.5K**. Samuel **Waiting for final steps · 10 hours · 66K**.
4. The fight page still used the live **VS** chrome and treated Marc like a winner.

The 10 hours is **how long since Samuel’s last upload**, not grace remaining. He synced during the live window. That is not a final result.

---

## Locked product rules

1. **Submitted** = the person opened FitFight after `ends_at` and the server stored an exact-end snapshot (`cutoff_at === ends_at`, `final_steps_complete = true`). A mid-fight sync does **not** count.
2. Until every **accepted** member has submitted, **or** 24 hours after `ends_at`, the home Finished row shows **P**. Never **W** / **L**.
3. **W / L** only after the fight is `final`.
4. Opening a pending fight is a **settlement** screen, not the live VS screen: tentative result → one existing chart (Pace) → ranking.
5. People who have not submitted sit **at the top** of the ranking, marked pending. Submitted people sit below with a tentative rank.
6. Words: **Pending** / **Tentative lead** / **Tentative loss**. Not “you won.” Not “potential winner.”
7. Everyone has **24 hours** after `ends_at` to submit. Miss it → **you lose** (forfeit). Do **not** subtract 2–3 days of steps.
8. Both miss → **draw**. Everyone submits early → **finalize now**.
9. Partial mid-fight totals stay visible for honesty. They do **not** beat someone who submitted.
10. Push at **T+0** (everyone), then **T+12h**, **T+18h** (6h left), **T+23h** (1h left) for people still pending. Lock screen: no step counts, money, titles, or names.
11. Out of this slice: friend tap-to-nudge, pokes, paid nudges, daily AI status, rank-change spam.

---

## Why the homepage lies today

The server already has the right states. The phone ignores them.

| Already true | Broken |
|---|---|
| `live → awaiting_final_sync → final` (`web/lib/scoring/fight-clock.ts`) | iOS `mapFight` sets `.finished` when `ends < Date()`, even if `state == awaiting_final_sync` (`FitFight/AppModel.swift`) |
| Default grace `final_sync_grace_seconds = 86400` | Finished row: `rank == 1` → **W** (`FitFight/FightsListView.swift`) |
| `final_steps_complete` on each member, already in the snapshot | Detail page always uses `FFVSBlock` for two people |
| Standings already say “Waiting for final steps · …” | That copy is last-sync age, not “time left to submit” |
| Daily Vercel cron `0 3 * * *` + app-open closer | Cron is too coarse for 12h / 6h / 1h pushes. A fight can stay `live` after `ends_at` until someone opens or the next 03:00 UTC |

“Syncing final steps” already exists on the `.live` branch and is **dead code** once the clock ends.

---

## Words (EN / FR)

Do not localize the glyphs **P / W / L**.

| Surface | EN | FR |
|---|---|---|
| List glyph (not `final`) | **P** | **P** |
| List subtitle | Pending · Ended {date} | En attente · Terminé le {date} |
| You submitted, ahead | Tentative lead | En tête provisoire |
| You submitted, behind | Tentative loss | Retard provisoire |
| You have not submitted | Pending — open the app | À synchroniser — ouvrez l’app |
| Ranking pill, not submitted | Pending | À synchroniser |
| Ranking pill, submitted | Synced | À jour |
| Ranking caption (keep) | Waiting for final steps · {freshness} | En attente des pas finaux · {freshness} |
| After `final`, you won / lost | You won / You lost | Vous avez gagné / Vous avez perdu |
| After `final`, both forfeited | Draw | Égalité |
| After `final`, they didn’t submit | Did not sync · forfeited | Pas synchronisé · forfait |

Reuse existing keys where they already match (`health.waiting-final-steps-at`, `fight.ended-on`). Stop using **Won by** until `final`.

Gold = progress toward a locked result. Moss = you / tentative lead. Ember = urgency / tentative loss / you still need to open.

---

## Homepage

Keep the **Finished** section. Marc asked for **P** there, not a new tab.

| Fight | Glyph | Subtitle |
|---|---|---|
| `awaiting_final_sync`, or `live` past `ends_at` before the closer ticks | **P** (gold) | Pending · Ended {date} |
| `final`, you rank 1 | **W** | Ended {date} · 1st of N |
| `final`, you do not rank 1 | **L** | Ended {date} · Nth of N |
| You deferred (next round) | **–** | Ended {date} (unchanged) |

Add `FFResult.pending = "P"` next to W / L / – in `FitFight/DesignSystem/Components.swift`.

Add `FightStatus.pending`. Remove `ends < Date()` as a shortcut to `.finished`.

---

## Fight page (settlement)

Hide `FFVSBlock` while pending. Order:

1. **Hero** — tentative result, not “You won”
2. **Pace chart** — reuse `FightDayChartsView`, default Pace, picker can stay
3. **Ranking** — unsynced accepted people first
4. Action / Share as today
5. Leave stays off (already gated on `.live`)

### Hero (2-person, Marc’s screenshot)

Marc 81.5k submitted, Samuel 66k not submitted:

- Tag: **Pending**
- Title: **Tentative lead**
- Body: last-known gap, “Samuel hasn’t synced final steps”, gold pill for grace left
- Never “You won”

If **you** are the one who hasn’t submitted: ember notice **Open FitFight to lock your steps** + title **Pending — open the app**.

After `final`: snap to locked You won / You lost / Draw. Restore VS for two people if we want it; drop all tentative words.

### Ranking sort while pending

1. Accepted, `final_steps_complete == false` — top, rank `—`, gold **Pending**, dimmed avatar, last-known score still shown
2. Accepted, submitted — tentative 1…n by score
3. Invited / deferred — bottom, existing pills (not the same as sync-pending)

After `final`, normal score order. Forfeited people stay on the list at the bottom with forfeit copy. Do not invent 0 steps as their displayed total; keep the last verified number and mark forfeit.

---

## Forfeit (server)

Today, grace expiry **keeps the last partial score**. That is why a mid-fight 42 can still “win.” Marc overrode that.

At `final`:

- **Complete** members: rank among themselves by steps.
- **Incomplete** accepted members: **lose**. Rank below every complete member.
- One complete + one incomplete → complete wins, even if the incomplete person’s mid-fight total was higher.
- Both incomplete → draw.
- 3+: same two-tier rule.
- `final_value` = last verified snapshot (audit). Rank / outcome carry the forfeit.
- Do **not** set `disqualified` (enum exists, unused; means cheating, not “didn’t open the app”).
- Invited and deferred people are not in the scoring set (already true).
- Withdrawn people stay out.

**Who is scored:** `fight_members.state = 'accepted'` only. Same as `recalculateFight` today.

**Clock stays:** `nextFightState` does not change. Only scoring at the `final` write changes.

**Recurring (already shipped):** next round mints at `ends_at`, not at `final`. Previous round can still be pending while the next one is live. Leave that.

**1h / 6h test fights:** still 24h grace unless Marc later asks to shrink it.

**Join during grace:** code/link join is already blocked. Leave is still allowed. Do not add late joiners to a closing fight.

---

## Notifications (summary)

Full design: [`apns-remote-push-plan.md`](apns-remote-push-plan.md).

| When | Who | Lock-screen idea |
|---|---|---|
| T+0 (`ends_at`) | Every accepted member | Fight ended. Open FitFight. Pending people: sync your steps. |
| T+12h | Still pending | 12 hours left. Open FitFight or you lose. |
| T+18h | Still pending | 6 hours left. Open or you lose. |
| T+23h | Still pending | Last hour. Open or you lose. |
| T+24h | Everyone | Result is in. Open FitFight. No W/L/steps on the lock screen. |

Skip a grace reminder if that person already submitted. Cancel leftover reminders when the fight finals early.

The phone cannot own this timer. Daily Vercel cron cannot hit these slots. Need a **15-minute** worker (Supabase Cron → existing protected Next.js route). Keep the 03:00 UTC closer as backup.

No `.p8` in git or chat. TestFlight tokens are **production APNs** even on the staging backend.

UI + forfeit do **not** wait on Apple keys.

---

## Schema

**Zero migration for the honest UI.** Snapshot already sends `state` and `final_steps_complete`.

**No new column required for forfeit.** Completeness + rank at `final` is enough.

**Optional additive read (no DDL):** `grace_ends_at = ends_at + final_sync_grace_seconds` on the fight snapshot so the phone can count down grace instead of hardcoding 24h.

**Migration only when starting pushes:** private `device_installations`, `notification_intents` / outbox, delivery log. No client grants. Encrypt tokens at rest. Cascade on account delete. See the APNs plan.

---

## Tomorrow — implement in this order

Feature-branch and `develop` pushes **do not** upload TestFlight. Staging TestFlight only after Marc merges **`develop` → `preview`**. Simulator compile still runs on the PR.

### Slice A — honest pending UI (try this first)

iOS only. No SQL. No secrets.

- `FightStatus.pending`, `FFResult.pending`
- Fix `mapFight` (`ends < Date()` must not mean finished)
- Finished row **P**
- Settlement hero + Pace + pending-first ranking
- EN/FR strings, `Changelog.swift` `1.0.0` row

PR → `develop`. Ask Marc to merge `develop` → `preview`. Then TestFlight → Update.

### Slice B — forfeit scoring

`recalculateFight` + `scoreFight` (or a wrapper). Rewrite `security.integration.ts` watermark test (today expects incomplete `42` to stand). Keep `fight-clock` tests.

Backend first. Optional iOS forfeit copy on the same or next PR.

### Slice C — grace countdown

Add computed `grace_ends_at` to the snapshot. Old phones ignore unknown keys. Deploy backend before the iOS that shows the clock.

### Slice D — outbox tables + enqueue, send is a no-op

Private tables. Insert intents in the same closer transaction. Worker marks skipped until APNs secrets exist.

### Slice E — iOS permission + token register

Ask in context (first live fight or first pending fight), not at launch. `POST /api/v1/device-installations`. Add `/fights/*` to AASA and `handleOpenURL`. **Do not prompt until F can actually deliver.**

### Slice F — APNs send

After Marc creates the key and puts `APNS_*` on Vercel Preview + Production.

### Slice G — 15-minute cron

Supabase Cron → `/api/internal/close-fights` (or a renamed unified worker). Required before 12h / 6h / 1h reminders are honest.

---

## Marc-only (pushes)

UI + forfeit do not wait on this.

1. App ID `com.fitfight.mvp` → enable **Push Notifications**.
2. New key **FitFight APNs** (APNs only). Download the `.p8` once. Do not reuse the App Store Connect key or the Sign in with Apple key.
3. Vercel Preview and Production: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_TOKEN_ENCRYPTION_KEY`. Never paste the key in chat.
4. Hosted Supabase develop + prod: 15-minute cron to the worker, secret in Vault.
5. When he wants the pending UI on a phone: merge **`develop` → `preview`**. Do not Run workflow.

---

## Tests that will break (Slice B)

| File | Today | After |
|---|---|---|
| `web/lib/supabase/queries/security.integration.ts` watermark test | Incomplete `42` becomes `final_value` | That person forfeits |
| `recalculate-fight-supabase-query.test.ts` | Happy path only | Add mixed complete / forfeit |
| `score-fight.test.ts` | Values only | Forfeit ranking cases |
| `fight-clock.test.ts` | Clock only | Keep |
| HealthKit upload tests | Completeness flag | Keep |
| iOS | No AppModel unit tests | Compile + optional new `swiftc` label tests |

New cases: high partial vs low complete → complete wins; both incomplete → draw; 3-person mixed order; early final when all complete.

---

## Files (Slice A, tomorrow)

- `FitFight/AppModel.swift`
- `FitFight/FightsListView.swift`
- `FitFight/FightDetailView.swift`
- `FitFight/FightDayCharts.swift` (optional Pace default only)
- `FitFight/DesignSystem/Components.swift`
- `FitFight/Localizable.xcstrings`
- `FitFight/Changelog.swift`

No new tab. No 11th chart. No poke button.

---

## Out of scope

Friend tap-to-nudge (Notion P3). Daily AI status. Rank-change pushes. Mute UI (schema later). Silent push as the timer. Money / last-loses / other metrics. `disqualified` as the forfeit flag.
