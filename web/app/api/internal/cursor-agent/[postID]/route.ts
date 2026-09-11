import { apiRoute, json, requireUuid } from "@/lib/http";
import { handleCursorAgentWebhook } from "@/lib/cursor/cursor-agent-webhook";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute<{ postID: string }>(async (request, { params }) => {
  const postId = requireUuid(params.postID, "postID");
  return json(await handleCursorAgentWebhook(postId, request));
});
