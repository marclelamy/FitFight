import { ApiError, ERROR_CODES } from "@/lib/http";
import type { FeedbackPostDetail } from "@/lib/types/feedback/feedback";
import { feedbackPostNotionMarkerPrefix } from "@/lib/types/notion/product-backlog";
import {
  cursorApiKeySchema,
  cursorCreateAgentResponseSchema,
  fitFightAgentStartingRef,
  fitFightGithubRepoUrl,
} from "@/lib/types/cursor/cloud-agent";

const CURSOR_AGENTS_URL = "https://api.cursor.com/v1/agents";

export async function launchFeedbackFixAgent(
  detail: FeedbackPostDetail,
  fetchImpl: typeof fetch = fetch,
): Promise<{ agent_id: string; agent_url: string }> {
  const apiKey = cursorApiKeySchema.safeParse(process.env.CURSOR_API_KEY);
  if (!apiKey.success) {
    throw new ApiError(503, ERROR_CODES.config, "Cursor isn’t configured yet.");
  }

  const commentBlock = detail.comments.length === 0
    ? "No comments."
    : detail.comments.map((comment, index) => (
      `${index + 1}. @${comment.author_handle} (${comment.created_at})\n${comment.body}`
    )).join("\n\n");
  const prompt = [
    "Fix this FitFight Bugs & requests item in https://github.com/marclelamy/FitFight.",
    "",
    "Rules:",
    "- Branch off develop. Open a PR into develop. Do not merge. Do not PR into main.",
    "- Do not bump MARKETING_VERSION. Changelog rows reuse 1.0.0 if people will see the change.",
    "- Do exactly this request. Do not add extras, refactors, or unrelated cleanup.",
    "- Never put secrets, .p8 files, or database passwords in git or chat.",
    "- Cloud only. Do not ask Marc to open Xcode or a home Mac.",
    "- Do not create or call app-facing Postgres RPCs.",
    "- Do not run destructive database commands.",
    "",
    "Notion Product Backlog (Blend HQ):",
    "- New app feedback already creates a P0 Inbox row (Product FitFight, Source App feedback).",
    `- Find that row by Notes containing \`${feedbackPostNotionMarkerPrefix}${detail.post.id}\`.`,
    "- Status options are Inbox, Triaged, Ready, Building, Done, Wont.",
    "- After you open the PR, if you can reach Notion: add the PR URL to Notes. Leave Status as Building, or set it to Building if it is still Inbox.",
    "- Do not set Status to Done. The work is not shipped until Marc merges. Skip Notion if no row exists. Do not create a second row.",
    "",
    "Use the post and comments as the spec.",
    "",
    `Kind: ${detail.post.kind}`,
    `Title: ${detail.post.title}`,
    `Author: @${detail.post.author_handle}`,
    `Created: ${detail.post.created_at}`,
    `Feedback post ID: ${detail.post.id}`,
    `Upvotes: ${detail.post.vote_count}`,
    "",
    "Post:",
    detail.post.body,
    "",
    "Comments:",
    commentBlock,
  ].join("\n");

  const response = await fetchImpl(CURSOR_AGENTS_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey.data}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      prompt: { text: prompt },
      name: `Fix: ${detail.post.title}`.slice(0, 100),
      repos: [{ url: fitFightGithubRepoUrl, startingRef: fitFightAgentStartingRef }],
      autoCreatePR: true,
      skipReviewerRequest: true,
    }),
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
    agent_id: parsed.data.agent.id,
    agent_url: parsed.data.agent.url,
  };
}
