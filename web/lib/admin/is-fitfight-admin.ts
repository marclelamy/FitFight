import type { SupabaseClient } from "@supabase/supabase-js";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import {
  fitFightAdminEmailValues,
  fitFightAdminHandleValues,
  type FitFightAdminViewer,
} from "@/lib/types/admin/fitfight-admin";

function listedValues(defaults: readonly string[], extra: string | undefined): Set<string> {
  const values = [...defaults];
  if (extra) {
    for (const part of extra.split(",")) {
      const item = part.trim().toLowerCase();
      if (item) values.push(item);
    }
  }
  return new Set(values.map((value) => value.toLowerCase()));
}

export function isFitFightAdmin(viewer: FitFightAdminViewer): boolean {
  const handles = listedValues(fitFightAdminHandleValues, process.env.FITFIGHT_ADMIN_HANDLES);
  if (handles.has(viewer.handle.trim().toLowerCase())) {
    return true;
  }
  const emails = listedValues(fitFightAdminEmailValues, process.env.FITFIGHT_ADMIN_EMAILS);
  return viewer.emails.some((email) => emails.has(email.trim().toLowerCase()));
}

export async function readAdminViewer(
  userId: string,
  admin: SupabaseClient = createAdminClient(),
): Promise<FitFightAdminViewer> {
  const { data, error } = await admin
    .from("profiles")
    .select("handle")
    .eq("user_id", userId)
    .is("deleted_at", null)
    .maybeSingle();
  if (error) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not verify account");
  }
  if (!data?.handle) {
    throw new ApiError(401, ERROR_CODES.profile_missing, "Invalid or deleted account");
  }

  const userResult = await admin.auth.admin.getUserById(userId);
  if (userResult.error || !userResult.data.user) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not verify account");
  }

  const emails: string[] = [];
  const user = userResult.data.user;
  if (user.email) {
    emails.push(user.email);
  }
  const metadataEmail = user.user_metadata.email;
  if (typeof metadataEmail === "string" && metadataEmail.trim()) {
    emails.push(metadataEmail);
  }
  for (const identity of user.identities ?? []) {
    const identityEmail = identity.identity_data?.email;
    if (typeof identityEmail === "string" && identityEmail.trim()) {
      emails.push(identityEmail);
    }
  }
  return { handle: data.handle, emails };
}
