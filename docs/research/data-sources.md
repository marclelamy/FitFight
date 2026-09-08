# Data sources FitFight can collect

Catalog date: **4 September 2026**. Product decision: **pull from vendor APIs directly**, because most people never turn on Apple Health export. Apple Health remains the only path for Apple Watch and iPhone. This is still collection-only: private to the signed-in User, not Fight scoring. Field-level vendor notes: [`sports-health-integrations.md`](sports-health-integrations.md).

## Why not “just Apple Health”

Those watches and apps *can* write into Apple Health. Most people do not flip that switch. FitFight will not see their WHOOP, Oura, Polar, COROS, Garmin, or Strava data unless they connect that account in FitFight.

Apple Watch and the iPhone have **no cloud API**. HealthKit is the only legal way to read them.

## Wanted sources

| Source | How FitFight pulls it | What we get | Gate before coding |
| --- | --- | --- | --- |
| **Apple Watch / iPhone** | HealthKit on the phone. No REST API exists. | Steps (already), workouts, duration, distance, energy, sport type | Expand HealthKit types + consent copy |
| **WHOOP** | Public OAuth 2 API + webhooks | Workouts, sleep, Recovery, Strain, RMSSD, HR | WHOOP app approval; written OK to show derived scores to Fight members |
| **Oura** | Public OAuth 2 API | Workouts, sleep, Readiness, HR, activity | Production user-cap approval; active Oura membership for Gen3+ |
| **Polar** | AccessLink / API v4 OAuth | Exercises, daily activity, HR, sleep, cardio load | Register an AccessLink app |
| **COROS** | Partner OAuth API | Workouts, HR, sleep, distance | Marc: apply at [COROS API](https://support.coros.com/hc/en-us/articles/17085887816340-Submit-an-API-Application) / `api@coros.com` |
| **Garmin** | Garmin Connect Health + Activity APIs | Steps, workouts, Body Battery, stress, FIT detail | Marc: apply to the [Garmin Connect Developer Program](https://developer.garmin.com/gc-developer-program/) |
| **Strava** | Public OAuth 2 API + webhooks. **We connect it.** | Activities the athlete recorded in Strava | Marc: create the API app. Email `developers@strava.com` with the exact private-Fight UX (named friends, they all opted in, derived total only). Until they write yes, show Strava only to that person. Their 2026 policy also limits cache to 7 days, so a finished Fight cannot keep a permanent Strava-API copy unless they approve it |
| **Amazfit / Zepp** | **No public developer API.** Zepp OS OAuth is for watch apps, not pulling a user’s cloud history. | — | Apple Health export if they enable it. Do not reverse-engineer Huami. Ask Zepp for a partner API or drop this source |
| **Nike Run Club** | **No public consumer API.** Internal Nike endpoints are not a FitFight integration. | — | Apple Health workout if they enable NRC → Health. Do not scrape |
| **Peloton** | **No public API.** Community scrapers exist; we will not use them. | — | Apple Health workout if they enable Peloton → Health |

Parked this wave: **Fitbit / Pixel / Google Health** (Pixel is Android; Fitbit cloud would be the Google Health API, not this iPhone list), Samsung, Health Connect, Suunto, Wahoo, Zwift.

## First collection slice

Still **private**. Still **not** a Fight score. One Data source per member later; never add WHOOP + Strava + Watch for the same run.

1. Keep shipping Steps from Apple Health.
2. Add Connect on You for **WHOOP** and **Oura** first (public APIs, workouts plus Recovery/Readiness on the same connection).
3. Expand Apple Health to private `HKWorkout` + duration / distance / energy so Watch/iPhone sports exist in the same store.
4. Polar next (public AccessLink). Then Garmin and COROS once Marc has credentials.
5. **Strava:** connect it. That person sees their own activities. Email Strava for Fight standings. Many people record on Watch/Garmin and only *share* to Strava — those Fights can use Watch/Garmin without waiting.
6. Amazfit, Nike Run Club, Peloton: HealthKit fallback only unless a partner API appears.

Normalize into one activity/observation shape at ingest. Vendor sport strings map into Apple’s `HKWorkoutActivityType` (running, cycling, swimming, strength, yoga, hiking, … ~80 types) plus `other`. Do not invent a second sport list.

## What Marc has to do (cannot be done from the cloud)

- WHOOP: create the developer app, wait for approval, confirm Fight-member display.
- Oura: create the app, apply to raise the user cap.
- Polar: AccessLink client.
- Garmin: Connect Developer Program.
- COROS: API application.
- Strava: create the API app now. Email `developers@strava.com` with the private-Fight UX. We still build the connection.
- Amazfit / Nike / Peloton: there is nothing to apply to today.

Secrets stay in Vercel/GitHub, never in git or iOS.

## Strava — paths that stay inside their rules

Do not hide numbers, score in secret, or keep a 7-day Fight as a way around the policy. Processing two people’s Strava totals for a Fight is still their API used as a challenge product.

What **does** keep both FitFight and Strava inside the published rules:

| Path | What the person sees | Fight? | Notes |
| --- | --- | --- | --- |
| **1. Fight from the watch / Garmin / WHOOP / Oura** | Standings as today | Yes | Most “Strava people” recorded on a device. Strava is the post, not the source. Ship this. |
| **2. Connect Strava, You only** | Only *your* activities | No Strava score on someone else’s card | Build this. 7-day cache, delete on disconnect. |
| **3. Email Strava** | Private Fight, named friends, derived total, no map | Only after they write yes | Send `developers@strava.com` that UX. Allowlist exists (§3.2). Do not ship Fight scoring on a hope. |
| **4. User gives us the file** | Same as other uploads | Yes, as *user-provided* activity | They use Strava’s bulk export / GPX and upload to FitFight. GDPR portability. Ugly. Not the API. |
| **5. Photo / “I did this”** | Honor-system proof on the Fight | Yes, labeled unverified | Fits later social; not a sensor source. |
| **6. HealthKit copy** | Workout Strava already wrote into Apple Health, if they enabled it | Only as Apple Health, not labeled as Strava API | Different pipe. Not a legal opinion. Do not fetch the API to fill gaps. |

Not a path: opaque backend comparison, “trust us,” week-long then delete, or reading §6.1 (apps under 10k athletes) as permission to show other people’s Strava data. §2.3 has no such exception.

## Honest limits

- Connecting WHOOP in FitFight does not also give us Apple Watch. Two sources, two connections, one selected source per Fight.
- HealthKit still looks empty when the person denied read or never wrote that type.
- Garmin Connect often needs the companion app opened before *HealthKit* updates. The Garmin **API** does not have that problem.
- Empty Nike/Peloton/Amazfit in FitFight is expected until they enable Apple Health or a partner API exists.
