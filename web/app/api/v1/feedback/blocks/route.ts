import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { blockFeedbackAuthor } from "@/lib/supabase/queries/feedback-supabase-query";
import { blockFeedbackAuthorRequestSchema } from "@/lib/types/feedback/feedback";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const parsed = blockFeedbackAuthorRequestSchema.safeParse(await readJson(request));
  if (!parsed.success) {
    throw parsed.error;
  }
  return json(await blockFeedbackAuthor(userId, parsed.data.user_id));
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
