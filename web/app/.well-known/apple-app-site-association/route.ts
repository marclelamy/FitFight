import { NextResponse } from "next/server";

const association = {
  applinks: {
    apps: [],
    details: [
      {
        appID: "C92DPD8ME2.com.fitfight.mvp",
        appIDs: ["C92DPD8ME2.com.fitfight.mvp"],
        paths: ["/j/*", "/r/*", "/fights/*"],
        components: [{ "/": "/j/*" }, { "/": "/r/*" }, { "/": "/fights/*" }],
      },
    ],
  },
};

export const runtime = "nodejs";
export const dynamic = "force-static";

export function GET() {
  return NextResponse.json(association, {
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "public, max-age=3600",
    },
  });
}
