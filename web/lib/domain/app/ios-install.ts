import { z } from "zod";

import { iosInstallSchema, type IosInstall } from "@/lib/types/app/ios-install";

const testFlightInviteURL = "https://testflight.apple.com/join/wcZKdwVZ";
const appStoreURLSchema = z.string().url();
const appStoreIdSchema = z.string().regex(/^[0-9]+$/);

export function iosInstall(host: string): IosInstall {
  const hostname = host.split(",")[0]?.trim().toLowerCase().replace(/:\d+$/, "") ?? "";
  const appStoreURL = appStoreURLSchema.safeParse(
    process.env.NEXT_PUBLIC_IOS_APP_STORE_URL?.trim(),
  );
  const appStoreId = appStoreIdSchema.safeParse(
    process.env.NEXT_PUBLIC_IOS_APP_STORE_ID?.trim(),
  );
  const onProductionSite = hostname === "fitfight.app" || hostname === "www.fitfight.app";
  if (onProductionSite && appStoreURL.success) {
    return iosInstallSchema.parse({
      channel: "appStore",
      url: appStoreURL.data,
      appStoreId: appStoreId.success ? appStoreId.data : null,
    });
  }
  return iosInstallSchema.parse({
    channel: "testflight",
    url: testFlightInviteURL,
    appStoreId: null,
  });
}
