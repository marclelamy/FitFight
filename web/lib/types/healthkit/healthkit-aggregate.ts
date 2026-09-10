import { z } from "zod";
import { civilDayBounds, isCivilDay } from "@/lib/scoring/civil-day";
import {
  MAX_ACTIVITY_DAYS,
  MAX_ACTIVITY_LOOKBACK_MS,
  MAX_WORKOUTS,
  healthKitActivityDaySchema,
  healthKitWorkoutSchema,
} from "@/lib/types/healthkit/healthkit-activity";

const MAX_MERGED_DAYS = 400;
const MAX_FIGHT_AGGREGATES = 100;
const MAX_STEP_COUNT = 2_147_483_647;

const uuidV4Schema = z.string().uuid().refine(
  (value) => value[14] === "4" && ["8", "9", "a", "b"].includes(value[19]?.toLowerCase()),
  "must be a UUID v4",
).transform((value) => value.toLowerCase());
const dateTimeSchema = z.string().datetime({ offset: true });
const civilDaySchema = z.string().refine(isCivilDay, "must be YYYY-MM-DD");
const timeZoneSchema = z.string().min(1).max(100).refine((value) => {
  try {
    Intl.DateTimeFormat("en-US", { timeZone: value }).format();
    return true;
  } catch {
    return false;
  }
}, "invalid time zone");
const stepCountSchema = z.number().int().min(0).max(MAX_STEP_COUNT);

const healthKitMergedDaySchema = z.object({
  day: civilDaySchema,
  starts_at: dateTimeSchema,
  ends_at: dateTimeSchema,
  steps: stepCountSchema,
}).strict().superRefine((value, context) => {
  if (Date.parse(value.ends_at) <= Date.parse(value.starts_at)) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      message: "ends_at must follow starts_at",
      path: ["ends_at"],
    });
  }
});

const healthKitFightAggregateSchema = z.object({
  fight_id: uuidV4Schema,
  starts_at: dateTimeSchema,
  ends_at: dateTimeSchema,
  cutoff_at: dateTimeSchema,
  steps: stepCountSchema,
}).strict().superRefine((value, context) => {
  const startsAt = Date.parse(value.starts_at);
  const endsAt = Date.parse(value.ends_at);
  const cutoffAt = Date.parse(value.cutoff_at);
  if (endsAt <= startsAt) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      message: "ends_at must follow starts_at",
      path: ["ends_at"],
    });
  }
  if (cutoffAt <= startsAt || cutoffAt > endsAt) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      message: "cutoff_at is outside the Fight window",
      path: ["cutoff_at"],
    });
  }
});

export const healthKitAggregateSyncSchema = z.object({
  complete_through: dateTimeSchema,
  time_zone: timeZoneSchema,
  merged_days: z.array(healthKitMergedDaySchema).max(MAX_MERGED_DAYS),
  fight_aggregates: z.array(healthKitFightAggregateSchema).max(MAX_FIGHT_AGGREGATES),
  activity_days: z.array(healthKitActivityDaySchema).max(MAX_ACTIVITY_DAYS).optional(),
  workouts: z.array(healthKitWorkoutSchema).max(MAX_WORKOUTS).optional(),
}).strict().superRefine((value, context) => {
  const completeThrough = Date.parse(value.complete_through);
  const mergedDays = new Set<string>();
  value.merged_days.forEach((day, index) => {
    if (!isCivilDay(day.day)) {
      return;
    }
    const bounds = civilDayBounds(day.day, value.time_zone);
    if (mergedDays.has(day.day)) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "duplicate merged day",
        path: ["merged_days", index, "day"],
      });
    }
    mergedDays.add(day.day);
    if (Date.parse(day.ends_at) > completeThrough) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "ends_at exceeds complete_through",
        path: ["merged_days", index, "ends_at"],
      });
    }
    if (Date.parse(day.starts_at) !== bounds.startsAt.getTime()) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "starts_at must equal the civil-day start",
        path: ["merged_days", index, "starts_at"],
      });
    }
    if (Date.parse(day.ends_at) !== Math.min(bounds.endsAt.getTime(), completeThrough)) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "ends_at must equal the effective civil-day end",
        path: ["merged_days", index, "ends_at"],
      });
    }
  });
  const fightIds = new Set<string>();
  value.fight_aggregates.forEach((aggregate, index) => {
    if (fightIds.has(aggregate.fight_id)) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "duplicate Fight aggregate",
        path: ["fight_aggregates", index, "fight_id"],
      });
    }
    fightIds.add(aggregate.fight_id);
    const expectedCutoff = Math.min(completeThrough, Date.parse(aggregate.ends_at));
    if (Date.parse(aggregate.cutoff_at) !== expectedCutoff) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "cutoff_at does not match complete_through",
        path: ["fight_aggregates", index, "cutoff_at"],
      });
    }
  });
  const earliestAllowed = completeThrough - MAX_ACTIVITY_LOOKBACK_MS;
  const activityKeys = new Set<string>();
  value.activity_days?.forEach((day, index) => {
    const bounds = civilDayBounds(day.day, value.time_zone);
    const key = `${day.day}:${day.metric}`;
    if (activityKeys.has(key)) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "duplicate activity day",
        path: ["activity_days", index, "metric"],
      });
    }
    activityKeys.add(key);
    if (Date.parse(day.starts_at) < earliestAllowed) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "activity day is older than the collection window",
        path: ["activity_days", index, "starts_at"],
      });
    }
    if (Date.parse(day.ends_at) > completeThrough) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "ends_at exceeds complete_through",
        path: ["activity_days", index, "ends_at"],
      });
    }
    if (Date.parse(day.starts_at) !== bounds.startsAt.getTime()) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "starts_at must equal the civil-day start",
        path: ["activity_days", index, "starts_at"],
      });
    }
    if (Date.parse(day.ends_at) !== Math.min(bounds.endsAt.getTime(), completeThrough)) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "ends_at must equal the effective civil-day end",
        path: ["activity_days", index, "ends_at"],
      });
    }
  });
  const workoutIds = new Set<string>();
  value.workouts?.forEach((workout, index) => {
    if (workoutIds.has(workout.healthkit_uuid)) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "duplicate workout",
        path: ["workouts", index, "healthkit_uuid"],
      });
    }
    workoutIds.add(workout.healthkit_uuid);
    if (Date.parse(workout.started_at) < earliestAllowed) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "workout is older than the collection window",
        path: ["workouts", index, "started_at"],
      });
    }
    if (Date.parse(workout.ended_at) > completeThrough) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "ended_at exceeds complete_through",
        path: ["workouts", index, "ended_at"],
      });
    }
  });
});

export const healthKitAggregateSyncResponseSchema = z.object({
  complete_through: dateTimeSchema,
  synced_days: z.number().int().min(0),
  synced_fights: z.number().int().min(0),
}).strict();

export type HealthKitAggregateSync = z.infer<typeof healthKitAggregateSyncSchema>;
export type HealthKitAggregateSyncResponse = z.infer<
  typeof healthKitAggregateSyncResponseSchema
>;
