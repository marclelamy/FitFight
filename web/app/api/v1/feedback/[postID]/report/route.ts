import { apiRoute, corsPreflight, json, readJson, requireUuid } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { reportFeedbackPost } from "@/lib/supabase/queries/feedback-supabase-query";
import { reportFeedbackPostRequestSchema } from "@/lib/types/feedback/feedback";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute<{ postID: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  const parsed = reportFeedbackPostRequestSchema.safeParse(await readJson(request));
  if (!parsed.success) {
    throw parsed.error;
  }
  return json(await reportFeedbackPost(
    userId,
    requireUuid(params.postID, "postID"),
    parsed.data,
  ));
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
