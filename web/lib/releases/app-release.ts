import { ApiError } from "@/lib/http";
import {
  appReleaseManifestSchema,
  appReleaseProjectSchema,
  type AppReleasePolicy,
} from "@/lib/types/releases/app-release";

export async function appReleasePolicy(): Promise<AppReleasePolicy> {
  const project = appReleaseProjectSchema.safeParse(process.env.NEXT_PUBLIC_SUPABASE_URL?.replace(/\/$/, ""));
  if (!project.success) {
    throw new ApiError(503, "config", "App release environment is not configured");
  }

  let response: Response;
  let payload: unknown;
  try {
    response = await fetch(
      `https://raw.githubusercontent.com/slooowshutter/FitFight/testflight-latest/releases.json?check=${Date.now()}`,
      { cache: "no-store", signal: AbortSignal.timeout(8_000) },
    );
    if (!response.ok) {
      throw new Error("Release manifest is unavailable");
    }
    payload = await response.json();
  } catch {
    throw new ApiError(503, "release_unavailable", "Could not check the latest app release");
  }

  const parsed = appReleaseManifestSchema.safeParse(payload);
  if (!parsed.success) {
    throw new ApiError(503, "release_unavailable", "Could not read the latest app release");
  }
  return project.data === "https://zstzbfocunthczzubggz.supabase.co" ? parsed.data.staging : parsed.data.prod;
}

export async function requireLatestAppRelease(request: Request): Promise<void> {
  const policy = await appReleasePolicy();
  // Existing binaries cannot send these headers until the first gated release is installable.
  if (!policy.enforced) return;
  const version = request.headers.get("x-fitfight-version");
  const build = request.headers.get("x-fitfight-build");
  if (![policy.latest, policy.review].some((release) => release
    && version === release.version && build === String(release.build))) {
    throw new ApiError(426, "update_required", "Update FitFight to continue");
  }
}
