import { z } from "zod";

export const iosInstallChannelValues = ["testflight", "appStore"] as const;
export const iosInstallChannelSchema = z.enum(iosInstallChannelValues);

export const iosInstallSchema = z.object({
  channel: iosInstallChannelSchema,
  url: z.string().url(),
  appStoreId: z.string().regex(/^[0-9]+$/).nullable(),
});

export type IosInstallChannel = z.infer<typeof iosInstallChannelSchema>;
export type IosInstall = z.infer<typeof iosInstallSchema>;
