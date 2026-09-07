import type { Metadata } from "next";
import { headers } from "next/headers";
import Link from "next/link";

import { iosInstall } from "@/lib/domain/app/ios-install";
import { isJoinCode, normalizeJoinCode } from "@/lib/domain/fights/join-code";

type JoinPageProps = {
  params: Promise<{ code: string }>;
};

export async function generateMetadata({ params }: JoinPageProps): Promise<Metadata> {
  const { code } = await params;
  const display = normalizeJoinCode(code);
  const headerList = await headers();
  const install = iosInstall(headerList.get("x-forwarded-host") ?? headerList.get("host") ?? "");
  return {
    title: `Join ${display} | FitFight`,
    description: "Get FitFight and join this fight on iPhone.",
    robots: { index: false, follow: false },
    itunes:
      install.channel === "appStore" && install.appStoreId
        ? {
            appId: install.appStoreId,
            appArgument: `https://fitfight.app/j/${display}`,
          }
        : undefined,
  };
}

export default async function JoinPage({ params }: JoinPageProps) {
  const { code } = await params;
  const display = normalizeJoinCode(code);
  const valid = isJoinCode(display);
  const headerList = await headers();
  const install = iosInstall(headerList.get("x-forwarded-host") ?? headerList.get("host") ?? "");
  let afterInstall: string;
  switch (install.channel) {
    case "testflight":
      afterInstall =
        "This opens TestFlight. Install FitFight there, come back to this page, and tap Open in FitFight. You can also type the code under New → Join.";
      break;
    case "appStore":
      afterInstall =
        "This opens the App Store. After FitFight installs, come back to this page and tap Open in FitFight. You can also type the code under New → Join.";
      break;
    default: {
      const _exhaustive: never = install.channel;
      return _exhaustive;
    }
  }

  return (
    <main className="legal-page join-page">
      <header className="legal-header">
        <Link className="brand" href="/" aria-label="FitFight home">
          <span className="brand-mark">FF</span>
          <span>FitFight</span>
        </Link>
      </header>
      <article className="legal-content">
        <p className="eyebrow">JOIN A FIGHT</p>
        <h1>Join this fight in FitFight</h1>
        <p className="join-code" aria-label={valid ? `Fight code ${display}` : "Fight code"}>
          {display || "————"}
        </p>
        <p className="legal-intro">
          {valid
            ? afterInstall
            : "This code is not a FitFight join code. Get the app, then ask your friend for a new link."}
        </p>
        <div className="join-actions">
          <a className="primary-action" href={install.url} rel="noopener noreferrer">
            Get FitFight
          </a>
          {valid ? (
            <a className="text-action" href={`fitfight://j/${display}`}>
              Open in FitFight
            </a>
          ) : null}
        </div>
      </article>
    </main>
  );
}
