import type { SupabaseClient } from "@supabase/supabase-js";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import { requireLatestAppRelease } from "@/lib/releases/app-release";

export type AuthedUser = {
  userId: string;
};

function bearerToken(request: Request): string {
  const header = request.headers.get("authorization") ?? request.headers.get("Authorization");
  if (!header) {
    throw new ApiError(401, ERROR_CODES.unauthorized, "Missing bearer token");
  }
  const match = /^Bearer\s+(\S+)/i.exec(header.trim());
  if (!match?.[1]) {
    throw new ApiError(401, ERROR_CODES.unauthorized, "Missing bearer token");
  }
  return match[1];
}

function claimSub(claims: unknown): string | null {
  if (!claims || typeof claims !== "object") {
    return null;
  }
  const sub = (claims as { sub?: unknown }).sub;
  return typeof sub === "string" && sub.length > 0 ? sub : null;
}

async function requireActiveProfile(admin: SupabaseClient, userId: string): Promise<void> {
  const { data, error } = await admin
    .from("profiles")
    .select("user_id")
    .eq("user_id", userId)
    .is("deleted_at", null)
    .maybeSingle();
  if (error) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not verify account");
  }
  if (!data) {
    throw new ApiError(401, ERROR_CODES.profile_missing, "Invalid or deleted account");
  }
}

export async function verifyUser(request: Request): Promise<AuthedUser> {
  const jwt = bearerToken(request);
  await requireLatestAppRelease(request);
  const admin = createAdminClient();

  const claimsResult = await admin.auth.getClaims(jwt);
  const fromClaims = claimSub(claimsResult.data?.claims);
  if (fromClaims) {
    await requireActiveProfile(admin, fromClaims);
    return { userId: fromClaims };
  }

  const userResult = await admin.auth.getUser(jwt);
  const userId = userResult.data.user?.id;
  if (userId) {
    await requireActiveProfile(admin, userId);
    return { userId };
  }

  throw new ApiError(401, ERROR_CODES.unauthorized, "Invalid or expired token");
}
