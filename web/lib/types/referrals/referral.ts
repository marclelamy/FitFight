import { z } from "zod";

export const referralCodeSchema = z.string().uuid();
export const claimReferralRequestSchema = z.object({ code: referralCodeSchema }).strict();
export const claimReferralResponseSchema = z.object({ recorded: z.boolean() }).strict();

export type ReferralCode = z.infer<typeof referralCodeSchema>;
export type ClaimReferralRequest = z.infer<typeof claimReferralRequestSchema>;
export type ClaimReferralResponse = z.infer<typeof claimReferralResponseSchema>;
