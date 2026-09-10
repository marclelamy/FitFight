import { z } from "zod";

export const notionTokenSchema = z.string().trim().min(1);

export const notionProductBacklogTypeValues = ["Idea", "Request", "Bug", "Feature"] as const;
export const notionProductBacklogTypeSchema = z.enum(notionProductBacklogTypeValues);

export const notionProductBacklogStatusValues = [
  "Inbox",
  "Triaged",
  "Ready",
  "Building",
  "Done",
  "Wont",
] as const;
export const notionProductBacklogStatusSchema = z.enum(notionProductBacklogStatusValues);

export const notionAppFeedbackDefaults = {
  priority: "P0",
  product: "FitFight",
  source: "App feedback",
  status: "Inbox",
} as const;

export const notionAppFeedbackAgentStatus = "Building" as const;
export const notionAppFeedbackDoneStatus = "Done" as const;
export const feedbackPostNotionMarkerPrefix = "feedback_post: ";

export const notionFeedbackPageQuerySchema = z.object({
  results: z.array(z.object({
    id: z.string().min(1),
    properties: z.object({
      Notes: z.object({
        rich_text: z.array(z.object({ plain_text: z.string() })),
      }).optional(),
    }).optional(),
  })),
});

export type NotionProductBacklogType = z.infer<typeof notionProductBacklogTypeSchema>;
export type NotionProductBacklogStatus = z.infer<typeof notionProductBacklogStatusSchema>;
export type NotionFeedbackPageQuery = z.infer<typeof notionFeedbackPageQuerySchema>;
