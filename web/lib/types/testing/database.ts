import { z } from "zod";

export const databaseTestEnvironmentSchema = z.object({
  CI: z.literal("true"),
  DATABASE_URL: z.string().url().refine((value) => ["localhost", "127.0.0.1"].includes(new URL(value).hostname)),
  SUPABASE_TEST_URL: z.string().url().refine((value) => ["localhost", "127.0.0.1"].includes(new URL(value).hostname)),
  SUPABASE_TEST_ANON_KEY: z.string().min(1),
  SUPABASE_TEST_SERVICE_KEY: z.string().min(1),
  SUPABASE_CLIENT_ACCESS_CLOSED: z.enum(["true", "false"]).transform((value) => value === "true"),
});

export type DatabaseTestEnvironment = z.infer<typeof databaseTestEnvironmentSchema>;
