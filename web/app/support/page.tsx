import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Support | FitFight",
  description: "Get help with FitFight accounts, Apple Health Steps, Fight invitations, synchronization, and deletion.",
  robots: { index: true, follow: true },
};

export default function SupportPage() {
  return (
    <main className="legal-page">
      <header className="legal-header">
        <Link className="brand" href="/" aria-label="FitFight home">
          <span className="brand-mark">FF</span>
          <span>FitFight</span>
        </Link>
        <nav className="legal-nav" aria-label="Legal and support">
          <Link href="/privacy">Privacy</Link>
          <Link href="/support" aria-current="page">Support</Link>
        </nav>
      </header>

      <article className="legal-content">
        <p className="eyebrow">FITFIGHT SUPPORT</p>
        <h1>How can we help?</h1>
        <p className="legal-intro">
          Email us with your FitFight username, the app version shown at the top of the
          screen, and a short description of what happened.
        </p>
        <a
          className="primary-action legal-email"
          href="mailto:marc@marclamy.com?subject=FitFight%20support"
        >
          Email marc@marclamy.com
        </a>
        <p className="support-safety">
          Never send your Apple ID password, verification code, or raw Apple Health data.
        </p>

        <section>
          <h2>Apple Health Steps</h2>
          <p>
            In FitFight, open <strong>You → Apple Health</strong> to grant read-only
            Apple Health access or retry a sync. The permission sheet may list steps plus
            other movement types. Fights still use Steps. FitFight reads aggregate Steps
            for your active Fight windows and the relevant daily totals shown in Fight
            charts; background updates depend on iOS and may not be immediate.
          </p>
          <p>
            To revoke access, remove FitFight in Apple Health or iOS Settings. Your score
            may remain incomplete after access is removed.
          </p>
        </section>

        <section>
          <h2>Bugs and feature requests</h2>
          <p>
            Open <strong>You → Settings → Bugs &amp; requests</strong> to post a bug or a
            feature request, see what other signed-in people submitted, upvote, and comment
            with your username. You can still email support for account or Health issues.
          </p>
        </section>

        <section>
          <h2>Inviting someone</h2>
          <p>
            Enter their exact FitFight username when creating a Fight. They must first
            sign in with Apple and choose a username. The invitation then appears in
            their Fights list for acceptance.
          </p>
        </section>

        <section>
          <h2>Scores and Fight timing</h2>
          <p>
            FitFight compares Apple Health&apos;s merged Step Count over the same exact
            Fight window for every participant. Open the app to refresh current Steps.
            Steps that occur after the Fight&apos;s end time do not count toward its result.
          </p>
        </section>

        <section>
          <h2>Delete your account</h2>
          <p>
            Open <strong>You → Settings → Delete account</strong> and confirm. This
            permanently removes your profile, uploaded Steps, invitations and memberships,
            bugs and feature requests you posted, removes you from Fights created by someone else, and deletes Fights you created
            for every participant. FitFight also asks Apple to revoke an available Sign in
            with Apple credential and signs you out. This cannot be undone.
          </p>
          <p>
            If automatic Apple revocation was unavailable, follow the message in the app to
            disconnect FitFight in iPhone Settings. If deletion itself fails, retry and email
            support from the address linked to your account.
          </p>
        </section>

        <section>
          <h2>Privacy</h2>
          <p>
            Read the <Link href="/privacy">FitFight Privacy Policy</Link> for details about
            account data, private Fights, Apple Health Steps, service providers, and deletion.
          </p>
        </section>
      </article>

      <footer className="legal-footer">
        <span>© 2026 FitFight</span>
        <Link href="/privacy">Privacy Policy</Link>
      </footer>
    </main>
  );
}
