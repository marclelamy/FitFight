# Next Apple Health types — plan, not a build

Recorded **10 Sep 2026** after Marc asked which Health stats most people actually have, and whether “Activity” should be next. This is a product plan. Do **not** implement it until the backlog item moves up.

WHOOP, Strava, Exercise Minutes, Stand, and Workout Count stay later. Production scoring stays **Steps** until Marc moves this.

Related: [`sports-health-integrations.md`](sports-health-integrations.md), [`fight-rules.md`](../fight-rules.md), [`system-design.md`](../system-design.md) §7 and §9.

## The short answer

“Activity” is the right instinct. The type to pull is **Active Energy** (Move calories), not the Exercise or Stand rings.

Do **not** start vacuuming Health “so we have it later.” FitFight only syncs types attached to a shipped Measure. Extra types mean a new permission sheet, more privacy copy, more empty-state lies, and data we cannot score yet.

## What most people actually have

Apple does not publish a public “percent of users with this type on.” Coverage here is from how the iPhone and Watch write Health, plus what WHOOP / Garmin / Strava already export.

| What people say | HealthKit type | Who has real numbers | Fight-ready now? |
|---|---|---|---|
| Steps | `stepCount` | Almost every iPhone. The phone writes this itself. | **Already shipping.** |
| Distance | `distanceWalkingRunning` | Same sensor as Steps. Nearly everyone who has Steps. | High coverage, **low new game** — it is Steps in metres. |
| Flights | `flightsClimbed` | Most iPhones with a barometer. | Type is common; many days are **0**. Weak fight. |
| Activity / Move | `activeEnergyBurned` | Apple Watch: this **is** the red Move ring. WHOOP, Garmin, Strava, Oura write it when the user turns that Health export on. Phone-only: some estimated calories, often thin. | **Best next Measure.** Same cumulative query as Steps. |
| Exercise minutes | `appleExerciseTime` | **Watch only.** Phone-only friends show 0. | Skip. This was the old “Active Minutes” mock. |
| Stand | `appleStandHour` / `appleStandTime` | **Watch only.** | Skip. |
| Workouts | `HKWorkout` | Only people who record a session (Watch, Fitness+, Strava, …). Casual step-fighters often have few or none. | Second wave. Needs the workout rules in `fight-rules.md`. |
| Heart rate, HRV, sleep, weight | matching quantity / category types | Watch, band, or scale. | Different product. Heavier privacy. Not a first extra fight. |

The three Fitness rings (Move / Exercise / Stand) are **Watch-first**. Phone-only users do not get a fair Exercise or Stand fight. Move calories still reach more people than those two rings because wearables write Active Energy into Health even without a Watch workout.

Do **not** score fights from `HKActivitySummary`. That API is calendar-day Activity rings, not an exact Fight window. Keep the Steps pattern: Apple’s merged cumulative statistic over `starts_at` → `cutoff_at`, plus daily buckets for the chart only.

Some regions give phone-only users **Move Time** (`appleMoveTime`) instead of Move calories. If we ship Active Energy only, those people look empty. Decide that in the metric spec before coding.

## Recommendation

**Next pull: Active Energy. One new Measure. Same ingest shape as Steps.**

Why this one, not Distance or Exercise Minutes:

1. It is what people mean by Activity / Move.
2. Watch + WHOOP + Garmin + Strava + Oura already land here in Health. Direct vendor APIs stay later.
3. It is a different game from Steps (effort, not step volume). Distance is not.
4. The phone code is almost the same: another `HKStatisticsQuery` / collection query, another permission type, another unit (`kcal`).
5. Exercise Minutes and Stand would zero out friends who only have an iPhone.

Name it **Active Energy** or **Move** in the product. Do not reuse the old **Active Minutes** label unless we later mean Exercise Minutes on purpose.

## What we will not do in this wave

- Do not request ten Health types “just in case.”
- Do not store raw samples, per-source totals, routes, heart rate, or sleep.
- Do not turn on WHOOP or Strava OAuth. If those apps write Active Energy to Health, the Apple Health path already sees it.
- Do not restore the old New-screen metric picker as decoration. A second Measure is real or it stays hidden.
- Do not invent the Advanced fight-rule form.

## Plan when Marc moves this up

### 1. Lock the Measure

Write a one-page metric spec before any Swift:

- Type: `activeEnergyBurned`
- Unit: kilocalories
- Score: total over the exact Fight window (same as Steps)
- Source: Apple’s merged HealthKit aggregate, labelled **Apple Health**
- Empty / denied reads: same honesty rule as Steps — HealthKit will not tell us “permission denied”
- Phone-only and Move Time: in or out
- Manual / user-entered energy: in or out
- Privacy strings: update `NSHealthShareUsageDescription` to name Steps **and** Active Energy

Existing users who already granted Steps will see a **second** Health permission sheet. Ask only when the new Measure ships, not earlier.

### 2. Ingest like Steps

Reuse the current aggregate path. Do not invent a warehouse.

- Phone: request `stepCount` + `activeEnergyBurned` when the user connects Health
- Phone: for each active/ending Fight window, send the merged total for **that Fight’s Measure only**
- Phone: send merged daily buckets only for chart days of those fights
- Backend: same snapshot / `metric_days` seam; metric is no longer hardcoded to `steps`
- Background delivery: observe the types we actually score
- You → Apple Health: show today’s Steps and, once connected, today’s Active Energy
- Account deletion: delete the new aggregates the same way as Steps

Create stays **Steps × highest** until step 3 is ready. Collecting energy with no fight that uses it is the warehouse we are avoiding.

### 3. One new fight type

After ingest is real on two phones:

- New: **Steps** or **Active Energy**, still highest total, same durations
- A Fight locks its Measure at start. Do not mix Steps and Energy on one card
- Standings, gap, chart, finalization copy the Steps path with a different unit
- Changelog + TestFlight when people can see it

### 4. After that works

- **Workouts** (`HKWorkout`): “did you train.” Needs minimum minutes, manual workouts, overlaps. That is Workout Count.
- Exercise Minutes / Stand: only if we accept Watch-only fights
- Distance: only if someone wants a running-specific fight; it is not the next general metric
- Direct WHOOP / Strava: only for scores Health cannot see (Recovery, Strain, Readiness). Ordinary energy and workouts stay on Health

## Decision for Marc

Pick one:

1. **Active Energy next** — Watch and wearable friends get a second fight. Phone-only friends may look thin. Recommended.
2. **Stay Steps-only** until the current two-phone Steps fight is proven and App Store is closer.
3. **Distance next** — almost everyone has it, but it is the same race as Steps.

Do not pick “pull everything now.”
