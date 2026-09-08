# Sports and health integrations for FitFight

Research date: **29 August 2026**, Google Health Apple Health write path updated **4 September 2026**. Field-level vendor notes live here. The **product collection decision** — pull vendor APIs directly because people do not enable Apple Health export; HealthKit only for Apple Watch/iPhone — is [`data-sources.md`](data-sources.md). FitFight currently still reads Apple Health steps only. Vendor behavior and terms change, so re-check the linked first-party documentation before shipping an adapter.

## Executive answer

This file is how each vendor’s API and HealthKit export actually behave. It is not the build order. Marc’s call is in [`data-sources.md`](data-sources.md): connect WHOOP, Oura, Polar, Garmin, COROS, and Strava in FitFight. Apple Health is not a substitute for those connections. It is the only path for Apple Watch and iPhone, and a fallback when a vendor has no public API (Amazfit, Nike Run Club, Peloton).

Apple Health can still normalize steps, workouts, energy, and distance **if** the person enabled that vendor’s export. HealthKit access is not automatic. A value is visible only if the vendor wrote that type, the user enabled the export, and they granted FitFight read access. HealthKit intentionally makes “permission denied” look like “no data.” [Apple authorization guide](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)

For the current shipped Steps fight, keep Apple Health merged Steps. Direct APIs are now the collection path for the sources above, not a later optional extra.

### Decision matrix

| Platform | Direct API | Useful data through the direct API | Apple Health path | FitFight decision |
| --- | --- | --- | --- | --- |
| **Apple Health / Apple Watch** | Native HealthKit, on device; no public Apple Health REST API | Standardized samples and workouts already in the user's Health store | Native source | **Only path for Watch/iPhone.** Keep Steps; add workouts next. |
| **WHOOP** | Public OAuth 2 API | Recovery, strain/cycles, HRV RMSSD, RHR, SpO2, skin temperature, sleep, workouts | Strong, but excludes Recovery, Strain, and WHOOP HRV | **Direct API.** People will not enable Health export. |
| **Garmin** | Business/enterprise program, approval required | Daily health, sleep, stress, Body Battery, body composition, detailed FIT activities | Strong for standard daily metrics and workouts; no routes | **Direct API** after Marc’s Garmin program approval. |
| **Oura** | Public OAuth 2 API; production approval after initial user limit | Readiness/activity/sleep scores, HR/HRV, SpO2, temperature, stress, workouts | Very strong for standard metrics | **Direct API.** Readiness is on the same connection. |
| **Withings** | Public OAuth 2 health-data API | Weight/body composition, BP, sleep, activity, HR, temperature, SpO2 and more | Strong for scale/body metrics | Parked this wave. |
| **Strava** | OAuth 2 activity API, but restrictive 2026 terms | Activities, routes, segments, streams such as GPS, HR, cadence, watts | Partial activity bridge | **Direct API for that athlete.** Shared Fight display needs written Strava approval. |
| **Google Health / Fitbit / Pixel Watch** | Google Health API; Fitbit Web API scheduled to shut down in September 2026 | Activity, workouts, HR/HRV, sleep, vitals, body measurements, nutrition and more | Two-way as of Google Health iOS 5.05 (3 Aug 2026) | **Parked.** Pixel is Android. |
| **Polar** | AccessLink OAuth APIs | Exercises and samples, daily activity, continuous HR, sleep, cardio load, biosensing | Good but one-way and narrower | **Direct API.** |
| **Samsung Health** | Samsung Health Data SDK, partner registration | Broad activity, body, sleep, vitals, nutrition records | Android-only; no official Apple Health bridge | **No iOS path.** |
| **ClassPass** | Merchant inventory/booking API | Venues, schedules, capacity, reservations, attendance | No official health-data integration found | **Not a health source.** |

## What Apple Health actually gives FitFight

HealthKit is an on-device typed store. It returns Swift/Objective-C objects, not a generic JSON object and not arbitrary vendor payloads. The basic hierarchy is:

```text
HKObject
├─ uuid
├─ sourceRevision        // app/source that saved it + version/product/OS
├─ device?               // reported generating hardware, may be absent
└─ metadata?             // optional writer-supplied context

HKSample : HKObject
├─ sampleType
├─ startDate
└─ endDate
```

Common concrete samples are `HKQuantitySample` for numbers, `HKCategorySample` for enum-like states such as sleep, `HKCorrelation` for related samples such as systolic + diastolic blood pressure, and `HKWorkout` for activities. Apple defines the available types and units; an app cannot invent a new HealthKit type for a proprietary readiness score. [HealthKit data types](https://developer.apple.com/documentation/healthkit/data-types), [HealthKit framework architecture](https://developer.apple.com/documentation/healthkit/about-the-healthkit-framework), [HKObject](https://developer.apple.com/documentation/healthkit/hkobject), [HKSample](https://developer.apple.com/documentation/healthkit/hksample)

### Representative object

This is a useful storage/debug representation, not Apple's wire format:

```json
{
  "uuid": "…",
  "type": "HKQuantityTypeIdentifierStepCount",
  "start": "2026-08-29T08:00:00+02:00",
  "end": "2026-08-29T08:05:00+02:00",
  "quantity": { "value": 412, "unit": "count" },
  "sourceRevision": {
    "source": {
      "name": "Garmin Connect",
      "bundleIdentifier": "com.garmin…"
    },
    "version": "…",
    "productType": "…",
    "operatingSystemVersion": "…"
  },
  "device": {
    "name": "…",
    "manufacturer": "Garmin",
    "model": "…"
  },
  "metadata": {
    "HKWasUserEntered": false
  }
}
```

`sourceRevision.source` answers “which app or direct source saved this object?” `device` separately describes reported hardware and may be `nil`. For companion-app imports the source may identify Garmin Connect or Withings while the physical watch/scale is absent. Device local identifiers are not permanent global hardware IDs. Metadata is optional and writer-supplied, so absence proves nothing. [HKSourceRevision](https://developer.apple.com/documentation/healthkit/hksourcerevision), [HKSource](https://developer.apple.com/documentation/healthkit/hksource), [HKDevice](https://developer.apple.com/documentation/healthkit/hkdevice), [HealthKit metadata keys](https://developer.apple.com/documentation/healthkit/metadata-keys)

### The important standard objects

| User concept | HealthKit representation | Correct FitFight reading pattern | Provenance |
| --- | --- | --- | --- |
| Steps | cumulative `HKQuantitySample`, `.stepCount`, unit `count` | Daily `HKStatisticsCollectionQuery` with `.cumulativeSum` | Per raw sample; use `.separateBySource` only for audit |
| Weight | discrete `HKQuantitySample`, `.bodyMass`, mass unit | Latest sorted sample or `.mostRecent` statistic | Source, optional scale device, optional user-entered metadata |
| Heart rate | discrete `HKQuantitySample`, `.heartRate`, count/time unit | Raw samples or interval average/min/max | Source/device; motion/sensor metadata may be absent |
| HRV | `HKQuantitySample`, `.heartRateVariabilitySDNN` | Raw or interval statistics | Standard is SDNN; WHOOP's RMSSD is not equivalent |
| Sleep | `HKCategorySample`, `.sleepAnalysis` | Read intervals and interpret the category value | Per interval/source; overlaps can occur |
| Workout | `HKWorkout` plus associated quantity samples | Read activity, dates, duration, statistics; query associated detail separately | Workout and associated samples each carry provenance |
| Route | separate `HKWorkoutRoute` associated to a workout | Separate permission and route query | Route object/source |
| Blood pressure | `HKCorrelation` containing systolic and diastolic quantities | Query the correlation and tolerate hidden unauthorized members | Correlation and members carry provenance |

Quantity types are either cumulative, such as steps/distance/energy, or discrete, such as weight/heart rate. That aggregation style determines valid statistics. [HKQuantitySample](https://developer.apple.com/documentation/healthkit/hkquantitysample), [quantity aggregation styles](https://developer.apple.com/documentation/healthkit/hkquantityaggregationstyle), [HKCategorySample](https://developer.apple.com/documentation/healthkit/hkcategorysample), [HKWorkout](https://developer.apple.com/documentation/healthkit/hkworkout), [HKWorkoutRoute](https://developer.apple.com/documentation/healthkit/hkworkoutroute), [HKCorrelation](https://developer.apple.com/documentation/healthkit/hkcorrelation)

For workouts, current SDK documentation deprecates legacy totals such as `totalDistance`; use `allStatistics` or `statistics(for:)`. Detailed samples do not alter stored workout totals, so never add the workout total and its associated samples together. [Workout statistics](https://developer.apple.com/documentation/healthkit/hkworkout/allstatistics), [adding samples to workouts](https://developer.apple.com/documentation/healthkit/adding-samples-to-a-workout)

### Queries, updates, and source selection

- `HKSampleQuery`: one-time raw sample/workout snapshot.
- `HKStatisticsQuery`: one aggregate.
- `HKStatisticsCollectionQuery`: fixed time buckets such as steps per day.
- `HKAnchoredObjectQuery`: incremental sync, returning additions, deletions, and a reusable anchor.
- `HKSourceQuery`: sources that have saved a given type.

[HKSampleQuery](https://developer.apple.com/documentation/healthkit/hksamplequery), [HKStatisticsCollectionQuery](https://developer.apple.com/documentation/healthkit/hkstatisticscollectionquery), [HKAnchoredObjectQuery](https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery), [HKSourceQuery](https://developer.apple.com/documentation/healthkit/hksourcequery)

For daily steps, do **not** manually sum every raw sample from every source. HealthKit statistics merge matching sources by default, respecting Apple's source-priority behavior. `.separateBySource` exposes source-specific statistics when auditing. Raw samples can overlap; `uuid` identifies the HealthKit object, not necessarily a unique real-world event copied across apps. A writer may provide sync identifier/version metadata for its own deduplication, but unrelated vendors need not share identifiers. [HKStatistics](https://developer.apple.com/documentation/healthkit/hkstatistics), [Apple source priority controls](https://support.apple.com/en-us/108779), [sync identifier](https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier)

For FitFight server ingestion, retain at least: HealthKit UUID, type, normalized value/unit or workout/category payload, start/end, source name + bundle identifier, source version/product/OS, optional device, selected metadata, and import time. The Steps implementation now retains these raw fields, deletion UUIDs, Apple source-day statistics, and sync provenance. Calculate competition totals from the intended normalized statistic, not from summing stored observations twice.

### Permissions and why sync can appear missing

Read and write authorization are separate and requested per type. The user can allow some types, deny others, change settings later, or limit history. `authorizationStatus(for:)` reports **write** status only; Apple does not reveal whether read permission was denied. A read query can therefore return no third-party samples both when access is denied and when no data exists. `getRequestStatusForAuthorization` says whether the permission sheet needs presentation, not whether read access was granted. [Apple authorization guide](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data), [authorizationStatus(for:)](https://developer.apple.com/documentation/healthkit/hkhealthstore/authorizationstatus%28for%3A%29), [HKAuthorizationRequestStatus](https://developer.apple.com/documentation/healthkit/hkauthorizationrequeststatus)

The user controls each contributing app in Health settings and can reorder or disable sources by type. Some vendor workflows are not instantaneous: Garmin, for example, sends data only after the wearable syncs to Garmin Connect and the Connect app opens successfully. [Apple compatible-app controls](https://support.apple.com/en-us/104997), [Apple source priority controls](https://support.apple.com/en-us/108779), [Garmin Apple Health behavior](https://support.garmin.com/fr-FR/?faq=lK5FPB9iPF5PXFkIpFlFPA&productID=125677&tab=)

## Core vendor findings

### WHOOP

The [WHOOP API](https://developer.whoop.com/api/) uses OAuth 2 and scopes for recovery, physiological cycles, workouts, sleep, profile, and body measurements. It exposes Recovery Score, resting heart rate, HRV RMSSD, SpO2, skin temperature, strain, HR/energy, workout zones and available GPS/distance, sleep stages/performance/efficiency, height, weight, and max HR. [WHOOP webhooks](https://developer.whoop.com/docs/developing/webhooks/) support change delivery.

WHOOP's [Apple Health integration](https://support.whoop.com/s/article/Apple-Health-Integration?language=en_US) imports workouts/routes, energy, distance, mindful minutes, weight/height, and heart rate. It exports workouts, active energy, heart rate, sleep, resting heart rate, respiratory rate, SpO2, and optional steps. It does **not** export HRV because WHOOP uses RMSSD while Apple Health's standard HRV type is SDNN; it also does not export ECG, blood pressure, or proprietary recovery activities. Direct API value: Recovery, Strain, and WHOOP's RMSSD.

### Garmin

The [Garmin Connect Developer Program](https://developer.garmin.com/gc-developer-program/) is for approved business/enterprise integrations using OAuth 2. The [Health API](https://developer.garmin.com/gc-developer-program/health-api/) provides JSON summaries such as steps, intensity minutes, sleep, calories, heart rate, stress, Pulse Ox, Body Battery, body composition, respiration, blood pressure, and enhanced beat-to-beat data after device sync. The [Activity API](https://developer.garmin.com/gc-developer-program/activity-api/) provides FIT/GPX/TCX activities; FIT can include laps, GPS, HR, power, speed, and other sensor records. [Program FAQ](https://developer.garmin.com/gc-developer-program/program-faq/)

Garmin Connect's [Apple Health integration](https://support.garmin.com/fr-FR/?faq=lK5FPB9iPF5PXFkIpFlFPA&productID=125677&tab=) writes active/resting energy, body fat, BMI, floors, selected heart rate, sleep, steps, walk/run distance, water, weight, and workouts. It is one-way Garmin → Health and does not export GPS routes. Direct API value: Body Battery/stress, richer activity detail, and routes.

### Oura

The [Oura API v2](https://cloud.ouraring.com/v2/docs) uses OAuth 2 and exposes daily activity/sleep/readiness, sleep detail, heart rate/HRV, workouts, sessions/tags, SpO2, temperature and stress; it also supports webhooks. Apps begin with a small user limit and need approval to scale. Gen3-and-newer API access requires the member to have an active membership. [Oura API support](https://support.ouraring.com/hc/en-us/articles/4415266939155-The-Oura-API)

Oura's [Apple Health integration](https://support.ouraring.com/hc/en-us/articles/360025438734-Apple-Health-Integration) exports steps, one-minute heart rate, sleep/stages, workouts/routes, active energy, height/weight, respiration, and mindful minutes; it imports a broad set of activity, body, sleep, and vital types. Direct API value: Readiness and other Oura scores, temperature/stress context, and deeper ring data.

### Withings

The [Withings Public Health Data API](https://developer.withings.com/api-reference/) uses OAuth 2 and exposes weight, height, fat/free-fat/muscle/water/bone mass, BMI-related measurements, blood pressure, pulse, temperature, SpO2, vascular metrics, VO2max, activity/workouts, high-frequency sleep, HR/HRV, and more. Authorized apps can retrieve history and use notifications; raw sensor access is contract-gated. [Available health data](https://developer.withings.com/developer-guide/v3/integration-guide/public-health-data-api/data-api/all-available-health-data/), [OAuth and history](https://developer.withings.com/developer-guide/v3/integration-guide/public-health-data-api/get-access/oauth-web-flow/)

Withings' Apple Health support lets the user choose categories. Its field-level support documentation lists sleep, steps, distance, calories, weight/body composition, heart rate, VO2max, and blood pressure among exports, with some step/HR import. [Withings Apple Health linking](https://support.withings.com/hc/en-us/articles/203728916-Linking-my-Withings-account-to-Apple-Health), [Withings field list](https://support.withings.com/hc/de/articles/115013184128-Partner-Apps-Was-ist-Apple-Health). Direct API value: richer composition/BP/vascular/sleep history; not needed for ordinary weight.

### Strava

The [Strava API](https://developers.strava.com/docs/reference/) uses OAuth 2 and provides athletes, activities, routes, uploads, and activity streams such as time, distance, GPS, altitude, velocity, heart rate, cadence, watts, and temperature when present. Users may decline scopes; new apps start with limited athlete capacity and rate limits. [Authentication](https://developers.strava.com/docs/authentication/), [getting started](https://developers.strava.com/docs/getting-started/)

However, the 2026 [Strava API Policy](https://www.strava.com/legal/api_policy) is decisive for FitFight: §2.3 says a user's Strava data may be displayed only to that authenticated user; §6.2 allows only a seven-day cache; §§5.4–5.5 restrict aggregation/analytics and persistent storage. A shared FitFight leaderboard based on direct Strava API data is therefore not viable under the published terms without written approval from Strava. This restriction is about direct Strava API data; this report does not give a legal opinion about user-authorized HealthKit records.

Strava's [Apple Health integration](https://support.strava.com/en-us/articles/15402024-apple-health-and-strava) writes Strava-recorded route, activity type, distance, time, and calories to Health. Activities merely imported into Strava from Garmin/Zwift are not re-exported. In the other direction, Strava imports only workouts recorded by Apple's Workout app, not arbitrary third-party workouts in Health. It is not a universal bridge.

### Google Health, Fitbit, and Pixel Watch

The Fitbit app was renamed Google Health on 19 May 2026. Google's [platform overview](https://developers.google.com/health/about) says the Google Health API replaces the Fitbit Web API, whose shutdown is scheduled for September 2026. The [data-type catalog](https://developers.google.com/health/data-types) covers activity/exercise, steps, energy, distance, floors, HR/HRV, SpO2, respiration, temperature, weight/body fat, sleep, nutrition, ECG and other supported records. Access uses granular Google OAuth scopes and may require OAuth verification. [Google Health scopes](https://developers.google.com/health/scopes), [Google OAuth verification](https://support.google.com/cloud/answer/13463073?hl=en)

The current [Google Health Apple Health article](https://support.google.com/googlehealth/answer/17037331?hl=en) documents two-way sync: Google Health can read Apple Health and, as of iOS app 5.05 (3 August 2026), can write Fitbit/Pixel exercise, steps, sleep, vitals, and related types into Apple Health when the person grants write categories. [9to5Mac](https://9to5mac.com/2026/08/03/google-health-adds-two-way-apple-health-syncing-on-iphone/). Treat Fitbit/Pixel as a **HealthKit source after that export is enabled and verified on-device**. The Google Health API remains the cloud path if FitFight must sync without the iPhone opening. Do not build against the Fitbit Web API; Google turns it down in September 2026.

### Polar

Polar's [AccessLink API](https://www.polar.com/accesslink-api/) uses OAuth and provides exercises, detailed samples, daily activity, five-minute continuous HR, sleep/stages/scores, Cardio Load, SleepWise, physical information, webhooks, and supported temperature/ECG/SpO2 sensing reports. Polar also has a newer granular-scope [API v4](https://www.polar.com/polar-api-v4/), which should be evaluated before a new build.

Polar Flow's [Apple Health integration](https://support.polar.com/en/support/connecting_polar_flow_with_apple_health) is one-way Polar → Health and writes workout active energy, workout HR, resting energy, sleep timing/duration, steps, weight, and workout type/duration/distance/times/energy/average HR. It does not write continuous HR. Direct API value: exercise streams, continuous HR, cardio load, and deeper sleep/biosensing.

### Samsung Health and Health Connect

The [Samsung Health Data SDK](https://developer.samsung.com/health/data/overview.html) is an Android SDK with partner registration for distribution. It can read broad activity summaries, steps, exercise/location, heart rate, sleep, body composition/temperature, blood pressure, SpO2, glucose, nutrition, Energy Score and other supported records; write support is narrower. [Samsung data types](https://developer.samsung.com/health/data/guide/features/data-types.html), [partner process](https://developer.samsung.com/health/data/process.html). There is no official iOS/Apple Health path relevant to FitFight today.

Google [Health Connect](https://developer.android.com/health-and-fitness/health-connect/availability) is also Android-only. It is an on-device broker with per-app permissions, a large [record type catalog](https://developer.android.com/health-and-fitness/health-connect/data-types), and `DataOrigin.packageName` provenance. [Health Connect architecture](https://developer.android.com/health-and-fitness/health-connect/architecture), [data attribution](https://developer.android.com/health-and-fitness/health-connect/ui/data). It becomes relevant only if FitFight ships Android.

### ClassPass

The likely transcription was **ClassPass**. Its [developer API](https://developers.classpass.com/) exposes merchant inventory, schedules, capacity, reservations, and attendance—not consumer heart rate, steps, calories, or workout telemetry. [ClassPass API access terms](https://help.classpass.com/hc/en-us/articles/360061293531-What-is-ClassPass-s-API-Access-Terms-of-Use) limit it to booking services. No official Apple Health integration was found. It can prove a booking/attendance event, not exercise completion or intensity.

## Secondary platforms

| Platform | Direct/API position | Apple Health position | Practical conclusion |
| --- | --- | --- | --- |
| **Suunto** | [Suunto Cloud API](https://apizone.suunto.com/) uses OAuth and partner approval for workout FIT data; public pages mention workouts/daily activity, while newer webhook docs mention sleep and 24/7 activity. | No current first-party field-level support article was found. | API docs are evolving/gated; verify schemas and Health export on-device before relying on it. [Start guide](https://apizone.suunto.com/how-to-start), [webhooks](https://apizone.suunto.com/webhooks) |
| **COROS** | [Partner API application](https://support.coros.com/hc/en-us/articles/17085887816340-Submit-an-API-Application); public field schema is sparse, with workout/profile authorization. | Current [Apple Health article](https://support.coros.com/hc/en-us/articles/360041549551-Connecting-Apple-Health-with-COROS-App) lists cycling distance, HR, sleep, steps, swim distance, and walk/run distance. Other support pages conflict on workouts. | Useful as a standard Health source, but verify whether `HKWorkout` is emitted. |
| **Wahoo** | [Wahoo Cloud API](https://developers.wahooligan.com/cloud) uses OAuth/approval for profile, zones, workouts, plans, and routes. | Wahoo's iOS app supports [Apple Health activity sharing](https://support.wahoofitness.com/hc/en-us/articles/14467471126802-Authorized-Apps-Wahoo-app); product-specific behavior differs, and exact fields are not documented. | Prefer HealthKit for workouts; verify per Wahoo product/app. |
| **Peloton** | No public consumer workout API was located; do not build against private endpoints. | Peloton documents [Apple Health read/write connectivity](https://www.onepeloton.com/blog/wearables-integration), but not a field-level schema. | Accept normalized workouts through Health and validate fields; no direct integration. |
| **Zwift** | No documented public user API; activity FIT files can be exported. | Its official [third-party platform list](https://support.zwift.com/de/zwift-and-third-party-platforms-SypU0LdVr) does not list Apple Health. Strava cannot reliably re-export imported Zwift activities to Health. | No dependable direct or HealthKit ingestion path; user file import would be a separate feature. |
| **MyFitnessPal** | Its [API site](https://myfitnesspalapi.com/) says it is not accepting API access requests. | [Apple Health sync](https://support.myfitnesspal.com/hc/en-us/articles/360032271092-Apple-Health-connection-and-syncing) writes meal summaries/most nutrients and weight, and imports same-day exercise/sleep; historical import is limited. | Potential nutrition/weight Health source, not a new direct integration. |

## Recommended FitFight architecture

Build order and which sources are in: [`data-sources.md`](data-sources.md). Technical rules that still apply:

1. **Apple Watch / iPhone stay HealthKit.** There is no Apple cloud API. Request only the types attached to a shipped collection slice. Steps fights still use Apple's merged cumulative statistic over each exact Fight window.
2. **Vendor clouds are first-class connections**, not a HealthKit fallback. People will not enable WHOOP/Oura/Garmin export.
3. **One selected Data source per member per Metric per Fight.** Do not add a WHOOP workout to its Strava copy.
4. **Show sync health honestly.** Never say “permission denied” from an empty HealthKit read.
5. **Strava is in.** Connect it. Fight standings from Strava wait on an email to `developers@strava.com`.
6. **Do not scrape** Nike, Peloton, or Amazfit. No public API.
7. **Android / Health Connect / Pixel** are out until there is an Android app.

## FitFight-specific gap today

The current Steps implementation keeps only Apple's merged cumulative total for each exact Fight window and the relevant merged daily chart buckets. It does not collect raw samples, deletion tombstones, per-source statistics, or provenance. Before adding any new metric, the product and backend still need to define its unit, aggregation window, source-merging rule, late-update/deletion behavior, user-facing permission state, and anti-cheat expectations. The source inventory and the vendor-API collection decision now live on the backlog via [`data-sources.md`](data-sources.md). This report still does not implement WHOOP, Strava, Workout Count, or Active Minutes.

## Primary-source index

- Apple: [HealthKit](https://developer.apple.com/documentation/healthkit), [data types](https://developer.apple.com/documentation/healthkit/data-types), [authorization](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data), [source controls](https://support.apple.com/en-us/108779)
- WHOOP: [API](https://developer.whoop.com/api/), [Apple Health](https://support.whoop.com/s/article/Apple-Health-Integration?language=en_US)
- Garmin: [Developer Program](https://developer.garmin.com/gc-developer-program/), [Health API](https://developer.garmin.com/gc-developer-program/health-api/), [Activity API](https://developer.garmin.com/gc-developer-program/activity-api/), [Apple Health](https://support.garmin.com/fr-FR/?faq=lK5FPB9iPF5PXFkIpFlFPA&productID=125677&tab=)
- Oura: [API v2](https://cloud.ouraring.com/v2/docs), [Apple Health](https://support.ouraring.com/hc/en-us/articles/360025438734-Apple-Health-Integration)
- Withings: [API](https://developer.withings.com/api-reference/), [Apple Health](https://support.withings.com/hc/en-us/articles/203728916-Linking-my-Withings-account-to-Apple-Health)
- Strava: [API](https://developers.strava.com/docs/reference/), [2026 API Policy](https://www.strava.com/legal/api_policy), [Apple Health](https://support.strava.com/en-us/articles/15402024-apple-health-and-strava)
- Google: [Google Health API](https://developers.google.com/health/about), [data types](https://developers.google.com/health/data-types), [Apple Health](https://support.google.com/googlehealth/answer/17037331?hl=en)
- Polar: [AccessLink](https://www.polar.com/accesslink-api/), [API v4](https://www.polar.com/polar-api-v4/), [Apple Health](https://support.polar.com/en/support/connecting_polar_flow_with_apple_health)
- Samsung/Android: [Samsung Health Data SDK](https://developer.samsung.com/health/data/overview.html), [Health Connect](https://developer.android.com/health-and-fitness/health-connect/availability)
- ClassPass: [Developer API](https://developers.classpass.com/), [API terms](https://help.classpass.com/hc/en-us/articles/360061293531-What-is-ClassPass-s-API-Access-Terms-of-Use)
