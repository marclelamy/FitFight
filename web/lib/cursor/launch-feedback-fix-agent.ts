import { ApiError, ERROR_CODES } from "@/lib/http";
import { cursorWebhookSecret } from "@/lib/cursor/cursor-agent-webhook";
import type { FeedbackPostDetail } from "@/lib/types/feedback/feedback";
import {
  cursorApiKeySchema,
  cursorCreateAgentResponseSchema,
  fitFightAgentStartingRef,
  fitFightGithubRepoUrl,
} from "@/lib/types/cursor/cloud-agent";

const CURSOR_AGENTS_URL = "https://api.cursor.com/v0/agents";

export async function launchFeedbackFixAgent(
  detail: FeedbackPostDetail,
  fetchImpl: typeof fetch = fetch,
  requestUrl?: string,
): Promise<{ agent_id: string; agent_url: string }> {
  const apiKey = cursorApiKeySchema.safeParse(process.env.CURSOR_API_KEY);
  if (!apiKey.success) {
    throw new ApiError(503, ERROR_CODES.config, "Cursor isn’t configured yet.");
  }

  const commentBlock = detail.comments.length === 0
    ? "No comments."
    : detail.comments.map((comment, index) => (
      `${index + 1}. @${comment.author_handle} (${comment.created_at})\n${comment.body}\nDevice: ${JSON.stringify(comment.metadata)}`
    )).join("\n\n");
  const prompt = [
    `Fix this FitFight Bugs & requests item in ${fitFightGithubRepoUrl}.`,
    "",
    "Rules:",
    "- Branch off develop. Open a PR into develop. Do not merge. Do not PR into main.",
    "- Do not bump MARKETING_VERSION. Changelog rows reuse 1.0.0 if people will see the change.",
    "- Do exactly this request. Do not add extras, refactors, or unrelated cleanup.",
    "- Never put secrets, .p8 files, or database passwords in git or chat.",
    "- Cloud only. Do not ask Marc to open Xcode or a home Mac.",
    "- Do not create or call app-facing Postgres RPCs.",
    "- Do not run destructive database commands.",
    "- Do not create or update Notion rows. FitFight already created the Product Backlog item and will move it to Building, then Done when this run finishes with a PR.",
    "",
    "Use the post and comments as the spec.",
    "",
    `Kind: ${detail.post.kind}`,
    `Title: ${detail.post.title}`,
    `Author: @${detail.post.author_handle}`,
    `Created: ${detail.post.created_at}`,
    `Feedback post ID: ${detail.post.id}`,
    `Upvotes: ${detail.post.vote_count}`,
    `Device: ${JSON.stringify(detail.post.metadata)}`,
    "",
    "Post:",
    detail.post.body,
    "",
    "Comments:",
    commentBlock,
  ].join("\n");

  const body: Record<string, unknown> = {
    prompt: { text: prompt },
    source: { repository: fitFightGithubRepoUrl, ref: fitFightAgentStartingRef },
    target: { autoCreatePr: true, skipReviewerRequest: true },
  };
  const webhookSecret = cursorWebhookSecret();
  if (requestUrl && webhookSecret) {
    body.webhook = {
      url: `${new URL(requestUrl).origin}/api/internal/cursor-agent/${detail.post.id}`,
      secret: webhookSecret,
    };
  }

  const response = await fetchImpl(CURSOR_AGENTS_URL, {
    method: "POST",
    headers: {
      Authorization: `Basic ${Buffer.from(`${apiKey.data}:`, "utf8").toString("base64")}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(15_000),
  });

  const raw: unknown = await response.json().catch(() => null);
  if (response.status === 429) {
    throw new ApiError(429, ERROR_CODES.rate_limited, "Cursor is busy. Try again in a minute.");
  }
  if (!response.ok) {
    console.error("fitfight_cursor_feedback", JSON.stringify({
      post_id: detail.post.id,
      status: response.status,
    }));
    throw new ApiError(502, ERROR_CODES.internal, "Could not start the Cursor agent.");
  }

  const parsed = cursorCreateAgentResponseSchema.safeParse(raw);
  if (!parsed.success) {
    throw new ApiError(502, ERROR_CODES.internal, "Could not start the Cursor agent.");
  }
  return {
    agent_id: parsed.data.id,
    agent_url: parsed.data.target.url,
  };
}
