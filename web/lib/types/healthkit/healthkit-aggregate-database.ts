import { z } from "zod";
import { fightCalculationRowSchema } from "@/lib/types/fights/fight-calculation";

const timestampSchema = z.string().refine((value) => Number.isFinite(Date.parse(value)));

export const healthKitAggregateSourceSchema = z.object({
  id: z.string().uuid(),
  complete_through: timestampSchema,
  server_now: timestampSchema,
});

export const healthKitAggregateFightSchema = fightCalculationRowSchema.pick({
  starts_at: true,
  ends_at: true,
  outcome_rule: true,
  stake_minor: true,
  default_goal_value: true,
}).extend({ fight_id: z.string().uuid() });

export const healthKitAggregateMemberSchema = z.object({
  fight_id: z.string().uuid(),
  user_id: z.string().uuid(),
  current_value: z.coerce.number().finite().nullable(),
  final_value: z.coerce.number().finite().nullable(),
  personal_target: z.coerce.number().finite().nullable(),
});

export type HealthKitAggregateSource = z.infer<typeof healthKitAggregateSourceSchema>;
export type HealthKitAggregateFight = z.infer<typeof healthKitAggregateFightSchema>;
export type HealthKitAggregateMember = z.infer<typeof healthKitAggregateMemberSchema>;
