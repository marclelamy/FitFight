import { z } from "zod";

export const cursorApiKeySchema = z.string().trim().min(1);
export const cursorWebhookSecretSchema = z.string().min(32);

export const fitFightGithubRepoUrl = "https://github.com/slooowshutter/FitFight";
export const fitFightAgentStartingRef = "develop";

export const cursorCreateAgentResponseSchema = z.object({
  agent: z.object({
    id: z.string().min(1),
    url: z.string().url().optional(),
  }),
});

export const cursorApiErrorSchema = z.union([
  z.object({
    error: z.object({
      code: z.string(),
      message: z.string(),
    }),
  }).transform((value) => value.error),
  z.object({
    code: z.string(),
    message: z.string(),
  }),
]);

export const cursorAgentWebhookStatusValues = ["ERROR", "FINISHED"] as const;
export const cursorAgentWebhookStatusSchema = z.enum(cursorAgentWebhookStatusValues);

export const cursorAgentWebhookSchema = z.object({
  event: z.literal("statusChange"),
  id: z.string().min(1),
  status: cursorAgentWebhookStatusSchema,
  target: z.object({
    prUrl: z.string().url().optional(),
  }).optional(),
});

export type CursorCreateAgentResponse = z.infer<typeof cursorCreateAgentResponseSchema>;
export type CursorApiError = z.infer<typeof cursorApiErrorSchema>;
export type CursorAgentWebhookStatus = z.infer<typeof cursorAgentWebhookStatusSchema>;
export type CursorAgentWebhook = z.infer<typeof cursorAgentWebhookSchema>;
