# Product

One line: challenge friends to a private Steps fight; most steps wins, and the loser does the agreed action.

## Names (they’re different)

| What | Value |
| --- | --- |
| On-device display name | **FitFight** |
| App Store Connect listing name | **FitFight MVP** (`FitFight` / `Fitfight` was already taken) |
| SKU | `fitfight` |
| Bundle ID | `com.fitfight.mvp` |
| Team | Marc Lamy, Team ID `C92DPD8ME2` |
| Xcode target / scheme | `FitFight` |

Do not rename the bundle ID without Apple + CI updates.

## Current 1.0 scope — 9 Sep 2026

- Four tabs: **Fights**, **New**, **Feed**, **You**.
- Each fight has posts (photos, a short video, or a note) on a Feed tab next to Stats. The Feed tab swipes between Main and each fight. Tap + to compose one post, add whatever you want, tag people, and multi-select Main and/or fights. A tag does not add someone to a fight they are not in. Posts can take any emoji and nested comments.
- New accounts pick an optional photo with their username, then connect Apple Health, then allow challenge reminders.
- Every fight is **Steps × highest total**. There are no other metrics or scoring modes.
- Every fight has a code and a share link. Public fights are listed on Join; private fights are not. Exact usernames are optional. There is no friends list or friend-request flow.
- Type an optional title and an optional action the loser must do. If there is no title, the action is the fight name. There is no money or bragging-rights option.
- Choose **1 hour**, **6 hours**, or **1 day** for testing, or **3 days**, **1 week**, **2 weeks**, or **1 month**.
- Apple Health sends merged Steps aggregates needed for active fights. It may also store private energy, distance, exercise, stand, flights, and workout summaries. Those extras are not fight options yet.
- Settings keeps Privacy, Support, Bugs & requests, Versions, Sign out, and Delete account. Look is Night or Day.
- Delete account removes the full account, uploaded Steps, memberships, owned fights, and bugs or requests the User posted; a stored Sign in with Apple authorization is revoked when available.
- The old Requests tab, money, unsupported metrics, and dead settings are removed.

## v0.3 (approved design) — historical

The web kit in [`docs/design/source/`](design/source/README.md) is the look. SwiftUI ports it:

- Four tabs: **Fights**, **New**, **Requests**, **You**
- Theme = dark/light × one of ten accents (default dark + blue)
- Live fight cards carry their own leaderboard and money line
- Version label at the top; Versions under You → Settings

That was the original port, not the current product. Marketing version is now `1.0.0`; CI bumps only the **build number** for TestFlight. Do **not** bump marketing version for a TestFlight ship. See [`shipping.md`](shipping.md#versions-vs-builds-why-friends-wait).

## v0.6 (design exploration) — retired 25 Aug 2026

The Design tab and the eleven experiment layouts are gone. The app is the
approved v0.3 Fights screen plus You → Look. Source mocks stay in
[`docs/design/source/`](design/source/README.md).

Historical note (what it was):

A fifth tab, **Design**, held eleven directions for the Fights screen — `original`
plus ten experiments — rendered live side by side. Tap one and the whole app takes
its palette. The pick persists in `UserDefaults` under `ff.design`.

- One file per direction lived in `FitFight/Designs/`; `DesignVariant.swift`
  holds the enum, the palettes and the dispatcher.
- A direction owns colour and corner radius only. Type scale and spacing still come
  from `tokens.json`, so the approved system is still the base underneath.
- Every direction reads the same `AppModel`. Same fights, same names, same money.
  If a redesign needs different data, that is a product change, not a design one.
- `original` is the approved v0.3 design and the default. Only it follows You → Look;
  the other ten pin their own palette and light/dark mode.
- `ScreenshotExport` renders `design-<name>.png` for each one, so CI publishes all
  eleven on every PR.

This is an experiment shelf, not a shipped feature set. When one wins, keep it, delete
the rest and the tab with them.

Placeholder themes (Arena, Pulse, Locker, Rogue) from v0.2 are retired — the v0.6
directions named Arena and Pulse are unrelated to them.

## v0.7 (talk to the boss) — retired 30 Aug 2026

Requests has a **Talk to the boss** button. It opens a private chat with Marc,
separate from the public vote board. There is still no server, so sending a
message opens Mail to `marc@marclamy.com`. He replies from his inbox. This was
removed with the Requests tab.

## v0.8 (Apple account + HealthKit Steps)

You can **Sign in with Apple**. You shows the real `profiles` handle. You → Data sources
reads today’s Apple Health **Steps** aggregate (not a sum of every raw source) and
lists contributing apps when HealthKit names them. Empty reads say “No accessible data”.
You → Settings has **Delete account**. Fights are still fixtures. HealthKit is not
uploaded to the server yet.

## v0.9 (live Steps Fight)

Sign in, add people directly by exact username, type the loser action, choose a
1-hour, 6-hour, 1-day, 3-day, 1-week, 2-week, or 1-month duration, and start a Steps fight. Apple Health
uploads merged Steps aggregates; standings come from the database. When the days
are up, opening the app marks the fight finished. Signed out, the app is only a
welcome screen plus Sign in with Apple.

**Honest status (31 Aug 2026):** the phone creates the fixed Steps fight, uploads
Apple Health Steps, and reads standings from Supabase. Username onboarding is
required. Friends, Requests, money, and alternate metrics are not part of the app. See
[`status.md`](status.md).

## Not this project

- Hermes (a home-Mac agent) is unrelated. Ignore it.
- GoPrime / humanedger is a different app Marc tested. Not source of truth here.

## Next product work

Honest works / doesn’t / next: [`status.md`](status.md). The living list is the [Notion Product Backlog](https://app.notion.com/p/3d38907c7ecf816facdff36cb59f463e) (FitFight rows only). Sign-in, username, direct-username Steps fights, HealthKit upload, and standings work on the phone against staging Supabase. The golden guide is [`system-design.md`](system-design.md) — follow it, do not implement all of it. The current product is **Steps only**. Don’t restore retired surfaces or invent the gaps listed in [`design/source/INVENTORY.md`](design/source/INVENTORY.md).
