import { connect, type ClientHttp2Session } from "node:http2";
import { readApnsEnvironment } from "./apns-config";
import { createApnsProviderToken } from "./apns-jwt";

export type ApnsSendInput = {
  deviceToken: string;
  environment: "sandbox" | "production";
  topic: string;
  title: string;
  body: string;
  route: string;
};

export type ApnsSendResult = {
  httpStatus: number;
  reason: string | null;
  apnsId: string | null;
  unregistered: boolean;
  retryLater: boolean;
  invalidProviderToken: boolean;
};

function apnsHost(environment: "sandbox" | "production"): string {
  return environment === "production"
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com";
}

function sendOnSession(
  session: ClientHttp2Session,
  input: ApnsSendInput,
  providerToken: string,
): Promise<ApnsSendResult> {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify({
      aps: {
        alert: { title: input.title, body: input.body },
        sound: "default",
      },
      fitfight: { route: input.route },
    });
    const request = session.request({
      ":method": "POST",
      ":path": `/3/device/${input.deviceToken}`,
      authorization: `bearer ${providerToken}`,
      "apns-topic": input.topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
    });
    let responseStatus = 0;
    let reason: string | null = null;
    let apnsId: string | null = null;
    request.on("response", (headers) => {
      responseStatus = Number(headers[":status"] ?? 0);
      const headerReason = headers["apns-reason"];
      apnsId = typeof headers["apns-id"] === "string" ? headers["apns-id"] : null;
      reason = typeof headerReason === "string" ? headerReason : null;
    });
    const chunks: Buffer[] = [];
    request.on("data", (chunk: Buffer) => {
      chunks.push(chunk);
    });
    request.on("end", () => {
      if (!reason && chunks.length > 0) {
        try {
          const parsed = JSON.parse(Buffer.concat(chunks).toString("utf8")) as { reason?: string };
          reason = parsed.reason ?? reason;
        } catch {
          // APNs sometimes returns an empty body on success.
        }
      }
      resolve({
        httpStatus: responseStatus,
        reason,
        apnsId,
        unregistered: responseStatus === 410
          || reason === "Unregistered"
          || reason === "BadDeviceToken"
          || reason === "DeviceTokenNotForTopic",
        retryLater: responseStatus === 429 || responseStatus === 503,
        invalidProviderToken: responseStatus === 403 && reason === "InvalidProviderToken",
      });
    });
    request.on("error", reject);
    request.end(payload);
  });
}

export async function sendApnsAlert(input: ApnsSendInput): Promise<ApnsSendResult> {
  const environment = readApnsEnvironment();
  if (!environment) {
    throw new Error("APNs credentials are not configured");
  }
  const providerToken = createApnsProviderToken(environment);
  const session = connect(apnsHost(input.environment));
  try {
    return await sendOnSession(session, input, providerToken);
  } finally {
    session.close();
  }
}
