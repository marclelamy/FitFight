import { z } from "zod";

export const notificationKindValues = ["fight_ended", "grace_reminder", "fight_finalized"] as const;
export const notificationSlotValues = ["t0", "t12", "t18", "t23", "final"] as const;
export const notificationIntentStatusValues = [
  "pending",
  "skipped",
  "sent",
  "failed",
  "expired",
] as const;
export const notificationSkipReasonValues = [
  "already_complete",
  "no_token",
  "muted",
  "superseded",
  "fight_cancelled",
] as const;

export const notificationKindSchema = z.enum(notificationKindValues);
export const notificationSlotSchema = z.enum(notificationSlotValues);
export const notificationIntentStatusSchema = z.enum(notificationIntentStatusValues);
export const notificationSkipReasonSchema = z.enum(notificationSkipReasonValues);

export const notificationCopyKeyValues = [
  "fight_ended_everyone",
  "fight_ended_sync",
  "grace_12h",
  "grace_6h",
  "grace_1h",
  "fight_finalized",
] as const;

export const notificationCopyKeySchema = z.enum(notificationCopyKeyValues);

export const pendingNotificationIntentSchema = z.object({
  id: z.string().uuid(),
  user_id: z.string().uuid(),
  fight_id: z.string().uuid(),
  kind: notificationKindSchema,
  slot: notificationSlotSchema,
  route: z.string().min(1),
  copy_key: notificationCopyKeySchema,
});

export type NotificationKind = z.infer<typeof notificationKindSchema>;
export type NotificationSlot = z.infer<typeof notificationSlotSchema>;
export type NotificationIntentStatus = z.infer<typeof notificationIntentStatusSchema>;
export type NotificationSkipReason = z.infer<typeof notificationSkipReasonSchema>;
export type NotificationCopyKey = z.infer<typeof notificationCopyKeySchema>;
export type PendingNotificationIntent = z.infer<typeof pendingNotificationIntentSchema>;
