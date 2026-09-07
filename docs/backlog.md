# Backlog

This is the product list. Not GitHub Issues, not Notion.

Marc talks from the phone: “put X on the backlog” or “do the next one.”
The agent edits this file, commits, opens a PR into `develop`.

| Column | Meaning |
| --- | --- |
| **Urgent** | Do before the next feature. Legal or data-integrity, not product. |
| **Semi urgent** | Product fixes to do soon. Not legal, not parked. |
| **Now** | Next work. Pick from here unless Marc says otherwise. |
| **Next** | Decided, not started. |
| **Later** | Ideas. Do not build until Marc moves them up. |
| **Ask first** | Designed gaps. Do not invent the screen. |
| **Done** | Shipped enough to leave the list. |

Do not invent UI for anything in **Ask first** or undesigned Later items.

Honest works / doesn’t / next: [`status.md`](status.md). Read that before the next build.

[`system-design.md`](system-design.md) is the golden guide. Follow it. Do not implement the whole document. Production Metric is **Steps**; Active Minutes and Workout Count stay later.

**Current scope lock (4 Sep 2026):** three tabs (**Fights**, **New**, **You**); direct exact-username invitations; Steps × highest total; an optional fight title and optional typed loser action; and 3-day, 1-week, 2-week, or 1-month durations. Do not restore friends, the old Requests tab, money, other metrics, alternate scoring, or removed settings unless Marc explicitly reopens that scope.

## Urgent

### Freeze historical results against aggregation-code changes

Changing normalization, aggregation, or scoring code must not silently rewrite previously finalized history. Persist the calculation version, input revision, calculated value, and finalized time used for each historical day and Fight result. A new code version applies prospectively unless an explicit, audited backfill is approved.

Provider corrections, deletion tombstones, and late device syncs may still update an unfinalized day during its disclosed correction window. Once finalized, that day's stored result remains immutable except through an explicit audited correction. Decide the day-finalization boundary and correction window before relying on historical totals for recommendations or completed Fights.

### Verify account deletion before App Store submission

The backend now hard-deletes the profile, username, authentication rows, Health/Steps
data, uploads, friendships, invitations, memberships, Fights the User created, and
bugs or feature requests they posted. It
removes the User from Fights owned by someone else. The phone clears its local Health
sync state. New Apple sign-ins store an encrypted revocation token; legacy accounts
without one still delete and receive the manual Apple Settings disconnect path.

Before App Store submission, configure the Sign in with Apple key and token-encryption
secret in both Vercel environments, then verify fresh sign-in and deletion on staging.

## Principle: server does the work

Most fight logic has to live on a server, not on the phone.

If the app is closed or killed, iOS will not reliably run timers, settle a month, or notice that HealthKit never uploaded. A server can: keep the fight window, send a push, settle scores once data is in.

The phone’s job is: show the UI, read Apple Health Steps when it is open (or briefly woken), and upload the required aggregates. Push notifications are not in the current scope.

**Last TestFlight:** 6 Sep 2026 — Pending next build (not uploaded): repeating fights past the start day let you join this round or wait for the next one; same-day joins still count as this round. People waiting for the next round are visible and do not count in this round’s standings. Pending next build (not uploaded): a tap anywhere on a Bugs & requests card opens it, not only the title. Pending distribution fix (not deployed): wait for Apple processing, submit each build for external beta review, enable automatic tester notification, and fail CI when external distribution fails. Last confirmed upload is 1.0.0 (153), which includes backend-based invitation decisions; build 114 still uses direct membership writes and needs updating. Marc confirmed build 153 reached Testing in Friends Beta after removing and re-adding the build on 5 Sep; friends can now update. Later uploads hit Apple’s upload limit. Pending next build (not uploaded): Create and Join on New use matching gray captions and no longer mention codes or inviting people. Apple Health failures retain the failed stage and safe system error code, emit searchable backend logs, and show an error reference under You; deploy the expanded diagnostics endpoint before the native build. One API request refreshes Fights; aggregate uploads and finalization use batched writes; valid login tokens are reused; private Apple Health timing history records reads, upload and complete refresh durations. Deploy the timing-history migration and backend before the native build. Latest prior build: Apple Health on You shows today’s real step count. Previous: Invitation decisions use authenticated backend commands. Unavailable Health data preserves saved Steps; final scores and their selected inputs freeze atomically. The paired migration closes direct client writes to fights, memberships, and sources; deploy the backend with the new Decline endpoint before applying it. Account deletion removes owned fights and the full account even when other participants remain. Previous build: Share on a fight uses the same space under the section title as Action and Standings. New fights can have a title. Title and action are both optional; if you skip a title, the action is the name on Fights. You → Settings has Bugs & requests: post a bug or a feature request, browse the board, upvote, and comment with your username. New starts with Create or Join. Joinable fights use a 4-character code and a live list (no scores on that list); share the code or link from the fight itself. Recurring fights roll into the next window when the current one ends. Leave from the fight if you do not want the next window. The Fights list titles every row with the fight name (or the action when there is no title), puts the gap on the right and the days left underneath, and keeps live fights one size. FitFight follows the iPhone’s English or French app language across the native UI, Health permissions, errors, accessibility labels, and Versions. The TestFlight update notice sits under the version line as a solid card. Apple Health background sync installs at launch, preserves one interrupted opportunity, and shows private status under You; standings show relative freshness and exact final-window completeness. Look for `1.0.0 · build N · staging`.

## Semi urgent

- **Slider for dates.** Replace or supplement the current date picker with a slider.
- **Haptic feedback on button tap.** Vibration (`retour haptique`) when buttons are tapped.
- **Nicer graph for a fight in progress.** Improve the in-progress Fight chart.
- **Data source mismatch for Dorian.** One place shows 2.2k steps for that day; another shows 0 steps. Same person, same day — they must match.

## Now

- Marc: Apple → On on the **new** develop Auth ([providers](https://supabase.com/dashboard/project/zstzbfocunthczzubggz/auth/providers)), client ID `com.fitfight.mvp`.
- Marc: add the Sign in with Apple key and a stable 32-byte token-encryption key to the staging and production Vercel environments before testing fresh sign-in or submitting.
- Marc: one Steps fight on staging. Exact username, optional title and action, Apple Health, Start **once**.
- Participants on TestFlight Internal Testing. Same build, their own Apple IDs and usernames. Start with a 3-day Steps fight.

## Next

- **Validate aggregate-only Apple Health sync on staging.** Use two phones to confirm the authenticated request sends the server-issued Fight windows, the exact-window totals drive both standings, relevant merged daily buckets drive charts only, and no raw archive or Storage object is created.
- **Watch a real 3-day fight close.** Opening the app marks a due fight finished; the daily Vercel cron is the safety net. Proof is two phones: standings match, the Fight ends, and Steps after `ends_at` do not count. Do that before App Store.
- **Smoke-test every allowed duration.** Confirm New sends 3, 7, 14, or 30 days and the detail screen shows the title or action and the correct end date.
- App Store when Marc says ship (`develop` → `main`).

## Later — outside the current product

These are parked ideas, not launch requirements. None may restore friends, the old
Requests tab, money, another metric, or alternate scoring without Marc explicitly
reopening scope.

- **LLM review for Bugs & requests.** After someone submits a bug or feature request, an LLM could check that the write-up is specific enough and reject empty or abusive language. Decide provider, API keys, prompt, cost, failure behavior, and what the person sees when a post is refused before building this. Not in v1.
- **Report and block on Bugs & requests.** The board is user-generated text. Apple will want a way to report a post and block a person. Do not invent that screen until this moves up.
- **Restore bounded full-fidelity HealthKit ingestion only when a shipped feature needs it.** The MVP deliberately keeps only Apple's merged exact Fight-window totals and the relevant merged daily chart buckets. Before restoring raw samples, deletion anchors, per-source statistics, device/source metadata, or another archive transport, define the concrete product purpose, explicit Collection consent, bounded backfill, retention and deletion policy, edit/deletion reconciliation, provenance shown to Users, and operational size limits. Never calculate Steps by naïvely summing overlapping raw samples or source totals; Apple's merged aggregate remains the reference unless a reviewed Metric specification replaces it.
- **Show the result of a Fight refresh.** Pull-to-refresh now uploads current Apple Health aggregates and reloads standings from the server, but after the native spinner ends the Fight still needs a visible up-to-date or failed state with a retry path. In participant standings, show sync freshness as relative elapsed time—minutes ago, hours ago, then days ago—instead of an absolute date and time. Do not promise that iOS background delivery is instant.
- **Advanced Fight-rule builder.** An explicitly advanced dynamic form for the full Measure × Score × Result model in [`fight-rules.md`](fight-rules.md). Earlier answers control which later fields appear: choosing workouts reveals workout-validity rules; choosing days reaching a value asks for the daily value; choosing Reach asks for the final goal. Show only reviewed compatible combinations, keep a plain-language summary visible, and validate the final object on the server. Do not make the Basic path feel like this form. No screen yet; do not build until moved up.
- **Natural-language Fight creation by text or voice.** A User types or records what they want—such as “10,000 Steps at least five days this week; everyone who does it succeeds.” Speech is transcribed when needed, then an LLM converts the request into the same validated Fight-rule object from [`fight-rules.md`](fight-rules.md) and fills the Advanced form. Ask a short follow-up when meaning is ambiguous; never invent an unsupported combination. Always show the completed form and plain-language rules for explicit confirmation before creating, inviting, or starting the Fight. Decide voice/transcript consent, retention, provider, cost, and failure behavior before implementation. No screen yet; do not build until moved up.
- **Replay and recurring fights.** When a fight ends, a Redo / Replay button starts the same challenge again; people accept the new window. Recurring is the always-on version: same fight every week (or every N days), server recreates it when the last one ends, so you do not rebuild a weekly steps fight with your wife by hand. Recurring series also get a tiny history: how many times each person has won or lost across previous windows, a ranking of this challenge over time. No extra screens yet; do not invent one.
- **End-of-window sync nudge — not now.** Later, push at the close of a period: open the app so steps / workouts can upload if they did not. After a Fight ends but before it is finalized, show a reminder button beside each participant whose final step data is missing or incomplete. Another participant can tap it to send them a FitFight notification identified as a reminder from their friend, with copy such as “Open FitFight to sync your steps.” The server sends and rate-limits these reminders; the phone cannot schedule them while killed. Do not show the incomplete standing as a final score.
- **Friend pokes (encourage / discourage).** A user writes a short line; the server sends a push to the friend. The notification is from FitFight; the words are from the friend. Apple does not ban this — every chat app does it. What they *do* require if people can send text: filter garbage, report, block, a way to reach us. Do not put health numbers or money in the lock-screen text. Rate-limit so it cannot become spam. “Discourage” is the spicy half — ship mute / block with it, or it becomes bullying and Apple *will* pull the app (guideline 1.2). Not a screen yet; do not invent one.
- **Dual challenge (one person vs the pool).** Not everyone racing the same metric. One person sets a personal goal — e.g. lose 10 kg in 2 months or 5 months, numbers from a connected scale at home. Other people put money into a pot. If they hit it, they take the pot. If they miss, still open: pot goes back to the backers, or the person pays them. Needs a weight/scale source, not only steps. Different shape from today’s “everyone on the card” fights. No screen yet; do not invent one.
- **Street stickers.** Stickers with a line like “do more sport / get fit and earn money at the same time,” plus a QR code. Marc sticks them everywhere. No design yet; do not invent one.
- **Company-sponsored credits.** Companies (example: Anthropic, OpenAI, or Blend) give credits or money to users who complete a challenge — enough sport / steps in a month, e.g. $20 of credits. Kind of philanthropy / partnership. No screen yet; do not invent one.
- **Challenge social / activity social.** The app is also a small social for friends on a fight. On a recurring bet (e.g. 45 kg dumbbell), people post progress — videos, what they did — to the challenge, both to share and to prove they made it. See what friends did, compare, encourage. Mix of Strava-style activity sharing and the bet. Fitness because people do it together.
  Also a place for accomplishments across apps and sports: one friend hikes, another bikes, they don’t share an app today so they send photos in Messages. Here they can post the activity, show the source (which provider), and share stats if they want. A friend feed even when you don’t have a fight with them. Maybe later: more than one feed (friends / fights / groups). Do not invent those tabs yet.
  Faking is fine for now. People will fake it. Figure anti-cheat later. For now: build the app, make it fun, let people share if they want. Steps Fights still come first; social is Later, not blocked on proof.
- **Stompers-style race line (not a high-score list).** Copy the feel of [Stompers](https://www.stompers.com/): animated people running on a line, not a ranked table. When you open a fight, stretch the lowest person’s score to the left of the screen and the highest to the right, then place everyone else on that min–max scale by their actual score. The line is the standing; do not make it a scoreable high-score board. Running animation is the point. No extra screens yet; do not invent one.
- **Animal avatars.** On join you pick an animal (panda / raccoon vibe). One locked artistic style as a small icon, used on You, home, everywhere. The animal can vaguely look like the person. Every 7 days regenerate the same animal from last week’s average movement / goals: more muscular if they hit it, fatter if they didn’t. When a fight starts, generate one cover of everyone’s animals fighting together. Art direction only; no screens yet; do not invent one.
- **School / university fights.** A class or a school runs a fight. Each person does their own sport. Teachers and the school do not get a feed of everything. They only need “did this person do enough.” Phone-in-class is one possible culture hook (if you want the phone, you are in the fight), not a designed screen. Same shape for universities. Wellness as part of how the school works, not a PE gradebook. Calories is a possible metric later. Production metric stays Steps for now. No screens yet; do not invent one.
- **Company yearly culture fights.** A company runs a long fight (a year, not a week) as how they work, not a sponsor pot. Different from company-sponsored credits. People still do their own sport. The company only needs “did they do enough,” not a spy dashboard. No screens yet; do not invent one.

### SEO

- **One honest comparison page after launch.** After a real two-phone Fight is validated and FitFight is publicly downloadable, publish one useful page on FitFight’s official domain, such as “Best step challenge apps for competing with friends.” Actually test the included apps; show original screenshots, evaluation criteria, strengths, drawbacks, and the date tested; disclose that FitFight publishes the comparison. Do not create exact-match domains or mass-produced AI directory pages. Measure App Store visits, installs, and activated Fights—not impressions—and add more pages only if the first one brings qualified users.

## Ask first

Nothing is authorized here for the launch. Removed friends, Requests, notification
inbox, payouts, payment, extra settings, per-person goals, and alternate Fight rules
are not missing screens; they are out of scope.

## Done

The phone writes fights and Steps to staging after this PR is merged. See [`status.md`](status.md).

- Current launch shape: Fights, New, and You; direct exact-username Steps challenges; optional fight title and optional loser action; 3/7/14/30-day durations; Privacy and Support links; essential settings only.
- Account deletion hard-deletes the account and owned Fights, removes participation elsewhere, clears local Health sync data, and supports encrypted Sign in with Apple token revocation.
- Historical v0.3 design port: four tabs, dark/light, 10 accents, fixture fights. Requests and extra accents were later removed.
- Historical Talk to the boss on Requests: private chat with Marc, emailed to him. Removed with Requests on 30 Aug 2026.
- Persistent GitHub `develop` + hosted Supabase branch `develop`.
- Sign in with Apple on You, real `profiles` handle, Apple Health Steps read on You → Data sources, Delete account under You → Settings.
- Smallest command API: create / invite / accept a Steps Fight. New adds participants by exact username and starts a real fight; fight detail Accept/Join accepts it.
- HealthKit Steps upload. Standings come from the database. Fights are no longer the fixture people.
- Fight closer: `live → awaiting_final_sync → final` on a server clock. Tests fake `now` for 1 / 3 / 7 / 14 day windows. Opening the app closes your due fights; Vercel cron closes the rest if nobody opens. No push yet.
- Welcome screen when signed out. Apple Sign In is the only way in; the tabs stay hidden until then.
- Username onboarding after sign-in. Phone-written Steps fights, HealthKit → `step_days`, standings from the database. Design tab removed.
- Approved HTML design-system port: Night/Day, Nunito, and reusable SwiftUI components. The internal showcase was removed from user settings.
