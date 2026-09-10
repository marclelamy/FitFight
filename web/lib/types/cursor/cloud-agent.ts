import { z } from "zod";

export const cursorApiKeySchema = z.string().trim().min(1);

export const fitFightGithubRepoUrl = "https://github.com/marclelamy/FitFight";
export const fitFightAgentStartingRef = "develop";

export const cursorCreateAgentResponseSchema = z
  .object({
    agent: z.object({
      id: z.string().min(1),
      url: z.string().url(),
    }),
  });

export type CursorCreateAgentResponse = z.infer<typeof cursorCreateAgentResponseSchema>;
