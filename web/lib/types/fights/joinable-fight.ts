import { z } from "zod";
import { fightVisibilityValues } from "./fight-visibility";
import { fightJoinStartSchema } from "./join-start";

export const fightVisibilitySchema = z.enum(fightVisibilityValues);

export const joinableFightSummarySchema = z.object({
  fightId: z.string().uuid(),
  seriesId: z.string().uuid(),
  name: z.string(),
  joinCode: z.string(),
  ownerHandle: z.string(),
  actionText: z.string().nullable(),
  startsAt: z.string(),
  endsAt: z.string(),
  memberCount: z.number().int().nonnegative(),
  recurring: z.boolean(),
  alreadyMember: z.boolean(),
  canJoinNext: z.boolean(),
});

export const joinFightRequestSchema = z
  .object({
    code: z.string().min(1).max(16).optional(),
    fightId: z.string().uuid().optional(),
    start: fightJoinStartSchema.default("now"),
  })
  .superRefine((value, ctx) => {
    if (!value.code && !value.fightId) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "code or fightId is required",
      });
    }
  });

export const leaveFightRequestSchema = z.object({
  fightId: z.string().uuid(),
});

export type FightVisibility = z.infer<typeof fightVisibilitySchema>;
export type JoinableFightSummary = z.infer<typeof joinableFightSummarySchema>;
export type JoinFightRequest = z.infer<typeof joinFightRequestSchema>;
export type LeaveFightRequest = z.infer<typeof leaveFightRequestSchema>;
