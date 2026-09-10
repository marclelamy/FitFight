import { z } from "zod";

export const notionTokenSchema = z.string().trim().min(1);

export const notionProductBacklogTypeValues = ["Idea", "Request", "Bug", "Feature"] as const;
export const notionProductBacklogTypeSchema = z.enum(notionProductBacklogTypeValues);

export const notionAppFeedbackDefaults = {
  priority: "P0",
  product: "FitFight",
  source: "App feedback",
  status: "Inbox",
} as const;

export type NotionProductBacklogType = z.infer<typeof notionProductBacklogTypeSchema>;
