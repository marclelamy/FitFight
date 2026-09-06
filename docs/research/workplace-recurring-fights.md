# Recurrent fights for workplaces (Station F)

Status: **proposal for workplace / campus extras.** Joinable codes and rolling recurring windows already shipped (4 Sep 2026). Do not add Group, admin, or HR until Marc answers the five forks.

Twelve agents independently attacked object model, join codes, admin, calendar, membership, fairness, privacy, UX, architecture, abuse, competitors, and Station F GTM. This is the synthesis. It is not a screen inventory. Do not invent UI from this file.

Related: [`../backlog.md`](../backlog.md) (Replay vs Recurring), [`../system-design.md`](../system-design.md) (Fight lock, Invite, owner), [`../fight-rules.md`](../fight-rules.md) (Steps × highest only), [`apple-review-blockers-current.md`](apple-review-blockers-current.md) (UGC / 1.2).

## One line

A workplace is a **Series** with a shoutable **join code**. Each week is still a normal **Fight**. Do not turn FitFight into HR software.

## Do not build this next

Current product is a private Steps Fight: exact username, required loser action, one window. Staging still needs a real two-phone 3-day Fight before App Store.

Recurrence, codes, and campus scale sit on top of that loop. Shipping them first is a costume on an unproven 1:1 product.

**Next product work stays:** finish 1.0.0 friend Fights. Then the smallest workplace slice is **join an existing Fight without typing other people’s usernames**. Recurring Series comes after people ask for “same thing next week.”

## The model

Keep every shipped noun. Add three:

```
User
  └─ Series member ── Series ── mints ── Fight (one window)
                         │
                         ├─ Join code   (place credential, shoutable)
                         └─ optional Group  (Station F roster that can host several Series)

Fight still has: Fight members, Fight owner, Invite (named person),
                 Fight window, Stake, Score, Final result
```

| Noun | What it is | What it is not |
| --- | --- | --- |
| **Fight** | One scored window. Immutable after lock. Same as today. | The campus. The season. |
| **Series** | Recurring template: cadence, timezone, metric, default stake, roster policy. Server mints the next Fight. | A mutating Fight row that “resets Monday.” |
| **Group** | Durable roster that can host more than one Series (campus, company, class). | Required for v1. A league with divisions. A social feed. |
| **Join code** | Credential for a Series (or Group). Public on purpose. | An Invite. Invites stay hashed, person-scoped, expiring. |
| **Invite** | Named User, current law. | A Slack screenshot. A sticker. |
| **Series owner** | Organizer of the container. One person. Transfer, don’t share. | Platform Admin. FitFight staff. HR. Co-admin lattice. |
| **Fight owner** | Creator of *that* window (usually the Series owner User). | Campus admin. |

**Workplace** and **theme** are copy, not types. Station F is an example Group. “Weekly steps at the kitchen” is a Series.

**Replay ≠ Recurring.** Replay is a human cloning one finished Fight into a new independent Fight. Recurring is a Series that inevitably mints the next window. Replaying week 12 must not fork a second Station F season.

Wife weekly: Series, closed roster, Invites, no Group, no code.
Station F: Series + Join code. Add Group only when the campus hosts more than one Series.

## Answers to the original questions

### Might it need admin?

Not a product role called Admin. One **Series owner**: rename, pause, rotate code, remove from *future* windows, transfer ownership. Same data floor as any member: derived Fight scores, never HealthKit, heart rate, routes, or an HR CSV.

FitFight staff stay out of the app. Backend ops are IDs, state, audits — not “read everyone’s steps.”

If the organizer deletes their account, the Series must **not** cascade-delete like today’s owned 1:1 Fights. Transfer or orphan. History stays readable.

### Make it recurrent?

Yes, as a **calendar Series**, not “spawn a clone when the last Fight dies.”

Default for a workplace: **Monday 00:00 in the Series timezone → next Monday 00:00**. Station F = `Europe/Paris`. Civil week, not 168 hours (DST weeks are 167 or 169 hours). Half-open `[starts_at, ends_at)`. No gap. Next Fight goes `live` even if last week is still `awaiting_final_sync`. Attribute samples by timestamp, never by sync time.

Generate **current + next**, idempotent on `(series_id, period_start)`. If cron is late, do **not** slide the window to now.

Pause/skip (August at Station F) is explicit skipped weeks, zero backfill.

Live board = this window only. Series trophies = wins on **`final`** Fights only.

### Join with code?

Yes, on the **Series**, never as a weekly Fight PIN (stickers cannot be reprinted every Monday).

- 6-character Crockford code, case-insensitive, globally unique (`AB2K9Q`). Optional vanity alias (`STATIONF`) with reserved words blocked.
- Universal Link `https://fitfight.app/j/CODE` — **not** `/invite/`.
- QR encodes the URL.
- Preview (name, window, stake, member count, “your Steps and rank will be visible”) → explicit accept → then Health.
- After this Fight has started: code joins the Series for the **next** window. Do not give a hallway stranger full-window credit. That path is a cheat, and it breaks the disclosed-lineup lock.
- Username invites keep working for friend Fights. A friend Fight has **no** code unless the creator turns join-by-code on.
- Codes are public IDs (lookup). Invite tokens stay hashed. Rate-limit guesses. Cap members. Rotate after abuse (know that rotation bricks printed stickers).

## How it should feel

Station F founder sees `F-7K2Q` in Slack or a QR at Riverside.

1. Camera / Join field → Series preview.
2. Sign in with Apple if needed. Pending join survives App Store install via the designed deferred-link path, **not** the clipboard.
3. Accept membership. Health is required to **race**, not to **belong**. No Health = spectator, not a zero on the board.
4. If they arrived mid-week after start: they are in the Series; they race **next Monday**. Copy has to say that or they think the app is broken.
5. Home: one Series card — your rank, your steps, person above / below, days left. Not 200 rows. Full list is a drill-in with search.
6. Sunday → Monday: same card rolls. They do **not** retype the code. Leave is one tap and stops future windows. Current Fight row stays (`withdrawn`), so rage-quit cannot erase a loss.

Organizer create is **not** a sixth step on New Fight. New stays 1:1. Hosting a weekly Series is rare, from You: name, Monday in this timezone, share code + QR.

## Must have

Product

- Series (template) + Fight instances. Do not reset one Fight row every Monday.
- Join code on the Series. Invite remains person-shaped.
- One Series owner, transfer, pause, rotate code. Never labeled Admin.
- Opt-in once to the Series, cheap leave that stops future windows.
- Mid-week code join → next window, not full-week Health backfill.
- Steps × highest total. No new metrics.
- Loser action **required** for 1:1. **Optional** (or presets only) for a Series. A 200-person required humiliation is a bullying API.
- Cap (~80 design, ~150 hard). Waitlist into next week. Not 1000 flat names.
- Series timezone is venue time. Travelers see a translation, they do not get a second window.
- Owner/member see the same board. No organizer-only Health.

Safety (ships with codes, not after a social feed)

- Filter + report + block + published contact on handles, Series name, action text. Guideline 1.2 already applies to today’s loser action; codes make it public-ish.
- Join preview before Health share.
- Leave this window, leave Series, kick from future, freeze joins.
- No public directory of Series. The code *is* the discovery.
- No silent re-enroll after leave.

Engineering (before Series, actually)

- API owns create / invite / accept / start. Revoke authenticated `INSERT`/`UPDATE` on `fights` and `fight_members`. Recurrence cannot be correct while the phone is the timer.
- Unique `(series_id, period_start)`. Generate at `ends_at`, not at `final`.
- Same Vercel worker as the closer, hourly+, idempotent. App-open may tick *your* Series, never mint windows itself.

## Nice to have

- Vanity code (`STATIONF`) + printable poster (QR, code, store badge).
- First-24h enrollment into *this* window, remaining-days only, badged `partial` — only if Marc rejects next-Monday.
- Skip-this-week without leaving the Series.
- Series win/loss tally after several `final` weeks (not the live board).
- Named successor if the owner goes silent.
- In-app QR scan (Camera app is enough at first).
- Startup-vs-startup teams later. Same metric. Cap roster so headcount is not the sport.
- Push: week opened, batched “you were passed,” “open to sync.” Recurrence is a zombie without them, but WhatsApp can babysit a table of eight.

## Should not do

- HR / campus dashboards, “did they do enough,” CSV of employees, domain SSO as default, auto-enroll from a company directory.
- Call anyone Admin, Moderator, or Staff in the app.
- One 200-person ranked humiliation list on home. One campus crown as v1.
- Required loser action at campus scale. Money pots. Percent-of-target ranking.
- Collapse Replay into Recurring. Collapse Group into Series. Collapse Invite into a share link.
- Public Explore / map / “all workplaces.” Geo-discovery.
- Full-window credit for a QR stranger. Auto-join on first launch.
- Co-admin matrix. Live-window kick in v1 (losing organizer deletes the leader).
- New metrics, handicaps, anti-cheat ML, animal avatars, Stompers line, social feed — to “make workplace fair.”
- Official Station F partnership, QR posters, Slack blast, full French i18n, Android — before a warm iPhone table has finished one Fight.
- Weekly-expiring campus codes (bricks stickers). 4-character codes (brute force).
- Letting Series owner see more health than members.
- Waiting for the social feed to ship report/block.

## Quirks that will actually happen

Membership and time

1. Series member ≠ Fight member. Leave the Series; past Final results stay.
2. Grace overlap: last week `awaiting_final_sync`, this week already `live`. Two Fights, one live board.
3. DST in Paris: that week is not 168 hours. Monday 00:00 civil still holds.
4. Creator timezone is sticky. Moving to London later must not rewrite history.
5. New York remote still fights Paris Monday–Monday. “My Monday” is copy, not a second score.
6. Tourist scans QR, gets auto-cloned forever unless guests ≠ standing members.
7. Intern visa ends; they keep winning from another country unless membership can expire.
8. Join without Health looks like sandbagging if you seat them at 0. Don’t.
9. Two Apple IDs, one Watch. Identity for “already in this window” has to be Health-ish, not just email.
10. Owner delete today nukes owned Fights. Malpractice for a workplace Series.

Join codes

11. `STATIONF`, `Station F`, `station-f` must be the same vanity, or the hallway dies.
12. Username field vs Join field: people will paste the code into invite.
13. Slack screenshot is distribution, not an incident. Twitter screenshot is a worldwide Fight — cap and kick.
14. Rotating the code bricks the café sticker. Rotation is rare and loud.
15. Camera opens Safari if Universal Links are wrong. Test the **App Store** deferred path, not only TestFlight.
16. Do not use clipboard as the deferred-install mechanism (“FitFight pasted from Safari”).
17. Shared iPad at a demo leaves the next stranger inside Station F.
18. 201st person at the poster needs a waitlist, not a shrug.

Fairness and privacy

19. Metro vs Uber is a 5–8k daily gap you cannot grind out of a chair. Highest total is fair measurement, unfair status.
20. Watch vs iPhone-in-pocket undercounts. Trust Apple’s merge; do not market verified.
21. Phone on a dog, treadmill desk, CDG walking weeks — all “steps.” Social call-out in a pod of eight; not a campus tribunal.
22. A manager on the same named board is employment-adjacent health data. GDPR still applies to Paris users even if v1 is “US-hosted.”
23. Daily buckets let coworkers infer sick days. Workplace default should be window total + rank, not hour-by-hour.
24. Rank-only still doxxes last of four. Small Series are the product; k-anonymity is not a v1 fix, honesty is.
25. Recurring win/loss tally is a permanent athletic HR file if you show it to the company. Keep it inside the Series, never export.

Product collisions

26. Someone will New-Fight a one-shot named “Station F this week.”
27. “This week’s code” in Slack trains people to rejoin every Monday. They must not.
28. Required action “loser cooks” does not scale. Empty or preset stake for Series.
29. `declined` on one window must not mean left-the-Series.
30. At-least-one-invitee is a 1:1 fossil. A code Series starts with the owner alone.

## Five forks for Marc

These actually change the product. Everything else can follow.

1. **Mid-week scan:** next Fight only (recommended — keeps the start lock), or this Fight with remaining-days only and a `partial` badge?
2. **Standing vs guest:** is Station F a club you belong to (opt-in once, leave anytime), or a poster you enter each week?
3. **One campus Series or many table Series?** One code for Station F vs every kitchen/startup mints their own. Several hosting Series ⇒ Group now; one ⇒ Series + code, Group later.
4. **Loser action on a Series:** optional / presets only (recommended), or still required free text like 1:1?
5. **Named leaderboard:** full names inside the Series (friend energy), or rank + private personal score because coworkers + managers will join?

If (5) is “keep it like friends, managers can join, daily graph stays,” do not call it workplace. Call it friends-with-a-code.

## Phases

**0 — Ship the friend Fight.** Two phones, 3-day Steps, matching standings, cutoff. App Store when Marc says. No campus clothing.

**1 — Ops dogfood, almost no software.** 6–8 iPhone people at Marc’s table. Internal TestFlight. WhatsApp is notifications. One N-player Fight, one cheap stake (“le dernier paie les cafés”), IRL settlement. If username-in-chat fails, the only slice worth building is **join this Fight by code** (still one window, no Series).

**2 — Recurrence after they ask.** Replay first (human taps Redo). If they still want always-on: Series + server mint + durable membership. Push “open to sync” the day Marc refuses to be the hallway nag.

**3 — Campus product, after store.** Stable Series code, QR, one Slack post as proof not acquisition. Then consider Station F official. Bilingual UI. Android is a hard ceiling on “the campus app.”

Kill criterion for a cold 20-person blast: nobody opens after day 2. That test is invalid without push and a warm table. Kill on the table of ~8 instead.

## Technical sketch (not a migration)

Do not implement from this section until Phase 2 is pulled into Now.

New: `fight_series`, `fight_series_members`, `join_codes` (hashed short code + pepper, or public-id lookup for vanity). Additive on `fights`: nullable `series_id`, `period_start`, unique `(series_id, period_start)`.

Join-code redeem is `POST /api/v1/join-codes/{code}/redeem`. Do not reuse `fight_invites.token_hash` uniqueness for 6-character codes.

Scale warning: 1000 members locking one Fight row on every HealthKit POST will melt. Split snapshot upsert from rank recompute before club scale. Recurrence for “wife weekly” does not need 1000.

## What the twelve lenses agreed on

- Three objects (container / series / window), not one fat Fight.
- Code on the Series. Invite stays private.
- No HR dashboard. Owner sees what members see.
- Server clock. Phone cannot be the recurrence timer.
- Report/block must ride with codes.
- Friend energy, not Challengize / Wellhub / Virgin Pulse.
- Station F first cohort is a table, not a partnership.

## What they fought about (and the call)

| Fight | Call |
| --- | --- |
| Wednesday join this week vs next | **Next window.** Remaining-days is a later escape hatch. |
| Opt-in every week vs once | **Once, with a loud leave.** Per-window consent dies by week three. After leave, never silent re-enroll. |
| 200-person campus board vs pods of 8 | **Cap small.** One Series, not a Halle-wide crown. Pods/teams later. |
| Backfill Health from week start | **No** for code joiners. Yes only for disclosed pending Invitees (today’s 1:1 law). |
| Call the container Group vs Community | **Series** in the product. **Group** in the schema if a roster outlives one Series. Never Community/League/Admin in UI. |
| Calendar Monday vs rolling 7 days | **Civil Monday in Series TZ.** Rolling 7 days from first tap is a forever-Wednesday league. |
