import { z } from "zod";

export const appReleaseSchema = z.object({
  version: z.string().regex(/^\d+\.\d+\.\d+$/),
  build: z.number().int().positive().safe(),
  update_url: z.union([
    z.literal("itms-beta://"),
    z.string().regex(/^https:\/\/apps\.apple\.com\/app\/id\d+$/),
  ]),
});

export const appReleasePolicySchema = z.object({
  latest: appReleaseSchema.nullable(),
  review: appReleaseSchema.nullable(),
  enforced: z.boolean(),
});

export const appReleaseManifestSchema = z.object({
  staging: appReleasePolicySchema.extend({
    latest: appReleaseSchema.extend({ update_url: z.literal("itms-beta://") }).nullable(),
    review: appReleaseSchema.extend({ update_url: z.literal("itms-beta://") }).nullable(),
  }),
  prod: appReleasePolicySchema.extend({
    latest: appReleaseSchema.extend({
      update_url: z.string().regex(/^https:\/\/apps\.apple\.com\/app\/id\d+$/),
    }).nullable(),
    review: appReleaseSchema.extend({
      update_url: z.string().regex(/^https:\/\/apps\.apple\.com\/app\/id\d+$/),
    }).nullable(),
  }),
});

export const appReleaseProjectValues = [
  "https://zstzbfocunthczzubggz.supabase.co",
  "https://pvqntpteehdvhqyctwum.supabase.co",
] as const;
export const appReleaseProjectSchema = z.enum(appReleaseProjectValues);

export type AppRelease = z.infer<typeof appReleaseSchema>;
export type AppReleasePolicy = z.infer<typeof appReleasePolicySchema>;
export type AppReleaseManifest = z.infer<typeof appReleaseManifestSchema>;
export type AppReleaseProject = z.infer<typeof appReleaseProjectSchema>;
