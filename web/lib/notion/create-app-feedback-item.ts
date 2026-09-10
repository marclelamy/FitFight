import type { FeedbackPostSummary } from "@/lib/types/feedback/feedback";
import {
  feedbackPostNotionMarkerPrefix,
  notionAppFeedbackDefaults,
  notionFeedbackPageQuerySchema,
  notionTokenSchema,
  type NotionProductBacklogStatus,
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
    `${feedbackPostNotionMarkerPrefix}${post.id}`,
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

export async function markAppFeedbackBacklogStatus(
  postId: string,
  status: NotionProductBacklogStatus,
  fetchImpl: typeof fetch = fetch,
  note?: string,
): Promise<"updated" | "skipped" | "failed"> {
  const token = notionTokenSchema.safeParse(process.env.NOTION_TOKEN);
  if (!token.success) {
    return "skipped";
  }

  const headers = {
    Authorization: `Bearer ${token.data}`,
    "Content-Type": "application/json",
    "Notion-Version": NOTION_VERSION,
  };
  const marker = `${feedbackPostNotionMarkerPrefix}${postId}`;

  try {
    const query = await fetchImpl(
      `https://api.notion.com/v1/databases/${PRODUCT_BACKLOG_DATABASE_ID}/query`,
      {
        method: "POST",
        headers,
        body: JSON.stringify({
          page_size: 1,
          filter: {
            property: "Notes",
            rich_text: { contains: marker },
          },
        }),
        signal: AbortSignal.timeout(8_000),
      },
    );
    if (!query.ok) {
      console.error("fitfight_notion_feedback", JSON.stringify({
        post_id: postId,
        status: query.status,
      }));
      return "failed";
    }

    const parsed = notionFeedbackPageQuerySchema.safeParse(await query.json());
    const page = parsed.success ? parsed.data.results[0] : undefined;
    if (!page) {
      return "skipped";
    }

    const properties: Record<string, unknown> = {
      Status: { select: { name: status } },
    };
    const existingNotes = page.properties?.Notes?.rich_text
      .map((item) => item.plain_text)
      .join("");
    if (note && existingNotes !== undefined && !existingNotes.includes(note)) {
      properties.Notes = {
        rich_text: [{
          text: { content: `${existingNotes}\n\n${note}`.slice(0, RICH_TEXT_LIMIT) },
        }],
      };
    }

    const patch = await fetchImpl(`https://api.notion.com/v1/pages/${page.id}`, {
      method: "PATCH",
      headers,
      body: JSON.stringify({ properties }),
      signal: AbortSignal.timeout(8_000),
    });
    if (patch.ok) {
      return "updated";
    }
    console.error("fitfight_notion_feedback", JSON.stringify({
      post_id: postId,
      status: patch.status,
    }));
    return "failed";
  } catch {
    console.error("fitfight_notion_feedback", JSON.stringify({
      post_id: postId,
      status: 0,
    }));
    return "failed";
  }
}
