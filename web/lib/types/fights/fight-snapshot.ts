import { z } from "zod";
import { fightMemberStateValues, fightStateValues } from "./membership-decision";
import { fightVisibilityValues } from "./fight-visibility";

const timestampSchema = z.string().datetime({ offset: true });

export const fightSnapshotRequestSchema = z.object({
  time_zone: z.string().min(1).max(100).refine((timeZone) => {
    try {
      new Intl.DateTimeFormat("en-US", { timeZone }).format();
      return true;
    } catch {
      return false;
    }
  }, "invalid time zone"),
}).strict();

export const fightSnapshotSchema = z.object({
  fights: z.array(z.object({
    id: z.string().uuid(),
    owner_id: z.string().uuid(),
    name: z.string(),
    state: z.enum(fightStateValues),
    starts_at: timestampSchema,
    ends_at: timestampSchema,
    action_text: z.string().nullable(),
    series_id: z.string().uuid().nullable(),
  })),
  members: z.array(z.object({
    fight_id: z.string().uuid(),
    user_id: z.string().uuid(),
    state: z.enum(fightMemberStateValues),
    current_value: z.number().finite().nullable(),
    rank: z.number().int().nullable(),
    final_value: z.number().finite().nullable(),
    last_synced_at: timestampSchema.nullable(),
    final_steps_complete: z.boolean(),
  })),
  profiles: z.array(z.object({
    user_id: z.string().uuid(),
    handle: z.string(),
    display_name: z.string(),
  })),
  series: z.array(z.object({
    id: z.string().uuid(),
    join_code: z.string().nullable(),
    visibility: z.enum(fightVisibilityValues),
    recurring: z.boolean(),
  })),
  step_days: z.array(z.object({
    user_id: z.string().uuid(),
    day: z.string().date(),
    steps: z.number().int().nonnegative(),
  })),
});

export const fightMaintenanceCandidateSchema = z.object({
  id: z.string().uuid(),
  state: z.enum(fightStateValues),
  starts_at: timestampSchema,
  ends_at: timestampSchema,
});

export const userFightMaintenanceSchema = z.object({
  candidates: z.array(fightMaintenanceCandidateSchema),
  recurring: z.array(z.string().uuid()),
});

export type FightSnapshotRequest = z.infer<typeof fightSnapshotRequestSchema>;
export type FightSnapshot = z.infer<typeof fightSnapshotSchema>;
export type FightMaintenanceCandidate = z.infer<typeof fightMaintenanceCandidateSchema>;
export type UserFightMaintenance = z.infer<typeof userFightMaintenanceSchema>;
