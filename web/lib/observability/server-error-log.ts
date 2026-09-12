import { requestTraceIdSchema } from "@/lib/types/observability/request-timing";
import {
  serverErrorLogInsertSchema,
  type ServerErrorLogInsert,
} from "@/lib/types/observability/server-error-log";

const SECRET_ENV_KEYS = [
  "APPLE_SIGN_IN_PRIVATE_KEY",
  "APPLE_SIGN_IN_TOKEN_ENCRYPTION_KEY",
  "APNS_PRIVATE_KEY",
  "APNS_TOKEN_ENCRYPTION_KEY",
  "CRON_SECRET",
  "CURSOR_API_KEY",
  "DATABASE_URL",
  "FITFIGHT_CRON_SECRET",
  "NOTION_TOKEN",
  "OPENROUTER_API_KEY",
  "SUPABASE_DB_URL",
  "SUPABASE_SECRET_KEY",
  "SUPABASE_SERVICE_ROLE_KEY",
] as const;

const REDACTED_KEY = /^(authorization|password|secret|token|private_key|privatekey|api_key|apikey|access_token|refresh_token|cursor_api_key|service_role)$/i;
const BEARER_OR_BASIC = /\b(?:Bearer|Basic)\s+\S+/gi;
const PEM_BLOCK = /-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g;
const SB_SECRET = /\bsb_secret_[A-Za-z0-9]+/g;

type ServerErrorLogWriter = (row: ServerErrorLogInsert) => Promise<void>;

let writer: ServerErrorLogWriter | null = null;

export function setServerErrorLogWriter(next: ServerErrorLogWriter | null): void {
  writer = next;
}

export function redactSecrets(value: unknown, depth = 0, seen = new WeakSet<object>()): unknown {
  if (typeof value === "string") {
    let next = value.replace(PEM_BLOCK, "[redacted-pem]").replace(SB_SECRET, "[redacted]").replace(BEARER_OR_BASIC, (match) => (
      match.startsWith("Bearer") ? "Bearer [redacted]" : "Basic [redacted]"
    ));
    for (const name of SECRET_ENV_KEYS) {
      const secret = process.env[name];
      if (secret && secret.length >= 8 && next.includes(secret)) {
        next = next.split(secret).join("[redacted]");
      }
    }
    return next.length <= 16_000 ? next : `${next.slice(0, 16_000)}…`;
  }
  if (value === null || typeof value !== "object") {
    return value;
  }
  if (seen.has(value)) {
    return "[circular]";
  }
  if (depth >= 6) {
    return "[truncated]";
  }
  seen.add(value);
  if (Array.isArray(value)) {
    return value.map((item) => redactSecrets(item, depth + 1, seen));
  }
  return Object.fromEntries(Object.entries(value as Record<string, unknown>).map(([key, item]) => (
    REDACTED_KEY.test(key) ? [key, "[redacted]"] : [key, redactSecrets(item, depth + 1, seen)]
  )));
}

export function serverErrorLogEntry(
  error: unknown,
  input: { request: Request; params: Record<string, string>; status: number },
): ServerErrorLogInsert | null {
  if (input.status < 500) {
    return null;
  }
  const api = apiErrorFields(error);
  const postgres = postgresFields(error);
  const upstream = api?.detail && typeof api.detail === "object"
    ? (api.detail as { upstream?: { status?: unknown } }).upstream
    : undefined;
  const failure = (
    postgres?.message
    ?? (api && typeof upstream?.status === "number" ? `${api.message} (upstream ${upstream.status})` : null)
    ?? (error instanceof Error ? error.message : String(error))
  ).slice(0, 8000);
  let path = "/";
  try {
    path = new URL(input.request.url).pathname || "/";
  } catch {
    path = "/";
  }
  const method = (input.request.method || "GET").slice(0, 16);
  let actionPath = path;
  for (const [name, value] of Object.entries(input.params)
    .filter(([, value]) => value.length > 0)
    .sort((left, right) => right[1].length - left[1].length)) {
    actionPath = actionPath.replaceAll(value, `:${name}`);
  }
  const version = input.request.headers.get("x-fitfight-version");
  const build = input.request.headers.get("x-fitfight-build");
  const traceId = requestTraceIdSchema.safeParse(input.request.headers.get("x-fitfight-trace-id"));
  const cause = error instanceof Error ? error.cause : undefined;
  const trace = redactSecrets({
    name: error instanceof Error ? error.name : typeof error,
    message: error instanceof Error ? error.message : String(error),
    stack: error instanceof Error ? error.stack : undefined,
    cause: cause instanceof Error
      ? { name: cause.name, message: cause.message, stack: cause.stack, postgres: postgresFields(cause) }
      : cause,
    postgres,
    detail: api?.detail,
  });
  return serverErrorLogInsertSchema.parse({
    user_id: userIdFromAuthorization(input.request),
    method,
    path,
    action: `${method} ${actionPath}`.slice(0, 512),
    route_params: input.params,
    status: input.status,
    error_code: api?.code ?? "internal",
    failure: failure.length > 0 ? failure : "Internal error",
    trace: trace && typeof trace === "object" && !Array.isArray(trace) ? trace : { value: trace },
    app_version: version && /^\d{1,6}\.\d{1,6}\.\d{1,6}$/.test(version) ? version : null,
    app_build: build && /^\d{1,10}$/.test(build) ? build : null,
    request_trace_id: traceId.success ? traceId.data : null,
  });
}

export async function recordApiFailure(
  request: Request,
  error: unknown,
  input: { params: Record<string, string>; status: number },
): Promise<void> {
  let row: ServerErrorLogInsert | null;
  try {
    row = serverErrorLogEntry(error, { request, ...input });
  } catch (logError) {
    console.error("fitfight_server_error_log_failed", logError instanceof Error ? logError.name : "unknown");
    return;
  }
  if (!row) {
    return;
  }
  console.error("fitfight_server_error", JSON.stringify({
    action: row.action,
    status: row.status,
    error_code: row.error_code,
    failure: row.failure,
    user_id: row.user_id,
  }));
  try {
    if (writer) {
      await writer(row);
      return;
    }
    // NOTE: load the query only when persisting a 5xx so http.ts never imports postgres at module load.
    const { insertServerErrorLog } = await import("@/lib/supabase/queries/server-error-logs-supabase-query");
    await insertServerErrorLog(row);
  } catch (logError) {
    console.error("fitfight_server_error_log_failed", logError instanceof Error ? logError.name : "unknown");
  }
}

function apiErrorFields(error: unknown): { code: string; message: string; detail: unknown } | null {
  if (!(error instanceof Error) || error.name !== "ApiError") {
    return null;
  }
  const candidate = error as Error & { code?: unknown; detail?: unknown };
  if (typeof candidate.code !== "string" || candidate.code.length === 0) {
    return null;
  }
  return { code: candidate.code, message: candidate.message, detail: candidate.detail };
}

function postgresFields(error: unknown): Record<string, string> | undefined {
  if (!error || typeof error !== "object" || (error instanceof Error && error.name === "ApiError")) {
    return undefined;
  }
  const candidate = error as Record<string, unknown>;
  const fields: Record<string, string> = {};
  for (const key of [
    "code", "detail", "hint", "schema_name", "table_name", "table",
    "column_name", "constraint_name", "where", "severity", "message",
  ]) {
    const value = candidate[key];
    if (typeof value === "string" && value.length > 0) {
      fields[key] = value;
    }
  }
  if (!/^[0-9A-Z]{5}$/.test(fields.code ?? "") && !fields.column_name && !fields.table_name && !fields.schema_name) {
    return undefined;
  }
  return fields;
}

function userIdFromAuthorization(request: Request): string | null {
  const header = request.headers.get("authorization") ?? "";
  const match = /^Bearer\s+(\S+)/i.exec(header.trim());
  if (!match?.[1]) {
    return null;
  }
  const parts = match[1].split(".");
  if (parts.length < 2) {
    return null;
  }
  try {
    const payload = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8")) as { sub?: unknown };
    if (typeof payload.sub === "string"
      && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(payload.sub)) {
      return payload.sub;
    }
  } catch {
    return null;
  }
  return null;
}
