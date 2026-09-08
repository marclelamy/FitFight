import { TestflightInvite } from "@/components/testflight-invite";

export default function HomePage() {
  return (
    <main>
      <header className="site-header">
        <a className="brand" href="#top" aria-label="FitFight home">
          <span className="brand-mark">FF</span>
          <span>FitFight</span>
        </a>
        <TestflightInvite label="Get the app" kind="header" />
      </header>

      <section className="hero" id="top">
        <div className="hero-copy">
          <p className="eyebrow">YOUR STEP COMPETITION SCOREKEEPER</p>
          <h1>
            Let friendly competition<br />
            <span>move you.</span>
          </h1>
          <p className="lede">
            Connect Apple Health, start a private group challenge, and
            see who records the most steps.
          </p>
          <div className="hero-actions">
            <TestflightInvite label="Get the app" kind="hero" />
            <a className="text-action" href="#how-it-works">
              See how it works <span aria-hidden="true">↓</span>
            </a>
          </div>
          <p className="platform-note">iPhone · Install with TestFlight · Apple Health</p>
        </div>

        <div className="fight-stage" aria-label="Example FitFight leaderboard">
          <div className="orbit orbit-one" />
          <div className="orbit orbit-two" />
          <article className="fight-card">
            <div className="card-topline">
              <span className="status"><span className="live-dot" /> LIVE FIGHT</span>
              <span>2d left</span>
            </div>
            <div className="fight-title-row">
              <div>
                <p className="card-label">STEPS TOTAL</p>
                <h2>Weekly Step Challenge</h2>
              </div>
              <div className="rank"><strong>#1</strong><span>OF 2</span></div>
            </div>

            <div className="competitors">
              <div className="competitor winner">
                <div className="person">
                  <span className="avatar">Y</span>
                  <div><strong>You</strong><small>8,420 steps</small></div>
                </div>
                <div className="bar"><span /></div>
                <strong className="score">8.4k</strong>
              </div>
              <div className="competitor behind">
                <div className="person">
                  <span className="avatar">L</span>
                  <div><strong>Leo</strong><small>7,180 steps</small></div>
                </div>
                <div className="bar"><span /></div>
                <strong className="score">7.1k</strong>
              </div>
            </div>

            <div className="card-footer">
              <span>Keep moving</span>
              <strong>+1,240 ahead</strong>
            </div>
          </article>
          <div className="step-badge">
            <svg aria-hidden="true" viewBox="0 0 24 24">
              <path d="M8.1 3.4c1.5-.5 2.8.3 3.2 1.7.5 1.5-.2 3-1.7 3.5-1.5.5-2.8-.3-3.3-1.8-.4-1.4.3-2.9 1.8-3.4Zm6 6.7c1.8-.6 3.5.4 4.1 2.3.6 1.9-.3 3.8-2.1 4.4-1.8.6-3.5-.4-4.1-2.3-.6-1.9.3-3.8 2.1-4.4ZM5.2 10.5c1.2-.4 2.3.3 2.7 1.5.4 1.3-.2 2.5-1.4 2.9-1.2.4-2.3-.3-2.7-1.5-.4-1.2.2-2.5 1.4-2.9Zm4.2 5.1c1.5-.5 2.9.3 3.4 1.8.5 1.6-.2 3.1-1.7 3.6-1.5.5-2.9-.3-3.4-1.8-.5-1.5.2-3.1 1.7-3.6Z" />
            </svg>
          </div>
        </div>
      </section>

      <section className="how" id="how-it-works">
        <p className="eyebrow">HOW IT WORKS</p>
        <h2>Three steps to start. One winner to finish.</h2>
        <div className="steps">
          <article>
            <span>01</span>
            <h3>Add your friends</h3>
            <p>Search by username and add to any fight</p>
          </article>
          <article>
            <span>02</span>
            <h3>Move to win</h3>
            <p>Apple Health securely keeps the score while you live your day.</p>
          </article>
          <article>
            <span>03</span>
            <h3>Claim the win</h3>
            <p>Watch the standings, close the gap, and finish on top.</p>
          </article>
        </div>
      </section>

      <footer>
        <a className="brand" href="#top">
          <span className="brand-mark">FF</span>
          <span>FitFight</span>
        </a>
        <p>Challenge friends. Move to win.</p>
        <span>© 2026 FitFight</span>
      </footer>
    </main>
  );
}
