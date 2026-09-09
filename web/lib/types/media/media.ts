import { z } from "zod";

export const mediaKindValues = ["photo", "video"] as const;
export const mediaKindSchema = z.enum(mediaKindValues);

export const mediaPurposeValues = ["profile", "fight_post"] as const;
export const mediaPurposeSchema = z.enum(mediaPurposeValues);

export const mediaStatusValues = ["pending", "ready", "rejected"] as const;
export const mediaStatusSchema = z.enum(mediaStatusValues);

export const mediaPhotoContentTypeValues = ["image/jpeg", "image/png", "image/webp"] as const;
export const mediaVideoContentTypeValues = ["video/mp4", "video/quicktime"] as const;
export const mediaContentTypeValues = [
  ...mediaPhotoContentTypeValues,
  ...mediaVideoContentTypeValues,
] as const;
export const mediaContentTypeSchema = z.enum(mediaContentTypeValues);

const PHOTO_MAX_BYTES = 8_388_608;
const VIDEO_MAX_BYTES = 52_428_800;

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
  kind: mediaKindSchema.default("photo"),
  original_filename: z.string().trim().min(1).max(200)
    .refine((value) => !value.includes("/") && !value.includes("\\"), "Filename cannot include a path"),
  content_type: mediaContentTypeSchema,
  byte_size: z.number().int().min(1).max(VIDEO_MAX_BYTES),
  width: z.number().int().min(1).max(8192),
  height: z.number().int().min(1).max(8192),
  duration_ms: z.number().int().min(1).max(180_000).nullable().optional(),
  sha256: z.string().regex(/^[0-9a-f]{64}$/),
}).strict().superRefine((input, ctx) => {
  if (input.kind === "photo") {
    if (!(mediaPhotoContentTypeValues as readonly string[]).includes(input.content_type)) {
      ctx.addIssue({ code: "custom", message: "Photos must be JPEG, PNG, or WebP", path: ["content_type"] });
    }
    if (input.byte_size > PHOTO_MAX_BYTES) {
      ctx.addIssue({ code: "custom", message: "Choose a smaller photo", path: ["byte_size"] });
    }
    if (input.duration_ms != null) {
      ctx.addIssue({ code: "custom", message: "Photos cannot have a duration", path: ["duration_ms"] });
    }
    return;
  }
  if (input.purpose !== "fight_post") {
    ctx.addIssue({ code: "custom", message: "Videos can only be posted to a fight", path: ["purpose"] });
  }
  if (!(mediaVideoContentTypeValues as readonly string[]).includes(input.content_type)) {
    ctx.addIssue({ code: "custom", message: "Videos must be MP4 or QuickTime", path: ["content_type"] });
  }
  if (input.duration_ms == null) {
    ctx.addIssue({ code: "custom", message: "Videos need a duration", path: ["duration_ms"] });
  }
});

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
