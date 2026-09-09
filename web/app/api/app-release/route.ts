import { apiRoute, corsPreflight, json } from "@/lib/http";
import { appReleasePolicy } from "@/lib/releases/app-release";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const OPTIONS = corsPreflight;
export const GET = apiRoute(async () => json(await appReleasePolicy()));
