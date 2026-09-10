# Pending result, 24h forfeit, final-sync pushes

Plan date: **10 September 2026**. **No application code in this document.** Implement tomorrow from this plan.

Marc’s bug: the Fights **Finished** list showed a win after the clock ended, while a friend had not synced a post-end snapshot. The challenge is over; the result is not.

Related Apple/APNs detail: [`apns-remote-push-plan.md`](apns-remote-push-plan.md).

Notion (Blend HQ → Product Backlog):

- Bug: [Finished list shows Won before everyone synced](https://app.notion.com/p/3d78907c7ecf81ab9841de8bb8cfcc4c)
- Feature: [Pending result, 24h forfeit, final-sync pushes](https://app.notion.com/p/3d78907c7ecf811e8190f2fef3953e4a)

---

## Locked tonight

| Decision | Rule |
| --- | --- |
| Completeness | A person has **submitted** only if their selected source has a snapshot with `cutoff_at === fights.ends_at`. `last_synced_at` during the live window does **not** count. |
| List glyph | **P** while anyone accepted is incomplete. **W / L** only after `state === final`. |
| Words | **Pending** = not submitted. **Tentative lead / tentative loss** = current rank among submitted data. **Won / Lost** = finalized only. |
| Fight page | Distinct pending layout: hero → one chart → ranking. Not the live ring / VS “still racing” UI. |
| Chart | Lock **Pace** (cumulative). Hide the ten-style picker on this page. |
| Ranking | Unsynced accepted people at the **top**, marked Pending. Synced people ranked under them. Invited / next-round stay at the bottom. |
| Grace | **24 hours** after `ends_at` (`final_sync_grace_seconds`, already 86400). |
| Miss the deadline | They **lose** (forfeit). Do **not** deduct 2–3 days of steps (exact-window total cannot do that cleanly). |
| Early finalize | If every accepted member submits before 24h, go `final` immediately. |
| Both miss | Draw. Do not show two winners at 0. |
| Pushes | Server only. Local iOS timers are not the clock. |
| Cadence | T+0, T+12h, T+18h (6h left), T+23h (1h left). Optional T+24h “result is final.” |
| Lock screen | No step counts, ranks-as-scores, money, or loser-action text. |
| Out of scope | Friend tap-to-nudge, pokes, paid nudges, daily AI status, rank-change spam, silent APNs as a timer. |

Deducting days was walked back: standings are one exact-window total, not a sum of chart days.

---

## Why the homepage already lies

Server already has the right states: `live → awaiting_final_sync → final`, 24h grace, `final_steps_complete`.

iOS does this in `AppModel.swift`:

```swift
} else if row.state == "final" || row.state == "cancelled" || ends < Date() {
    status = .finished
}
```

After `ends_at`, grace fights become `.finished`. The Finished row uses `FFResultGlyph` **W** when `rank == 1`. The existing “Syncing final steps” copy sits under `.live` and never runs.

A mid-fight snapshot can still leave a high `current_value` and rank 1 with `final_steps_complete == false`. That is Marc’s screenshot.

`FFResult` today is only `win` / `loss` / `draw`. Add `pending = "P"`.

---

## Forfeit vs today’s closer

Today, when grace expires:

- Exact-end snapshot → that value, `final_steps_complete = true`
- Partial snapshot (`cutoff_at < ends_at`) → **keep that value**, incomplete
- Never synced → **0**, incomplete
- Integration test: owner 42 (partial) vs peer 0 (never) → owner wins

Marc’s rule is stricter: **no exact-end snapshot at T+24h → you lose**, even if a mid-fight total looks huge.

At finalize, score incomplete accepted members as **0** (or `disqualified` and last). Keep `final_steps_complete = false`. Synced members keep their exact-end total. If every remaining scorer forfeits, outcome is a **draw**.

Update `docs/system-design.md` § Fight close and the “never replace a stale score with zero” line in the same PR as the scoring change. Disclose the rule in New / accept copy.

Do **not** accept new `accepted` scorers after `ends_at`. In-app accept during `awaiting_final_sync` currently can; that is a spec bug.

Recurring mint stays at `ends_at` (next window can go live while the previous one is pending). Pending UI and forfeit apply only to **accepted** members of the **closing** fight. Deferred / invited are not scored and do not get “you lose” pushes.

---

## Pending fight page

Trigger: `serverState == "awaiting_final_sync"` and you are not deferred.

```
Hero (tentative lead / tentative loss / you still need to sync / everyone syncing)
Pace chart (no picker)
Standings — pending accepted on top, then synced ranks, then invited / next round
Share / loser action if present
```

| You | Others | Hero |
| --- | --- | --- |
| Not submitted | anyone | No W/L. “Sync your steps to count.” |
| Submitted, ahead of submitted field | someone pending | `FFResultGlyph(.win)` + **Tentative lead** |
| Submitted, behind a submitted person | someone pending | `FFResultGlyph(.loss)` + **Tentative loss** |
| Everyone pending | — | Neutral. “Everyone still syncing.” |
| Tie among submitted | — | **Tentative tie** |
| You deferred | — | Keep today’s next-round card. |

Colours: Moss = you/winning, Ember = losing/urgency, Gold = time/grace only. Do not put Pending on Gold.

Reuse `FightDayChartsView`, `FFLeaderboardRow`, `FFResultGlyph`, `FFPill`, `formatStandingFreshness`. Do not reuse `FFVSBlock` / `FFRingCard` / `FFHeroCard` for tentative.

API already returns `final_steps_complete`. Add `final_sync_grace_seconds` or `grace_ends_at` on the fight snapshot so the hero can show remaining grace. Client can derive pending roster from members.

---

## Copy (EN / FR)

| Slot | EN | FR |
| --- | --- | --- |
| Glyph | P | P |
| A11y | Pending sync | Synchro en attente |
| List subtitle | Finalizing steps | Finalisation des pas |
| Hero, you pending | Sync your steps to count | Synchronisez vos pas pour compter |
| Hero, ahead | Tentative lead | En tête provisoire |
| Hero, behind | Tentative loss | Retard provisoire |
| Row pill | Pending | En attente |

Pushes (accepted members only; no health numbers):

| When | Who | EN | FR |
| --- | --- | --- | --- |
| T+0 | Submitted | Fight ended. Tentative result is in. Waiting on others to submit. | Combat terminé. Résultat provisoire prêt. On attend les autres. |
| T+0 | Pending | Fight ended. Open FitFight to submit, or you lose in 24 hours. | Combat terminé. Ouvre FitFight pour envoyer tes pas, sinon tu perds dans 24 heures. |
| T+12h | Pending | 12 hours left to open FitFight, or you lose. | Plus que 12 heures pour ouvrir FitFight, sinon tu perds. |
| T+18h | Pending | 6 hours left to open FitFight, or you lose. | Plus que 6 heures pour ouvrir FitFight, sinon tu perds. |
| T+23h | Pending | 1 hour left to open FitFight, or you lose. | Plus qu’une heure pour ouvrir FitFight, sinon tu perds. |
| T+24h (optional) | All accepted | Result is final. Open FitFight to see how it ended. | Résultat définitif. Ouvre FitFight pour voir le classement. |

Pending people get **one** T+0 (submit), not the “waiting on others” T+0. Cancel remaining nudges when `final_steps_complete` becomes true. If everyone submitted at T+0, skip later nudges; optional T+24 can be skipped too.

---

## Jobs and notifications

Today: Vercel cron **once daily 03:00 UTC** + open-app closer. That cannot hit T+12 / T+18 / T+23, and can finalize hours late if nobody opens the app.

**Do this:** Supabase Cron every **15 minutes** → protected `POST /api/internal/worker` (Bearer `CRON_SECRET`). The worker:

1. Runs existing `closeDueFights()` (state + recurring mint).
2. Sends due outbox rows (or no-ops until APNs secrets exist).

Keep the daily Vercel cron as a safety net until the 15-minute job is proven.

On `live → awaiting_final_sync`, insert outbox rows in the **same transaction** (`ON CONFLICT DO NOTHING`):

- `fight-ended:{fightId}:{userId}` at `ends_at`
- `sync-nudge:{fightId}:{userId}:t12` at `ends_at + 12h`
- `…:t18` at `ends_at + 18h`
- `…:t23` at `ends_at + 23h`
- optional `fight-final:{fightId}:{userId}` at `ends_at + grace`

APNs dropped must **not** block finalization. Silent push is never the timer.

Full APNs vertical slice (capability, `.p8`, token register, HTTP/2, TestFlight = **production** APNs): [`apns-remote-push-plan.md`](apns-remote-push-plan.md).

New tables belong in **`private`**. No app-facing RPCs. Encrypt device tokens. Never log tokens or the `.p8`.

---

## Tomorrow — build order

Ship UI + forfeit even if Marc has not created the APNs key yet. Pushes are a later phase in the same epic.

### Phase 1 — Honest pending UI (TestFlight, no secrets)

1. Map `awaiting_final_sync` off `.finished`. Drive list/detail from `serverState`.
2. `FFResult.pending = "P"` on Finished (or a Pending section — keep one Finished list, P instead of W/L).
3. Pending fight Stats: hero → Pace → resorted standings.
4. EN/FR strings + a11y. Changelog `1.0.0` row. Do not bump `MARKETING_VERSION`.
5. iOS fixture: `awaiting_final_sync` must not decode as a final win.

Files: `AppModel.swift`, `FightsListView.swift`, `FightDetailView.swift`, `FightDayCharts.swift`, `Components.swift`, `Localizable.xcstrings`, `Changelog.swift`, `tests/APIContractTests.swift` / new mapping test.

### Phase 2 — Forfeit at 24h

1. `recalculateFight`: at `final`, incomplete accepted members score 0 (or disqualified last).
2. All-forfeit → draw, not dual rank 1.
3. Block new `accepted` after `ends_at`.
4. Amend `system-design.md` Fight close + incomplete rule.
5. Tests: `security.integration.ts` watermark case (owner 42 must **not** beat a synced peer after grace if 42 is not an exact-end snapshot); 23h late sync still counts; 24h01 forfeits; early all-complete finalize; deferred ignored.

### Phase 3 — Snapshot + 15-minute worker

1. Return `grace_ends_at` (or `final_sync_grace_seconds`) on the fight snapshot.
2. Supabase Cron `*/15` → worker that calls `closeDueFights`.
3. Additive migration only. No `-- allow-destructive`.

### Phase 4 — Outbox (send is a no-op until secrets)

1. `private.device_installations`, `private.notification_outbox`, optional `fight_close` preference.
2. Enqueue on transition; cancel nudges on exact-end upload.
3. Worker claims due rows; without `APNS_PRIVATE_KEY` returns `{ skipped: "config" }`.
4. pgTAP: no `anon` / `authenticated` grants. Delete-account cascade.
5. Types under `web/lib/types/notifications/`. Queries under `web/lib/supabase/queries/`.

### Phase 5 — iOS register + deep link

1. Push capability. **No** `UIBackgroundModes` `remote-notification`.
2. Ask permission in context (first `awaiting_final_sync`), not at launch.
3. Register hex token every launch after allow. `POST /api/v1/device-installations`.
4. Universal Link `https://<origin>/fights/<uuid>` + AASA + thin web stub (no scores).
5. You → Settings notifications on/off. App works if denied.

### Phase 6 — APNs send (Marc first)

Needs the checklist in [`apns-remote-push-plan.md`](apns-remote-push-plan.md). TestFlight tokens use **production** APNs against the **staging** backend.

---

## Tests

Keep: `fight-clock.test.ts`, `score-fight.test.ts`, write-budget finalize test, lock/rollback security tests, mint idempotency.

Change: `security.integration.ts` grace expiry (forfeit, not “keep 42”).

Add: pending vs 23h vs 24h01 vs early complete; outbox insert once per tick; iOS mapping fixture; no real APNs in CI (mock HTTP/2).

---

## Marc-only (pushes)

Do not paste a `.p8` in chat or git.

1. Apple Developer → App ID `com.fitfight.mvp` → enable **Push Notifications**.
2. Keys → `FitFight APNs` (APNs only). Download `.p8` once. Copy Key ID.
3. Vercel Preview **and** Production: `APNS_KEY_ID`, `APNS_TEAM_ID=C92DPD8ME2`, `APNS_PRIVATE_KEY`, `APNS_TOPIC=com.fitfight.mvp`, new `APNS_TOKEN_ENCRYPTION_KEY`.
4. Do **not** reuse App Store Connect or Sign in with Apple keys.
5. After the first push-capable TestFlight: Update → allow alerts → two-phone short fight.

UI + forfeit do not wait on this.

---

## Success

- After `ends_at`, homepage shows **P**, not **W**, until every accepted member has an exact-end snapshot or 24h passes.
- Opening the fight shows tentative copy, Pace, pending people at the top of the ranking.
- Opening the app after the end uploads an exact-end snapshot when Health is allowed.
- At T+24h01 a still-pending person loses; a person who synced at T+23h is scored.
- Pushes, once secrets exist, follow the cadence and never carry step counts.
- A dropped push still finalizes the fight.
