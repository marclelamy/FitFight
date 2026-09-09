import { z } from "zod";
import { mediaObjectSchema } from "@/lib/types/media/media";

export const fightPostAuthorSchema = z.object({
  user_id: z.string().uuid(),
  handle: z.string(),
  display_name: z.string(),
  avatar: mediaObjectSchema.nullable(),
}).strict();

export const fightPostSchema = z.object({
  id: z.string().uuid(),
  fight_id: z.string().uuid(),
  fight_name: z.string(),
  body: z.string(),
  created_at: z.string().datetime({ offset: true }),
  author: fightPostAuthorSchema,
  media: z.array(mediaObjectSchema),
  mine: z.boolean(),
}).strict();

export const fightPostListResponseSchema = z.object({
  posts: z.array(fightPostSchema),
  next_cursor: z.string().nullable(),
}).strict();

export const fightPostResponseSchema = z.object({
  post: fightPostSchema,
}).strict();

export const createFightPostRequestSchema = z.object({
  body: z.string().trim().max(500).default(""),
  media_ids: z.array(z.string().uuid()).max(4).default([]),
}).strict().refine((input) => input.body.length > 0 || input.media_ids.length > 0, {
  message: "Add a photo or a short note",
});

export const listFightPostsQuerySchema = z.object({
  cursor: z.string().min(1).max(120).optional(),
  limit: z.coerce.number().int().min(1).max(50).default(30),
}).strict();

export const fightPostReportReasonValues = ["spam", "abuse", "other"] as const;
export const fightPostReportReasonSchema = z.enum(fightPostReportReasonValues);

export const reportFightPostRequestSchema = z.object({
  reason: fightPostReportReasonSchema,
}).strict();

export const reportFightPostResponseSchema = z.object({
  reported: z.literal(true),
}).strict();

export const blockFeedAuthorRequestSchema = z.object({
  user_id: z.string().uuid(),
}).strict();

export const blockFeedAuthorResponseSchema = z.object({
  blocked: z.literal(true),
}).strict();

export type FightPostAuthor = z.infer<typeof fightPostAuthorSchema>;
export type FightPost = z.infer<typeof fightPostSchema>;
export type FightPostListResponse = z.infer<typeof fightPostListResponseSchema>;
export type FightPostResponse = z.infer<typeof fightPostResponseSchema>;
export type CreateFightPostRequest = z.infer<typeof createFightPostRequestSchema>;
export type ListFightPostsQuery = z.infer<typeof listFightPostsQuerySchema>;
export type FightPostReportReason = z.infer<typeof fightPostReportReasonSchema>;
export type ReportFightPostRequest = z.infer<typeof reportFightPostRequestSchema>;
export type ReportFightPostResponse = z.infer<typeof reportFightPostResponseSchema>;
export type BlockFeedAuthorRequest = z.infer<typeof blockFeedAuthorRequestSchema>;
export type BlockFeedAuthorResponse = z.infer<typeof blockFeedAuthorResponseSchema>;
