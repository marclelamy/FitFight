import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { InviteDownload } from "@/components/testflight-invite";
import { referralCodeSchema } from "@/lib/types/referrals/referral";

export const metadata: Metadata = {
  title: "Your friend invited you | FitFight",
  description: "Join your friend on FitFight and challenge each other to walk more.",
  robots: { index: false, follow: false },
};

export default async function ReferralPage({ params }: { params: Promise<{ code: string }> }) {
  const parsed = referralCodeSchema.safeParse((await params).code);
  if (!parsed.success) notFound();

  return (
    <main className="legal-page">
      <header className="legal-header">
        <Link className="brand" href="/" aria-label="FitFight home">
          <span className="brand-mark">FF</span>
          <span>FitFight</span>
        </Link>
      </header>
      <article className="legal-content">
        <p className="eyebrow">INVITED BY A FRIEND</p>
        <h1>Walk more. Together.</h1>
        <p className="legal-intro">
          Your friend invited you to FitFight. Challenge each other to walk more,
          compare Steps, and make every day count.
        </p>
        <InviteDownload />
      </article>
    </main>
  );
}
