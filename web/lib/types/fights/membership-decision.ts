import { z } from "zod";

export const fightStateValues = ["draft", "inviting", "scheduled", "live", "awaiting_final_sync", "final", "cancelled"] as const;
export const fightMemberStateValues = ["invited", "accepted", "deferred", "declined", "withdrawn", "disqualified"] as const;

export const membershipDecisionRowSchema = z.object({
  id: z.string().uuid(),
  state: z.enum(fightStateValues),
  member_state: z.enum(fightMemberStateValues),
});

export type MembershipDecisionRow = z.infer<typeof membershipDecisionRowSchema>;
