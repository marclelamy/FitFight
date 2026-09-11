import { createHmac, timingSafeEqual } from "node:crypto";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { markAppFeedbackBacklogStatus } from "@/lib/notion/create-app-feedback-item";
import {
  cursorAgentWebhookSchema,
  cursorApiKeySchema,
  cursorWebhookSecretSchema,
} from "@/lib/types/cursor/cloud-agent";
import { notionAppFeedbackDoneStatus } from "@/lib/types/notion/product-backlog";

export function cursorWebhookSecret(): string | undefined {
  const apiKey = cursorApiKeySchema.safeParse(process.env.CURSOR_API_KEY);
  if (apiKey.success && cursorWebhookSecretSchema.safeParse(apiKey.data).success) {
    return apiKey.data;
  }
  const cron = cursorWebhookSecretSchema.safeParse(
    process.env.CRON_SECRET ?? process.env.FITFIGHT_CRON_SECRET,
  );
  if (cron.success) {
    return cron.data;
  }
}

export async function handleCursorAgentWebhook(
  postId: string,
  request: Request,
  fetchImpl: typeof fetch = fetch,
): Promise<{ ok: true; updated: boolean }> {
  const secret = cursorWebhookSecret();
  if (!secret) {
    throw new ApiError(503, ERROR_CODES.config, "Cursor webhook secret is not set");
  }

  const rawBody = await request.text();
  const signature = request.headers.get("x-webhook-signature") ?? "";
  const expected = `sha256=${createHmac("sha256", secret).update(rawBody).digest("hex")}`;
  const expectedBytes = Buffer.from(expected);
  const signatureBytes = Buffer.from(signature);
  if (
    expectedBytes.length !== signatureBytes.length
    || !timingSafeEqual(expectedBytes, signatureBytes)
  ) {
    throw new ApiError(401, ERROR_CODES.unauthorized, "Unauthorized");
  }

  let raw: unknown;
  try {
    raw = JSON.parse(rawBody) as unknown;
  } catch {
    throw new ApiError(400, ERROR_CODES.invalid_json, "Request body is not valid JSON");
  }

  const parsed = cursorAgentWebhookSchema.safeParse(raw);
  if (!parsed.success) {
    throw parsed.error;
  }

  switch (parsed.data.status) {
    case "FINISHED": {
      const prUrl = parsed.data.target?.prUrl;
      if (!prUrl) {
        return { ok: true, updated: false };
      }
      const result = await markAppFeedbackBacklogStatus(
        postId,
        notionAppFeedbackDoneStatus,
        fetchImpl,
        prUrl,
      );
      if (result === "failed") {
        throw new ApiError(502, ERROR_CODES.internal, "Could not mark the backlog row done.");
      }
      return { ok: true, updated: result === "updated" };
    }
    case "ERROR":
      return { ok: true, updated: false };
    default: {
      const exhaustive: never = parsed.data.status;
      return exhaustive;
    }
  }
}
