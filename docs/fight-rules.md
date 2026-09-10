# Fight rules

Status: **design direction; only Most Steps is production scope**

This document defines how FitFight can support different Metrics and different ways of competing without creating a separate implementation for every combination.

## The model

Every Fight rule has three independent parts:

```ts
{
  measure: {},
  score: {},
  result: {}
}
```

- **Measure** — what activity data to use, such as Steps, distance, active minutes, or workouts.
- **Score** — how to calculate the number shown for each member, such as total, average per day, or number of days reaching a goal.
- **Result** — what that number means for winning and losing: first wins, last loses, a goal everyone can hit, a ranked band, or proportional sharing.

Score and Result stay independent. “10,000 Steps every day” vs “10,000 Steps on average” is Score plus Reach. “Only last place pays” vs “first place wins” is Result. Do not invent a new Measure for those.

Do not create a new type for every combination. There should not be separate implementations called `daily_steps`, `daily_distance`, `average_daily_steps`, and `average_daily_distance`. Add a Measure or Score operation once, then allow only the combinations that product rules have approved.

This is dynamic configuration, not an arbitrary formula language. The server owns the allowed Measure, Score, and Result values and rejects combinations whose meaning has not been defined and tested.

## Examples

### Most steps

```ts
{
  measure: { type: "steps" },
  score: { type: "total" },
  result: { type: "highest" }
}
```

The member with the greatest number of Steps during the Fight wins.

### Most days reaching 10,000 steps

```ts
{
  measure: { type: "steps" },
  score: {
    type: "days_reaching",
    value: 10_000
  },
  result: { type: "highest" }
}
```

Each Fight day with at least 10,000 Steps adds one to the member's Score. The member with the most successful days wins.

### Reach 10,000 steps every day

```ts
{
  measure: { type: "steps" },
  score: {
    type: "days_reaching",
    value: 10_000
  },
  result: {
    type: "reach",
    value: "every_day"
  }
}
```

The Score is still the number of successful days, but success requires every Fight day to be successful.

### Reach 10,000 steps on at least five days

```ts
{
  measure: { type: "steps" },
  score: {
    type: "days_reaching",
    value: 10_000
  },
  result: {
    type: "reach",
    value: 5
  }
}
```

Anyone with at least five successful Fight days succeeds.

### Highest average Steps per day

```ts
{
  measure: { type: "steps" },
  score: { type: "average_per_day" },
  result: { type: "highest" }
}
```

The Score is total Steps divided by every scheduled Fight day. The highest average wins.

### Average at least 10,000 Steps per day

```ts
{
  measure: { type: "steps" },
  score: { type: "average_per_day" },
  result: {
    type: "reach",
    value: 10_000
  }
}
```

Anyone whose final average is at least 10,000 Steps per day succeeds.

### Last one loses (Station F tournée)

```ts
{
  measure: { type: "steps" },
  score: { type: "total" },
  result: { type: "last_loses" }
}
```

Everyone still ranks by the same Score. Only last place is on the hook. The typed action is what that person does — for example paying a *tournée*, a round of drinks, on Thursday or Friday. First place is not a special prize unless a ranking zone also marks the top.

`count` marks more than one last place. `{ type: "last_loses", count: 2 }` puts the bottom two on the hook.

This is not “lowest Score wins.” Higher Steps still rank higher. Last-loses only decides who does the action.

### Top three win

```ts
{
  measure: { type: "steps" },
  score: { type: "total" },
  result: {
    type: "highest",
    count: 3
  }
}
```

`highest` without `count` is first place only, which is today's production Fight. `count` is the podium size.

### Ranking zones (league table)

```ts
{
  measure: { type: "steps" },
  score: { type: "total" },
  result: {
    type: "ranking_zones",
    zones: [
      {
        from: 1,
        to: 3,
        outcome: "win",
        label: "Podium"
      },
      {
        from: -1,
        to: -1,
        outcome: "lose",
        label: "Last one loses"
      }
    ]
  }
}
```

Use this when more than one band matters, the way a European league table colors Champions League rows at the top and relegation at the bottom. Positive `from` / `to` are ranks from the top. Negative ranks count from the bottom: `-1` is last, `-2` is second-to-last. Zones must not overlap. Ranks that are not in a zone are still competing; they have no special outcome.

`last_loses` is the same as one lose zone on `from: -1, to: -1`. `highest` with `count: 3` is the same as one win zone on `from: 1, to: 3`.

### Most valid workouts

```ts
{
  measure: {
    type: "workouts",
    minimumMinutes: 20,
    manualWorkouts: "exclude",
    mergeOverlapping: true,
    mergeIfGapUnderMinutes: 10
  },
  score: { type: "total" },
  result: { type: "highest" }
}
```

The Score is the number of workouts that satisfy the disclosed workout rules. A two-minute workout does not count. Overlapping records are deduplicated, and nearby fragments are treated as one workout.

### Most workout days

```ts
{
  measure: {
    type: "workouts",
    minimumMinutes: 20,
    manualWorkouts: "exclude",
    mergeOverlapping: true,
    mergeIfGapUnderMinutes: 10
  },
  score: {
    type: "days_reaching",
    value: 1
  },
  result: { type: "highest" }
}
```

A Fight day counts once when it contains at least one valid workout. Splitting one day into many workouts cannot increase this Score.

## The 8,000 plus 12,000 example

For a two-day Fight in which a member records 8,000 Steps and then 12,000 Steps:

| Rule | Score or result |
| --- | --- |
| Total Steps | 20,000 Steps |
| Days reaching 10,000 | One successful day |
| Reach 10,000 every day | Failed |
| Average Steps per day | 10,000 Steps per day |
| Reach a 10,000 daily average | Succeeded |

These are intentionally different games using the same underlying Steps.

## Supported combinations

Adding a Measure does not automatically authorize every Score operation. The backend keeps a reviewed compatibility list. For example:

| Measure | Plausible Score operations |
| --- | --- |
| Steps | Total, average per day, days reaching a value, longest streak reaching a value |
| Distance | Total, average per day, days reaching a value |
| Active minutes | Total, average per day, days reaching a value |
| Workouts | Total valid workouts, average per day, days reaching a count |

This avoids both extremes:

- No Metric × Score explosion in the codebase
- No user-authored formulas or undefined combinations

## Rules that apply to every combination

- A Fight locks its Measure, Score, Result, versions, values, time zone, and tie rule before competition starts.
- The UI states the rule in plain language before anyone accepts.
- Standings chrome follows the Result. Do not let the client invent a different winner or loser than the server Result.
- Every Score includes its unit: Steps, Steps per day, successful days, workouts, or another explicit unit.
- A daily average divides by every scheduled Fight day, never only days containing activity.
- Missing or unsynchronized data is not silently treated as confirmed zero activity while the Fight is live.
- One member uses one selected Data source for the Fight's Measure so duplicate provider data is not added together.
- Raw activity may appear as supporting detail but never acts as an undisclosed tie-breaker.
- Workout rules reduce casual gaming but cannot prove that someone truly exercised. Provenance and verification remain visible.
- Rules and calculations are versioned so completed Fights remain reproducible.
- `last_loses` still ranks by the Score: higher Steps stay above lower Steps. It only assigns the losing outcome to last place.
- `highest.count` and `last_loses.count` cannot exceed the accepted lineup. A five-person Fight cannot have a top-six podium.
- Ranking zones cannot overlap. Unzoned ranks are competing, not an implicit win or loss.

## Standings UI

The Result decides the standings treatment. Do not invent a separate UI-only rule object. No screen yet; this is the mapping the later design should follow.

| Result | Standings |
| --- | --- |
| `highest` (first wins; everyone competes) | Today's ranked list. Little extra chrome. Moss can mark the current first place. |
| `highest` with `count` | A band on the top N, like Ligue 1 Champions League rows: one color on the qualifying ranks, then the rest of the table. |
| `last_loses` | A labeled separator between last and second-to-last, such as “Last one loses.” Ember on the last row. The Station F tournée uses this. |
| `ranking_zones` | One band or separator per zone, using that zone's `label`. Top win bands read like European qualification rows. A bottom lose band uses the last-loses separator. |
| `reach` | Succeeded or failed per member. It is not a race table. |
| `proportional` | Share of the pot, not podium colors. |

Moss is winning / you. Ember is urgency / losing. Gold stays progress only. Do not invent a new accent family for league bands.

A two-person Fight with `highest` and a required loser action is already “first wins, last does the action.” A group Fight must say whether only last place is on the hook (`last_loses`) or the top is the story (`highest`).

## Draft Zod shape

This is an engineering sketch, not production code. It validates the object shape; the server's compatibility list performs the product-level validation of allowed combinations.

```ts
import { z } from "zod";

const measureSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("steps")
  }).strict(),

  z.object({
    type: z.literal("distance"),
    sport: z.string().min(1).optional(),
    unit: z.enum(["meters", "kilometers"])
  }).strict(),

  z.object({
    type: z.literal("active_minutes")
  }).strict(),

  z.object({
    type: z.literal("workouts"),
    minimumMinutes: z.number().int().positive(),
    manualWorkouts: z.enum(["include", "exclude"]),
    mergeOverlapping: z.boolean(),
    mergeIfGapUnderMinutes: z.number().int().nonnegative()
  }).strict()
]);

const scoreSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("total")
  }).strict(),

  z.object({
    type: z.literal("average_per_day")
  }).strict(),

  z.object({
    type: z.literal("days_reaching"),
    value: z.number().nonnegative()
  }).strict(),

  z.object({
    type: z.literal("longest_streak_reaching"),
    value: z.number().nonnegative()
  }).strict()
]);

const rankingZoneSchema = z.object({
  from: z.number().int(),
  to: z.number().int(),
  outcome: z.enum(["win", "lose", "safe"]),
  label: z.string().min(1).optional()
}).strict();

const resultSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("highest"),
    count: z.number().int().positive().optional()
  }).strict(),

  z.object({
    type: z.literal("last_loses"),
    count: z.number().int().positive().optional()
  }).strict(),

  z.object({
    type: z.literal("ranking_zones"),
    zones: z.array(rankingZoneSchema).min(1)
  }).strict(),

  z.object({
    type: z.literal("reach"),
    value: z.union([
      z.number().nonnegative(),
      z.literal("every_day")
    ])
  }).strict(),

  z.object({
    type: z.literal("proportional")
  }).strict()
]);

export const fightRuleSchema = z.object({
  version: z.literal(1),
  measure: measureSchema,
  score: scoreSchema,
  result: resultSchema
}).strict();

export type FightRule = z.infer<typeof fightRuleSchema>;
```

Some relationships need validation with Fight context rather than object shape alone. Examples: `every_day` requires a day-based Score; a five-day goal cannot exceed a three-day Fight; a Score operation must be approved for its Measure; every numeric target must use the Score's derived unit; `highest.count` and `last_loses.count` cannot exceed the lineup; ranking-zone `from` / `to` pairs must not overlap and must use the same sign (both from the top, or both from the bottom).

## Current scope

The current production Fight is equivalent to:

```ts
{
  version: 1,
  measure: { type: "steps" },
  score: { type: "total" },
  result: { type: "highest" }
}
```

Do not implement the other examples until they are moved into the backlog and approved for production. `last_loses`, `highest.count`, and `ranking_zones` are specified here so a later Advanced form or natural-language parse can fill them. They are not production scope.
