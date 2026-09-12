import { z } from "zod";
import { mediaObjectSchema } from "@/lib/types/media/media";

export const feedAudienceValues = ["fight", "main"] as const;
export const feedAudienceSchema = z.enum(feedAudienceValues);

export const feedScopeValues = ["all", "main"] as const;
export const feedScopeSchema = z.enum(feedScopeValues);

export const fightPostAuthorSchema = z.object({
  user_id: z.string().uuid(),
  handle: z.string(),
  display_name: z.string(),
  avatar: mediaObjectSchema.nullable(),
}).strict();

export const fightPostTagSchema = z.object({
  user_id: z.string().uuid(),
  handle: z.string(),
  display_name: z.string(),
}).strict();

export const fightPostReactionSchema = z.object({
  emoji: z.string(),
  count: z.number().int().min(1),
  mine: z.boolean(),
}).strict();

export const fightPostSchema = z.object({
  id: z.string().uuid(),
  audience: feedAudienceSchema,
  fight_id: z.string().uuid().nullable(),
  fight_name: z.string(),
  body: z.string(),
  created_at: z.string().datetime({ offset: true }),
  author: fightPostAuthorSchema,
  media: z.array(mediaObjectSchema),
  tags: z.array(fightPostTagSchema),
  reactions: z.array(fightPostReactionSchema),
  comment_count: z.number().int().min(0),
  mine: z.boolean(),
}).strict();

export const fightPostListResponseSchema = z.object({
  posts: z.array(fightPostSchema),
  next_cursor: z.string().nullable(),
}).strict();

export const fightPostResponseSchema = z.object({
  post: fightPostSchema,
}).strict();

export const fightPostBatchResponseSchema = z.object({
  posts: z.array(fightPostSchema),
}).strict();

export const createFightPostRequestSchema = z.object({
  body: z.string().trim().max(500).default(""),
  media_ids: z.array(z.string().uuid()).max(4).default([]),
}).strict().refine((input) => input.body.length > 0 || input.media_ids.length > 0, {
  message: "Add a photo, a video, or a short note",
});

export const feedDestinationSchema = z.discriminatedUnion("type", [
  z.object({ type: z.literal("main") }).strict(),
  z.object({
    type: z.literal("fight"),
    fight_id: z.string().uuid(),
  }).strict(),
]);

export const createFeedPostsRequestSchema = z.object({
  body: z.string().trim().max(500).default(""),
  media_ids: z.array(z.string().uuid()).max(4).default([]),
  destinations: z.array(feedDestinationSchema).min(1).max(50),
  tagged_user_ids: z.array(z.string().uuid()).max(20).default([]),
}).strict().refine((input) => input.body.length > 0 || input.media_ids.length > 0, {
  message: "Add a photo, a video, or a short note",
});

export const listFightPostsQuerySchema = z.object({
  cursor: z.string().min(1).max(120).optional(),
  limit: z.coerce.number().int().min(1).max(50).default(30),
  scope: feedScopeSchema.optional(),
}).strict();

export const listFeedPeopleQuerySchema = z.object({
  main: z.enum(["true", "1"]).optional(),
  fight_ids: z.string().max(2500).optional(),
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

export const feedPersonSchema = z.object({
  user_id: z.string().uuid(),
  handle: z.string(),
  display_name: z.string(),
  avatar: mediaObjectSchema.nullable(),
}).strict();

export const feedPeopleResponseSchema = z.object({
  people: z.array(feedPersonSchema),
}).strict();

export const fightPostCommentSchema = z.object({
  id: z.string().uuid(),
  post_id: z.string().uuid(),
  parent_id: z.string().uuid().nullable(),
  body: z.string(),
  created_at: z.string().datetime({ offset: true }),
  author: fightPostAuthorSchema,
  mine: z.boolean(),
}).strict();

export const fightPostCommentListResponseSchema = z.object({
  comments: z.array(fightPostCommentSchema),
  next_cursor: z.string().nullable(),
}).strict();

export const fightPostCommentResponseSchema = z.object({
  comment: fightPostCommentSchema,
}).strict();

export const createFightPostCommentRequestSchema = z.object({
  body: z.string().trim().min(1).max(500),
  parent_id: z.string().uuid().nullable().optional(),
}).strict();

export const listFightPostCommentsQuerySchema = z.object({
  cursor: z.string().min(1).max(120).optional(),
  limit: z.coerce.number().int().min(1).max(80).default(40),
}).strict();

export const reportFightPostCommentRequestSchema = z.object({
  reason: fightPostReportReasonSchema,
}).strict();

export const reportFightPostCommentResponseSchema = z.object({
  reported: z.literal(true),
}).strict();

export const setFightPostReactionRequestSchema = z.object({
  emoji: z.string().trim().min(1).max(16).refine((value) => {
    const segments = [...new Intl.Segmenter("en", { granularity: "grapheme" }).segment(value)];
    return segments.length === 1 && /\p{Extended_Pictographic}/u.test(value);
  }, "Pick one emoji"),
}).strict();

export const fightPostReactionResponseSchema = z.object({
  reactions: z.array(fightPostReactionSchema),
}).strict();

export type FeedAudience = z.infer<typeof feedAudienceSchema>;
export type FeedScope = z.infer<typeof feedScopeSchema>;
export type FightPostAuthor = z.infer<typeof fightPostAuthorSchema>;
export type FightPostTag = z.infer<typeof fightPostTagSchema>;
export type FightPostReaction = z.infer<typeof fightPostReactionSchema>;
export type FightPost = z.infer<typeof fightPostSchema>;
export type FightPostListResponse = z.infer<typeof fightPostListResponseSchema>;
export type FightPostResponse = z.infer<typeof fightPostResponseSchema>;
export type FightPostBatchResponse = z.infer<typeof fightPostBatchResponseSchema>;
export type CreateFightPostRequest = z.infer<typeof createFightPostRequestSchema>;
export type FeedDestination = z.infer<typeof feedDestinationSchema>;
export type CreateFeedPostsRequest = z.infer<typeof createFeedPostsRequestSchema>;
export type ListFightPostsQuery = z.infer<typeof listFightPostsQuerySchema>;
export type ListFeedPeopleQuery = z.infer<typeof listFeedPeopleQuerySchema>;
export type FightPostReportReason = z.infer<typeof fightPostReportReasonSchema>;
export type ReportFightPostRequest = z.infer<typeof reportFightPostRequestSchema>;
export type ReportFightPostResponse = z.infer<typeof reportFightPostResponseSchema>;
export type BlockFeedAuthorRequest = z.infer<typeof blockFeedAuthorRequestSchema>;
export type BlockFeedAuthorResponse = z.infer<typeof blockFeedAuthorResponseSchema>;
export type FeedPerson = z.infer<typeof feedPersonSchema>;
export type FeedPeopleResponse = z.infer<typeof feedPeopleResponseSchema>;
export type FightPostComment = z.infer<typeof fightPostCommentSchema>;
export type FightPostCommentListResponse = z.infer<typeof fightPostCommentListResponseSchema>;
export type FightPostCommentResponse = z.infer<typeof fightPostCommentResponseSchema>;
export type CreateFightPostCommentRequest = z.infer<typeof createFightPostCommentRequestSchema>;
export type ListFightPostCommentsQuery = z.infer<typeof listFightPostCommentsQuerySchema>;
export type ReportFightPostCommentRequest = z.infer<typeof reportFightPostCommentRequestSchema>;
export type ReportFightPostCommentResponse = z.infer<typeof reportFightPostCommentResponseSchema>;
export type SetFightPostReactionRequest = z.infer<typeof setFightPostReactionRequestSchema>;
export type FightPostReactionResponse = z.infer<typeof fightPostReactionResponseSchema>;
