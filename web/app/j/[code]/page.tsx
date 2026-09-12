import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { InviteDownload } from "@/components/testflight-invite";
import { isJoinCode, normalizeJoinCode } from "@/lib/domain/fights/join-code";

export const metadata: Metadata = {
  title: "Join a fight | FitFight",
  description: "Open this invite link in FitFight to join, even if the fight is private.",
  robots: { index: false, follow: false },
};

export default async function JoinPage({ params }: { params: Promise<{ code: string }> }) {
  const { code } = await params;
  const display = normalizeJoinCode(code);
  if (!isJoinCode(display)) notFound();

  return (
    <main className="legal-page">
      <header className="legal-header">
        <Link className="brand" href="/" aria-label="FitFight home">
          <span className="brand-mark">FF</span>
          <span>FitFight</span>
        </Link>
      </header>
      <article className="legal-content">
        <p className="eyebrow">JOIN A FIGHT</p>
        <h1>Open this fight in FitFight</h1>
        <p className="legal-intro">
          Code <strong>{display}</strong>. Open this invite link in FitFight to join,
          even if the fight is private. Scores stay in the app.
        </p>
        <InviteDownload />
      </article>
    </main>
  );
}
