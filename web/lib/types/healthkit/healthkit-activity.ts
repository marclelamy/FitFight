import { z } from "zod";
import { isCivilDay } from "@/lib/scoring/civil-day";

export const healthKitActivityMetricValues = [
  "active_energy",
  "walking_running_distance",
  "exercise_minutes",
  "stand_minutes",
  "stand_hours",
  "flights_climbed",
  "cycling_distance",
  "swimming_distance",
  "move_time_minutes",
  "wheelchair_distance",
  "wheelchair_pushes",
  "swimming_strokes",
  "rowing_distance",
  "paddle_distance",
  "skating_distance",
  "cross_country_ski_distance",
  "downhill_snow_distance",
  "workout_count",
  "workout_time",
  "walk_run_workout_distance",
] as const;

export const healthKitActivityMetricSchema = z.enum(healthKitActivityMetricValues);

export const healthKitActivityUnitByMetric = {
  active_energy: "kcal",
  walking_running_distance: "m",
  exercise_minutes: "min",
  stand_minutes: "min",
  stand_hours: "count",
  flights_climbed: "count",
  cycling_distance: "m",
  swimming_distance: "m",
  move_time_minutes: "min",
  wheelchair_distance: "m",
  wheelchair_pushes: "count",
  swimming_strokes: "count",
  rowing_distance: "m",
  paddle_distance: "m",
  skating_distance: "m",
  cross_country_ski_distance: "m",
  downhill_snow_distance: "m",
  workout_count: "count",
  workout_time: "s",
  walk_run_workout_distance: "m",
} as const;

export const MAX_ACTIVITY_DAYS = 800;
export const MAX_WORKOUTS = 200;
export const MAX_ACTIVITY_LOOKBACK_MS = 40 * 24 * 60 * 60 * 1000;
const MAX_ACTIVITY_VALUE = 2_147_483_647;

const dateTimeSchema = z.string().datetime({ offset: true });
const activityValueSchema = z.number().finite().min(0).max(MAX_ACTIVITY_VALUE);

export const healthKitActivityDaySchema = z.object({
  day: z.string().refine(isCivilDay, "must be YYYY-MM-DD"),
  starts_at: dateTimeSchema,
  ends_at: dateTimeSchema,
  metric: healthKitActivityMetricSchema,
  value: activityValueSchema,
  unit: z.string().min(1).max(16),
}).strict().superRefine((value, context) => {
  if (Date.parse(value.ends_at) <= Date.parse(value.starts_at)) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      message: "ends_at must follow starts_at",
      path: ["ends_at"],
    });
  }
  if (value.unit !== healthKitActivityUnitByMetric[value.metric]) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      message: "unit does not match metric",
      path: ["unit"],
    });
  }
});

export const healthKitWorkoutSchema = z.object({
  healthkit_uuid: z.string().uuid().transform((value) => value.toLowerCase()),
  started_at: dateTimeSchema,
  ended_at: dateTimeSchema,
  activity_type: z.string().min(1).max(64).regex(/^[a-z0-9_]+$/),
  duration_seconds: z.number().finite().min(0).max(7 * 24 * 60 * 60),
  distance_m: activityValueSchema.nullable().optional(),
  energy_kcal: activityValueSchema.nullable().optional(),
  effort: activityValueSchema.nullable().optional(),
}).strict().superRefine((value, context) => {
  if (Date.parse(value.ended_at) <= Date.parse(value.started_at)) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      message: "ended_at must follow started_at",
      path: ["ended_at"],
    });
  }
});

export type HealthKitActivityMetric = z.infer<typeof healthKitActivityMetricSchema>;
export type HealthKitActivityDay = z.infer<typeof healthKitActivityDaySchema>;
export type HealthKitWorkout = z.infer<typeof healthKitWorkoutSchema>;
