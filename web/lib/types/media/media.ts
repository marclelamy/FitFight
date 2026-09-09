import { z } from "zod";

export const mediaKindValues = ["photo", "video"] as const;
export const mediaKindSchema = z.enum(mediaKindValues);

export const mediaPurposeValues = ["profile", "fight_post"] as const;
export const mediaPurposeSchema = z.enum(mediaPurposeValues);

export const mediaStatusValues = ["pending", "ready", "rejected"] as const;
export const mediaStatusSchema = z.enum(mediaStatusValues);

export const mediaContentTypeValues = ["image/jpeg", "image/png", "image/webp"] as const;
export const mediaContentTypeSchema = z.enum(mediaContentTypeValues);

export const mediaObjectSchema = z.object({
  id: z.string().uuid(),
  kind: mediaKindSchema,
  purpose: mediaPurposeSchema,
  status: mediaStatusSchema,
  original_filename: z.string(),
  content_type: mediaContentTypeSchema,
  byte_size: z.number().int().positive(),
  width: z.number().int().positive(),
  height: z.number().int().positive(),
  duration_ms: z.number().int().positive().nullable(),
  sha256: z.string().regex(/^[0-9a-f]{64}$/),
  url: z.string().url().nullable(),
  created_at: z.string().datetime({ offset: true }),
}).strict();

export const createMediaUploadRequestSchema = z.object({
  purpose: mediaPurposeSchema,
  original_filename: z.string().trim().min(1).max(200)
    .refine((value) => !value.includes("/") && !value.includes("\\"), "Filename cannot include a path"),
  content_type: mediaContentTypeSchema,
  byte_size: z.number().int().min(1).max(8_388_608),
  width: z.number().int().min(1).max(8192),
  height: z.number().int().min(1).max(8192),
  sha256: z.string().regex(/^[0-9a-f]{64}$/),
}).strict();

export const mediaUploadResponseSchema = z.object({
  media: mediaObjectSchema,
  upload: z.object({
    url: z.string().url(),
    token: z.string().min(1),
    method: z.literal("PUT"),
  }).strict(),
}).strict();

export const mediaResponseSchema = z.object({
  media: mediaObjectSchema,
}).strict();

export type MediaKind = z.infer<typeof mediaKindSchema>;
export type MediaPurpose = z.infer<typeof mediaPurposeSchema>;
export type MediaStatus = z.infer<typeof mediaStatusSchema>;
export type MediaObject = z.infer<typeof mediaObjectSchema>;
export type CreateMediaUploadRequest = z.infer<typeof createMediaUploadRequestSchema>;
export type MediaUploadResponse = z.infer<typeof mediaUploadResponseSchema>;
export type MediaResponse = z.infer<typeof mediaResponseSchema>;
