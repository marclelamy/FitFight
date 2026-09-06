import { z } from "zod";

export const healthKitBackgroundRefreshStatusValues = [
  "available",
  "denied",
  "restricted",
] as const;
export const healthKitDeliveryRegistrationStatusValues = ["enabled", "unavailable"] as const;
export const healthKitSyncTriggerValues = ["observer", "foreground", "manual"] as const;
export const healthKitSyncErrorCodeValues = [
  "authentication_unavailable",
  "network_unavailable",
  "protected_data_unavailable",
  "attempt_expired",
  "healthkit_unavailable",
  "background_delivery_unavailable",
  "sync_failed",
] as const;
export const healthKitSyncOutcomeValues = ["succeeded", "failed", "cancelled"] as const;
export const healthKitSyncStageValues = [
  "authorization",
  "today_total",
  "session",
  "context",
  "healthkit_daily",
  "healthkit_fight",
  "upload",
  "fights_refresh",
] as const;

const optionalDateTimeSchema = z.string().datetime({ offset: true }).nullable().default(null);
const elapsedMillisecondsSchema = z.number().finite().min(0).max(604_800_000);

export const healthKitServerTimingSchema = z.object({
  auth_ms: elapsedMillisecondsSchema.optional(),
  db_ms: elapsedMillisecondsSchema.optional(),
  maintenance_ms: elapsedMillisecondsSchema.optional(),
  total_ms: elapsedMillisecondsSchema.optional(),
}).strict();

export const healthKitSyncStageSchema = z.object({
  stage: z.enum(healthKitSyncStageValues),
  started_ms: elapsedMillisecondsSchema,
  duration_ms: elapsedMillisecondsSchema,
  outcome: z.enum(healthKitSyncOutcomeValues),
  server_timing: healthKitServerTimingSchema.optional(),
}).strict();

export const healthKitSyncAttemptSchema = z.object({
  attempt_id: z.string().uuid(),
  trigger: z.enum(healthKitSyncTriggerValues),
  started_at: z.string().datetime({ offset: true }),
  outcome: z.enum(healthKitSyncOutcomeValues),
  error_code: z.enum(healthKitSyncErrorCodeValues).nullable().optional(),
  total_ms: elapsedMillisecondsSchema,
  stages: z.array(healthKitSyncStageSchema).max(256),
  fight_count: z.number().int().min(0).max(100).optional(),
  day_count: z.number().int().min(0).max(400).optional(),
  payload_bytes: z.number().int().min(0).max(1_000_000).optional(),
}).strict();

export const healthKitDiagnosticSnapshotSchema = z.object({
  background_refresh_status: z.enum(healthKitBackgroundRefreshStatusValues),
  delivery_registration_status: z.enum(healthKitDeliveryRegistrationStatusValues),
  last_observer_wake: optionalDateTimeSchema,
  last_sync_attempt: optionalDateTimeSchema,
  last_automatic_sync: optionalDateTimeSchema,
  last_manual_sync: optionalDateTimeSchema,
  last_trigger_context: z.enum(healthKitSyncTriggerValues).nullable().default(null),
  error_code: z.enum(healthKitSyncErrorCodeValues).nullable().default(null),
  app_version: z.string().min(1).max(40),
  app_build: z.string().min(1).max(40),
  attempts: z.array(healthKitSyncAttemptSchema).max(10).optional(),
}).strict();

export const healthKitDiagnosticSnapshotResponseSchema = z.object({
  updated_at: z.string().datetime({ offset: true }),
}).strict();

export type HealthKitDiagnosticSnapshot = z.infer<typeof healthKitDiagnosticSnapshotSchema>;
export type HealthKitServerTiming = z.infer<typeof healthKitServerTimingSchema>;
export type HealthKitSyncStage = z.infer<typeof healthKitSyncStageSchema>;
export type HealthKitSyncAttempt = z.infer<typeof healthKitSyncAttemptSchema>;
export type HealthKitDiagnosticSnapshotResponse = z.infer<
  typeof healthKitDiagnosticSnapshotResponseSchema
>;
