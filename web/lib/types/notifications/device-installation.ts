import { z } from "zod";

export const apnsEnvironmentValues = ["sandbox", "production"] as const;
export const notificationLocaleValues = ["en", "fr"] as const;
export const notificationPermissionStatusValues = ["authorized", "denied", "provisional"] as const;

export const apnsEnvironmentSchema = z.enum(apnsEnvironmentValues);
export const notificationLocaleSchema = z.enum(notificationLocaleValues);
export const notificationPermissionStatusSchema = z.enum(notificationPermissionStatusValues);

export const registerDeviceInstallationRequestSchema = z.object({
  token: z.string().regex(/^[0-9a-fA-F]+$/, "token must be hex"),
  apns_environment: apnsEnvironmentSchema,
  locale: notificationLocaleSchema,
  permission_status: notificationPermissionStatusSchema,
}).strict();

export const notificationDeliveryStatusSchema = z.object({
  apns_configured: z.boolean(),
});

export type ApnsEnvironment = z.infer<typeof apnsEnvironmentSchema>;
export type NotificationLocale = z.infer<typeof notificationLocaleSchema>;
export type NotificationPermissionStatus = z.infer<typeof notificationPermissionStatusSchema>;
export type RegisterDeviceInstallationRequest = z.infer<typeof registerDeviceInstallationRequestSchema>;
export type NotificationDeliveryStatus = z.infer<typeof notificationDeliveryStatusSchema>;
