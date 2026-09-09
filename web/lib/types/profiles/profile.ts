import { z } from "zod";

export const profileSchema = z.object({
  user_id: z.string().uuid(),
  handle: z.string(),
  display_name: z.string(),
  handle_set_at: z.string().datetime({ offset: true }).nullable(),
  referral_code: z.string().uuid(),
});

export const updateProfileRequestSchema = z.object({
  handle: z.string()
    .transform((value) => value.trim().replace(/^@+|@+$/g, "").toLowerCase())
    .pipe(z.string().regex(/^[a-z0-9_]{2,30}$/, "Use 2–30 letters, numbers, or underscore"))
    .optional(),
  display_name: z.string().trim().min(1, "Enter a display name").optional(),
}).strict().refine((input) => input.handle !== undefined || input.display_name !== undefined, {
  message: "Supply a username or display name",
});

export type Profile = z.infer<typeof profileSchema>;
export type UpdateProfileRequest = z.infer<typeof updateProfileRequestSchema>;
