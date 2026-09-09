import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { createAppFeedbackBacklogItem } from "@/lib/notion/create-app-feedback-item";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import {
  createFeedbackPost,
  listFeedbackPosts,
} from "@/lib/supabase/queries/feedback-supabase-query";
import {
  createFeedbackPostRequestSchema,
  listFeedbackQuerySchema,
} from "@/lib/types/feedback/feedback";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const kind = new URL(request.url).searchParams.get("kind");
  const parsed = listFeedbackQuerySchema.safeParse(kind ? { kind } : {});
  if (!parsed.success) {
    throw parsed.error;
  }
  return json(await listFeedbackPosts(userId, parsed.data));
});

export const POST = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const parsed = createFeedbackPostRequestSchema.safeParse(await readJson(request));
  if (!parsed.success) {
    throw parsed.error;
  }
  const created = await createFeedbackPost(userId, parsed.data);
  await createAppFeedbackBacklogItem(created.post);
  return json(created, 201);
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
