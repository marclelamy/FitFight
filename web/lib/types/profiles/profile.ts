import { z } from "zod";
import { mediaObjectSchema } from "@/lib/types/media/media";

export const profileSchema = z.object({
  user_id: z.string().uuid(),
  handle: z.string(),
  display_name: z.string(),
  handle_set_at: z.string().datetime({ offset: true }).nullable(),
  referral_code: z.string().uuid(),
  avatar: mediaObjectSchema.nullable(),
});

export const updateProfileRequestSchema = z.object({
  handle: z.string()
    .transform((value) => value.trim().replace(/^@+|@+$/g, "").toLowerCase())
    .pipe(z.string().regex(/^[a-z0-9_]{2,30}$/, "Use 2–30 letters, numbers, or underscore"))
    .optional(),
  display_name: z.string().trim().min(1, "Enter a display name").optional(),
  avatar_media_id: z.string().uuid().nullable().optional(),
}).strict().refine((input) => (
  input.handle !== undefined || input.display_name !== undefined || input.avatar_media_id !== undefined
), {
  message: "Supply a username, display name, or photo",
});

export type Profile = z.infer<typeof profileSchema>;
export type UpdateProfileRequest = z.infer<typeof updateProfileRequestSchema>;
