import {
  dailyStatusModelResponseSchema,
  type DailyStatusPromptContext,
} from "@/lib/types/notifications/daily-status";

const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";
const MODEL = "z-ai/glm-5.3-flash";

export function isOpenRouterConfigured(): boolean {
  const key = process.env.OPENROUTER_API_KEY?.trim();
  return Boolean(key);
}

function systemPrompt(locale: DailyStatusPromptContext["locale"]): string {
  const language = locale === "fr" ? "French" : "English";
  return [
    "You write short FitFight step-challenge status nudges.",
    `Reply in ${language}.`,
    "Return JSON only: {\"alert\":\"...\",\"recap\":\"...\"}.",
    "alert: at most 2 short sentences for the lock screen. recap: at most 3 short sentences for in-app.",
    "Tone: friendly nudge about being ahead, behind, tied, or needing a walk/sync — not a stats dump.",
    "Never include numbers, step counts, ranks, names, handles, fight titles, money, or currency symbols.",
    "Never mention winning money or wagers.",
  ].join(" ");
}

function userPrompt(context: DailyStatusPromptContext): string {
  return JSON.stringify(context);
}

export async function generateDailyStatusCopy(
  context: DailyStatusPromptContext,
): Promise<{ alert: string; recap: string }> {
  const apiKey = process.env.OPENROUTER_API_KEY?.trim();
  if (!apiKey) {
    throw new Error("OPENROUTER_API_KEY is not set");
  }

  const response = await fetch(OPENROUTER_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "HTTP-Referer": process.env.FITFIGHT_APP_URL ?? "https://fitfight.app",
      "X-Title": "FitFight",
    },
    body: JSON.stringify({
      model: MODEL,
      temperature: 0.6,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: systemPrompt(context.locale) },
        { role: "user", content: userPrompt(context) },
      ],
    }),
  });

  if (!response.ok) {
    throw new Error(`OpenRouter request failed (${response.status})`);
  }

  const payload = await response.json() as {
    choices?: Array<{ message?: { content?: string } }>;
  };
  const content = payload.choices?.[0]?.message?.content;
  if (!content) {
    throw new Error("OpenRouter returned no content");
  }

  const parsed = dailyStatusModelResponseSchema.parse(JSON.parse(content));
  return {
    alert: sanitizeCopy(parsed.alert),
    recap: sanitizeCopy(parsed.recap),
  };
}

function sanitizeCopy(text: string): string {
  return text.replace(/\s+/g, " ").trim();
}
