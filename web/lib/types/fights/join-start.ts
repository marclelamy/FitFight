import { z } from "zod";

export const fightJoinStartValues = ["now", "next"] as const;
export const fightJoinStartSchema = z.enum(fightJoinStartValues);

export const membershipAcceptRequestSchema = z.object({
  personalTarget: z.number().optional(),
  start: fightJoinStartSchema.default("now"),
});

export type FightJoinStart = z.infer<typeof fightJoinStartSchema>;
export type MembershipAcceptRequest = z.infer<typeof membershipAcceptRequestSchema>;
