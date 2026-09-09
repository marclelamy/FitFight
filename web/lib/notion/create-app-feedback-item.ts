import type { FeedbackPostSummary } from "@/lib/types/feedback/feedback";
import {
  notionAppFeedbackDefaults,
  notionTokenSchema,
  type NotionProductBacklogType,
} from "@/lib/types/notion/product-backlog";
import { appReleaseProjectSchema } from "@/lib/types/releases/app-release";

// Blend HQ → Product Backlog.
const PRODUCT_BACKLOG_DATABASE_ID = "4427c71a-f01b-4e2f-9e0d-3b3e46debab4";
const NOTION_VERSION = "2022-06-28";
const RICH_TEXT_LIMIT = 2000;

export async function createAppFeedbackBacklogItem(
  post: FeedbackPostSummary,
  fetchImpl: typeof fetch = fetch,
): Promise<boolean> {
  const token = notionTokenSchema.safeParse(process.env.NOTION_TOKEN);
  if (!token.success) {
    return false;
  }

  const project = appReleaseProjectSchema.safeParse(
    process.env.NEXT_PUBLIC_SUPABASE_URL?.replace(/\/$/, ""),
  );
  const channel = !project.success
    ? "unknown"
    : project.data === "https://pvqntpteehdvhqyctwum.supabase.co"
      ? "prod"
      : "staging";

  let type: NotionProductBacklogType;
  switch (post.kind) {
    case "bug":
      type = "Bug";
      break;
    case "feature":
      type = "Feature";
      break;
    default: {
      const exhaustive: never = post.kind;
      return exhaustive;
    }
  }

  const notes = [
    `@${post.author_handle} · ${post.kind} · ${channel}`,
    post.body,
    `feedback_post: ${post.id}`,
  ].join("\n\n");

  try {
    const response = await fetchImpl("https://api.notion.com/v1/pages", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token.data}`,
        "Content-Type": "application/json",
        "Notion-Version": NOTION_VERSION,
      },
      body: JSON.stringify({
        parent: { database_id: PRODUCT_BACKLOG_DATABASE_ID },
        properties: {
          Name: {
            title: [{ text: { content: post.title.slice(0, RICH_TEXT_LIMIT) } }],
          },
          Notes: {
            rich_text: [{ text: { content: notes.slice(0, RICH_TEXT_LIMIT) } }],
          },
          Priority: { select: { name: notionAppFeedbackDefaults.priority } },
          Product: { select: { name: notionAppFeedbackDefaults.product } },
          Source: { select: { name: notionAppFeedbackDefaults.source } },
          Status: { select: { name: notionAppFeedbackDefaults.status } },
          Type: { select: { name: type } },
        },
        children: [
          {
            object: "block",
            type: "paragraph",
            paragraph: {
              rich_text: [{ type: "text", text: { content: post.body.slice(0, RICH_TEXT_LIMIT) } }],
            },
          },
        ],
      }),
      signal: AbortSignal.timeout(8_000),
    });
    if (response.ok) {
      return true;
    }
    console.error("fitfight_notion_feedback", JSON.stringify({
      post_id: post.id,
      status: response.status,
    }));
    return false;
  } catch {
    // The in-app post already succeeded. Notion is best-effort.
    console.error("fitfight_notion_feedback", JSON.stringify({
      post_id: post.id,
      status: 0,
    }));
    return false;
  }
}
