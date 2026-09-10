import { z } from "zod";

export const feedbackKindValues = ["bug", "feature"] as const;
export const feedbackKindSchema = z.enum(feedbackKindValues);

export const createFeedbackPostRequestSchema = z
  .object({
    kind: feedbackKindSchema,
    title: z.string().trim().min(1).max(80),
    body: z.string().trim().min(1).max(2000),
  })
  .strict();

export const createFeedbackCommentRequestSchema = z
  .object({
    body: z.string().trim().min(2).max(500),
  })
  .strict();

export const listFeedbackQuerySchema = z
  .object({
    kind: feedbackKindSchema.optional(),
  })
  .strict();

export const feedbackPostSummarySchema = z
  .object({
    id: z.string().uuid(),
    kind: feedbackKindSchema,
    title: z.string(),
    body: z.string(),
    vote_count: z.number().int(),
    comment_count: z.number().int(),
    voted: z.boolean(),
    author_handle: z.string(),
    created_at: z.string().datetime(),
  })
  .strict();

export const feedbackCommentSchema = z
  .object({
    id: z.string().uuid(),
    body: z.string(),
    author_handle: z.string(),
    created_at: z.string().datetime(),
  })
  .strict();

export const feedbackListResponseSchema = z
  .object({
    posts: z.array(feedbackPostSummarySchema),
  })
  .strict();

export const feedbackPostResponseSchema = z
  .object({
    post: feedbackPostSummarySchema,
  })
  .strict();

export const feedbackDetailResponseSchema = z
  .object({
    post: feedbackPostSummarySchema,
    comments: z.array(feedbackCommentSchema),
  })
  .strict();

export const feedbackVoteResponseSchema = z
  .object({
    voted: z.boolean(),
    vote_count: z.number().int(),
  })
  .strict();

export const feedbackCommentResponseSchema = z
  .object({
    comment: feedbackCommentSchema,
  })
  .strict();

export type FeedbackKind = z.infer<typeof feedbackKindSchema>;
export type CreateFeedbackPostRequest = z.infer<typeof createFeedbackPostRequestSchema>;
export type CreateFeedbackCommentRequest = z.infer<typeof createFeedbackCommentRequestSchema>;
export type ListFeedbackQuery = z.infer<typeof listFeedbackQuerySchema>;
export type FeedbackPostSummary = z.infer<typeof feedbackPostSummarySchema>;
export type FeedbackComment = z.infer<typeof feedbackCommentSchema>;
export type FeedbackListResponse = z.infer<typeof feedbackListResponseSchema>;
export type FeedbackPostResponse = z.infer<typeof feedbackPostResponseSchema>;
export type FeedbackDetailResponse = z.infer<typeof feedbackDetailResponseSchema>;
export type FeedbackVoteResponse = z.infer<typeof feedbackVoteResponseSchema>;
export type FeedbackCommentResponse = z.infer<typeof feedbackCommentResponseSchema>;
