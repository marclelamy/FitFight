import { z } from "zod";

export const requestTimingPhaseValues = ["auth", "db", "maintenance"] as const;
export const requestOperationValues = ["healthkit_context", "healthkit_upload", "fights_refresh"] as const;
export const requestTraceIdSchema = z.string().uuid();

export type RequestTraceId = z.infer<typeof requestTraceIdSchema>;
export type RequestTimingPhase = typeof requestTimingPhaseValues[number];
export type RequestOperation = typeof requestOperationValues[number];
export type RequestTiming = {
  phases: Partial<Record<RequestTimingPhase, number>>;
};
