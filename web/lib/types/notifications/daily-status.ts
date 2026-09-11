import { z } from "zod";

export const dailyStatusStandingValues = [
  "leading",
  "tied_for_lead",
  "ahead",
  "behind",
  "last",
] as const;

export const dailyStatusStandingSchema = z.enum(dailyStatusStandingValues);

export const dailyStatusPromptContextSchema = z.object({
  standing: dailyStatusStandingSchema,
  participant_count: z.number().int().positive(),
  days_remaining: z.number().int().nonnegative(),
  needs_sync: z.boolean(),
  locale: z.enum(["en", "fr"]),
}).strict();

export const dailyStatusModelResponseSchema = z.object({
  alert: z.string().min(1).max(280),
  recap: z.string().min(1).max(600),
}).strict();

export const dailyStatusRecapResponseSchema = z.object({
  recap: z.string().min(1),
  sent_at: z.string().datetime({ offset: true }),
}).strict();

export type DailyStatusStanding = z.infer<typeof dailyStatusStandingSchema>;
export type DailyStatusPromptContext = z.infer<typeof dailyStatusPromptContextSchema>;
export type DailyStatusModelResponse = z.infer<typeof dailyStatusModelResponseSchema>;
export type DailyStatusRecapResponse = z.infer<typeof dailyStatusRecapResponseSchema>;
