import type { SupabaseClient } from "@supabase/supabase-js";
import { ApiError } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import { profileSchema, type Profile, type UpdateProfileRequest } from "@/lib/types/profiles/profile";

export async function readProfile(
  userId: string,
  admin: SupabaseClient = createAdminClient(),
): Promise<Profile> {
  const { data, error } = await admin.from("profiles")
    .select("user_id, handle, display_name, handle_set_at, referral_code")
    .eq("user_id", userId)
    .is("deleted_at", null)
    .maybeSingle();
  if (error) throw new ApiError(500, "db_error", "Could not load profile");
  if (!data) throw new ApiError(401, "profile_missing", "Invalid or deleted account");
  return profileSchema.parse(data);
}

export async function updateProfile(
  userId: string,
  input: UpdateProfileRequest,
  admin: SupabaseClient = createAdminClient(),
): Promise<Profile> {
  const { data, error } = await admin.from("profiles")
    .update({ ...input, ...(input.handle !== undefined ? { handle_set_at: new Date().toISOString() } : {}) })
    .eq("user_id", userId)
    .is("deleted_at", null)
    .select("user_id, handle, display_name, handle_set_at, referral_code")
    .maybeSingle();
  if (error?.code === "23505") throw new ApiError(409, "handle_taken", "That username is taken");
  if (error) throw new ApiError(500, "db_error", "Could not update profile");
  if (!data) throw new ApiError(401, "profile_missing", "Invalid or deleted account");
  return profileSchema.parse(data);
}
