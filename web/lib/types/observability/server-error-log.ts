import { z } from "zod";

export const serverErrorLogInsertSchema = z.object({
  user_id: z.string().uuid().nullable(),
  method: z.string().min(1).max(16),
  path: z.string().min(1).max(2048),
  action: z.string().min(1).max(512),
  route_params: z.record(z.string().max(256)),
  status: z.number().int().min(100).max(599),
  error_code: z.string().min(1).max(64),
  failure: z.string().min(1).max(8000),
  trace: z.record(z.unknown()),
  app_version: z.string().max(32).nullable(),
  app_build: z.string().max(16).nullable(),
  request_trace_id: z.string().uuid().nullable(),
});

export type ServerErrorLogInsert = z.infer<typeof serverErrorLogInsertSchema>;
