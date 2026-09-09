import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { deleteAccount } from "@/lib/supabase/queries/delete-account-supabase-query";
import { readProfile, updateProfile } from "@/lib/supabase/queries/profiles-supabase-query";
import { updateProfileRequestSchema } from "@/lib/types/profiles/profile";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  return json(await readProfile(userId));
});

export const PATCH = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const input = updateProfileRequestSchema.parse(await readJson(request));
  return json(await updateProfile(userId, input));
});

export const DELETE = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const appleAuthorizationRevoked = await deleteAccount(userId);
  return json({
    apple_authorization_revoked: appleAuthorizationRevoked,
    deleted: true,
  });
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
