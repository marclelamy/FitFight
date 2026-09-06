import Foundation

struct ReleaseNote: Identifiable {
    let version: String
    let year: Int
    let month: Int
    let day: Int
    let notes: LocalizedStringResource

    /// Several notes may share one marketing version (TestFlight does not bump it).
    var id: String { "\(version)-\(year)-\(month)-\(day)-\(notes.key)" }

    var date: Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return components.date ?? .distantPast
    }
}

enum Changelog {
    /// Newest first. Add a row here whenever we ship a user-facing change.
    static let releases: [ReleaseNote] = [
        ReleaseNote(
            version: "1.0.0",
            year: 2026,
            month: 9,
            day: 5,
            notes: "Apple Health sync failures now include an error reference on You and diagnostic details to help investigate."
        ),
        ReleaseNote(
            version: "1.0.0",
            year: 2026,
            month: 9,
            day: 5,
            notes: "Fights refresh with fewer network requests, and private Apple Health timing logs help diagnose slow syncs."
        ),
        ReleaseNote(
            version: "1.0.0",
            year: 2026,
            month: 9,
            day: 5,
            notes: "Apple Health on You shows today’s step count correctly."
        ),
        ReleaseNote(
            version: "1.0.0",
            year: 2026,
            month: 9,
            day: 5,
            notes: "Invitation responses are secured, and unavailable Apple Health data no longer replaces saved Steps with zero."
        ),
        ReleaseNote(
            version: "1.0.0",
            year: 2026,
            month: 9,
            day: 4,
            notes: "Share on a fight uses the same space under the section title as Action and Standings."
        ),
        ReleaseNote(
            version: "1.0.0",
            year: 2026,
            month: 9,
            day: 4,
            notes: "You can name a fight. Title and action are both optional; if you skip a title, the action is the name on Fights."
        ),
        ReleaseNote(
            version: "1.0.0",
            year: 2026,
            month: 9,
            day: 4,
            notes: "You → Settings now has Bugs & requests: post a bug or a feature request, see what other people submitted, upvote, and comment with your username."
        ),
        ReleaseNote(
            version: "1.0.0",
            year: 2026,
            month: 9,
            day: 4,
            notes: "New now starts with Create or Join. Joinable fights use a 4-character code and a live list; share the code or link from the fight. Recurring fights roll into the next window when the current one ends. Leave from the fight if you do not want the next one."
        ),
        ReleaseNote(
            version: "1.0.0",
            year: 2026,
            month: 9,
            day: 4,
            notes: "Every fight in the list is now titled by the action the loser owes, because that is the only name a fight has. The number on the right is how far ahead or behind you are, the days left sit underneath, and every live fight is the same size instead of one large card on top."
        ),
        ReleaseNote(
            version: "1.0.0",
            year: 2026,
            month: 9,
            day: 4,
            notes: "The TestFlight update notice sits under the version line at the top of the screen and uses a solid card instead of a see-through toast over the tab bar."
        ),
        ReleaseNote(
            version: "1.0.0",
            year: 2026,
            month: 9,
            day: 4,
            notes: "FitFight now follows your iPhone language in English or French, including fights, Apple Health access, settings, errors, accessibility labels, and the Versions history."
        ),
        ReleaseNote(
            version: "1.0.0",
            year: 2026,
            month: 9,
            day: 4,
            notes: "Apple Health background sync now starts at launch, preserves interrupted work for the next foreground refresh, and shows private sync status under You. Fight standings show relative freshness and whether ended fights include complete final Steps."
        ),
        ReleaseNote(
            version: "1.0.0",
            year: 2026,
            month: 9,
            day: 3,
            notes: "Fight setup uses a normal Next button on the first steps, then a real slide-to-start control on review so creating a fight cannot be mistaken for a swipe."
        ),
        ReleaseNote(
            version: "1.0.0",
            year: 2026,
            month: 9,
            day: 3,
            notes: "Tapping Fights again while a fight is open returns you to the list. You can also swipe from the left edge to go back, like in other iOS apps."
        ),
        ReleaseNote(
            version: "1.0.0",
            year: 2026,
            month: 9,
            day: 3,
            notes: "Fight setup now shows New fight beside the first-step progress, then replaces it with Back as you move through the remaining steps."
        ),
        ReleaseNote(
            version: "1.0.0",
            year: 2026,
            month: 9,
            day: 3,
            notes: "Fight setup now opens directly on the current step, without a repeated New Fight heading above the progress and Back controls."
        ),
        ReleaseNote(
            version: "1.0.0",
            year: 2026,
            month: 9,
            day: 3,
            notes: "Fight setup now starts with the Steps metric, then duration, opponents, loser action, and review. Next stays at the bottom on short steps, and Return closes every setup keyboard."
        ),
        ReleaseNote(
            version: "1.0.0",
            year: 2026,
            month: 9,
            day: 3,
            notes: "Creating a Fight is now a clear four-step flow: enter opponents with Return, choose the duration, agree on the loser action, then review every detail before starting."
        ),
        ReleaseNote(
            version: "1.0.0",
            year: 2026,
            month: 9,
            day: 3,
            notes: "Opening the app now shows an in-app notice when a newer TestFlight build is available, so you can open TestFlight and tap Update."
        ),
        ReleaseNote(
            version: "1.0.0",
            year: 2026,
            month: 9,
            day: 3,
            notes: "Inside a fight, the Total and Today tiles under the main card are gone. The head-to-head card, action, standings, and daily breakdown stay."
        ),
        ReleaseNote(
            version: "1.0.0",
            year: 2026,
            month: 9,
            day: 3,
            notes: "Standings now show each person's last Apple Health sync date and time, so you can see whether a score is current or someone has not uploaded yet."
        ),
        ReleaseNote(
            version: "1.0.0",
            year: 2026,
            month: 9,
            day: 2,
            notes: "FitFight now focuses on private Steps challenges: invite people by exact username, choose a duration, agree on the action, and compare Apple Health Steps. Privacy, Support, Versions, and permanent account deletion are available under You."
        ),
        ReleaseNote(
            version: "0.9.0",
            year: 2026,
            month: 9,
            day: 1,
            notes: "Fights and standings now identify people by their usernames, and head-to-head comparisons show the actual step difference instead of a generic position label."
        ),
        ReleaseNote(
            version: "0.9.0",
            year: 2026,
            month: 9,
            day: 1,
            notes: "Offline refreshes keep your profile available, cleanup from a previous account no longer interrupts Apple Health for the current account, and 1-day fights show the correct time remaining."
        ),
        ReleaseNote(
            version: "0.9.0",
            year: 2026,
            month: 9,
            day: 1,
            notes: "Fights appear immediately from the last successful update, refresh automatically when FitFight becomes active, and can be refreshed by pulling down on the Fights list or inside a Fight. A failed refresh keeps the existing Fights visible."
        ),
        ReleaseNote(
            version: "0.9.0",
            year: 2026,
            month: 8,
            day: 31,
            notes: "New fight now includes 1-hour, 6-hour, and 1-day durations for quickly testing a complete Fight, alongside the existing longer options."
        ),
        ReleaseNote(
            version: "0.9.0",
            year: 2026,
            month: 8,
            day: 31,
            notes: "Fight invitations now appear at the top of Fights, before active challenges, so requests waiting for a response are immediately visible."
        ),
        ReleaseNote(
            version: "0.9.0",
            year: 2026,
            month: 8,
            day: 31,
            notes: "Delete account now permanently removes your profile, username, uploaded Steps, invitations, memberships, scores, and fights you created, then clears local Health sync data and signs you out. FitFight also disconnects Sign in with Apple automatically when Apple supplied a revocable credential. Privacy and Support now explain the same behavior and the daily Steps shared inside a fight."
        ),
        ReleaseNote(
            version: "0.9.0",
            year: 2026,
            month: 8,
            day: 30,
            notes: "FitFight is now only private Steps challenges: three tabs (Fights, New, You), exact usernames instead of friendships, a required loser action, and 3-day, 1-week, 2-week, or 1-month durations. Requests, money, other metrics, and dead settings are gone; Privacy and Support links are added."
        ),
        ReleaseNote(
            version: "0.9.0",
            year: 2026,
            month: 8,
            day: 30,
            notes: "FitFight now sends only Apple's merged Steps totals: one exact total for each Fight window and the relevant daily totals for charts. Raw samples, deletions, source and device details, and Apple Health archives are no longer collected."
        ),
        ReleaseNote(
            version: "0.9.0",
            year: 2026,
            month: 8,
            day: 30,
            notes: "Apple Health synchronization now replaces an incompatible upload left by an older build while preserving the prepared HealthKit archive. Compatible interrupted uploads still resume normally."
        ),
        ReleaseNote(
            version: "0.9.0",
            year: 2026,
            month: 8,
            day: 30,
            notes: "Apple Health archives now reach private Storage with the complete signed resumable-upload authorization required by Supabase. Initial synchronization can continue instead of failing immediately after the server authorizes it."
        ),
        ReleaseNote(
            version: "0.9.0",
            year: 2026,
            month: 8,
            day: 30,
            notes: "Large Apple Health histories can now complete their first sync instead of stopping at 50 MiB. FitFight still uploads one resumable private archive and advances the HealthKit checkpoint only after the server processes it and removes the object."
        ),
        ReleaseNote(
            version: "0.9.0",
            year: 2026,
            month: 8,
            day: 30,
            notes: "Apple Health sync now accepts active Fight windows correctly, explains whether a failure happened while preparing, uploading, or processing Steps, and enables best-effort background updates when iOS permits. Manual sync still works whenever FitFight is open."
        ),
        ReleaseNote(
            version: "0.9.0",
            year: 2026,
            month: 8,
            day: 30,
            notes: "Apple Health sync can now resume an interrupted upload without starting over. FitFight advances its HealthKit checkpoint only after the complete archive is safely processed, freezes finished days, and uses the exact Fight end time so later Steps cannot change the result."
        ),
        ReleaseNote(
            version: "0.9.0",
            year: 2026,
            month: 8,
            day: 29,
            notes: "Steps fights still use Apple's merged total, so overlapping Apple Watch, iPhone, WHOOP, Garmin, and other sources are not added together. FitFight now sends every accessible raw Steps sample, deletion, source statistic, device detail, and metadata value through its secure backend for diagnostics and future features."
        ),
        ReleaseNote(
            version: "0.9.0",
            year: 2026,
            month: 8,
            day: 29,
            notes: "Selected rows now have properly concentric corners, and dividers disappear cleanly around the selection. Requests no longer drifts sideways when you scroll."
        ),
        ReleaseNote(
            version: "0.9.0",
            year: 2026,
            month: 8,
            day: 29,
            notes: "New look, built from the approved design kit. One palette instead of ten accent colours — moss is you and winning, ember is losing and urgent, gold is progress. Nunito replaces Manrope. Every screen rebuilt: a moss hero card on Fights, a head-to-head block and leaderboard on a fight, new form controls on New fight. Look is now Night or Day. You → Settings → Design system shows every token and component in the app."
        ),
        ReleaseNote(
            version: "0.9.0",
            year: 2026,
            month: 8,
            day: 27,
            notes: "Staging talks to the new persistent develop database. Sign in again on this build (the old staging host is gone)."
        ),
        ReleaseNote(
            version: "0.9.0",
            year: 2026,
            month: 8,
            day: 26,
            notes: "Start fight shows Starting… and ignores extra taps so one tap cannot create duplicate fights."
        ),
        ReleaseNote(
            version: "0.9.0",
            year: 2026,
            month: 8,
            day: 25,
            notes: "Pick a username after sign-in. Start a Steps fight from the phone (no extra server). Apple Health uploads. Standings come from the database. Add friends on You with their username. Design tab is gone. Version line shows version and build number."
        ),
        ReleaseNote(
            version: "0.9.0",
            year: 2026,
            month: 8,
            day: 25,
            notes: "If you are not signed in you get a welcome screen (FitFight, a line of copy, Sign in with Apple). The tabs stay hidden until you are in."
        ),
        ReleaseNote(
            version: "0.9.0",
            year: 2026,
            month: 8,
            day: 25,
            notes: "This TestFlight talks to develop. The version at the top includes staging and the date of the last ship. Still 0.9.0 — only the build number and the date change."
        ),
        ReleaseNote(
            version: "0.8.0",
            year: 2026,
            month: 8,
            day: 25,
            notes: "The version at the top now says prod or staging, so you can see which Supabase the phone is talking to."
        ),
        ReleaseNote(
            version: "0.8.0",
            year: 2026,
            month: 8,
            day: 25,
            notes: "Sign in, add friends by handle, start a real Steps fight, Apple Health uploads to the server, standings come from the database. Fights are no longer the fixture people. When the days are up the fight closes on the server — you do not have to leave the app open. Design tab still previews the old mock. Requests is unchanged."
        ),
        ReleaseNote(
            version: "0.8.0",
            year: 2026,
            month: 8,
            day: 24,
            notes: "You can sign in with Apple. You shows your real handle. You → Data sources reads today’s Steps from Apple Health (the HealthKit total, not every source added together) and lists contributing apps when HealthKit names them. Empty reads say “No accessible data”. You → Settings has Delete account."
        ),
        ReleaseNote(
            version: "0.7.0",
            year: 2026,
            month: 8,
            day: 23,
            notes: "Requests has a Talk to the boss button. It opens a private chat with Marc — not the public vote board. What you send is emailed to him; he writes back from his inbox until the app has a server."
        ),
        ReleaseNote(
            version: "0.6.0",
            year: 2026,
            month: 8,
            day: 23,
            notes: "Ten new looks for the app, plus a Design tab to flip between them. Each one is a real redesign of the fights screen with its own colours and its own idea of what matters: Ring closes an activity ring for every fight, Ledger reads like a betting statement, Arena puts you face to face with whoever is beating you, Soft says it in a sentence, Terminal prints it as monospace, Stack floats it on frosted glass, Podium builds a gold podium, Pulse turns the pot into one stacked bar, Bento lays it out as uneven tiles and Zine sets it like a printed page. Every design shows the same fights and the same money — only the look changes. The tab shows all eleven side by side, live, and one tap swaps the app over."
        ),
        ReleaseNote(
            version: "0.5.1",
            year: 2026,
            month: 8,
            day: 23,
            notes: "Everything was too round. Measuring the corners against the mockups showed the request cards curving over 12 points where the design curves over 6, and the Top/Features/Bugs switcher, the vote pill, the Feature/Bug tags and the day and stake chips were all close to twice as round as they should be. Section titles also sit slightly inside the card below them, the way the design draws them."
        ),
        ReleaseNote(
            version: "0.5.0",
            year: 2026,
            month: 8,
            day: 23,
            notes: "The app was shouting. Measuring the brightness of every line against the mockups showed that most quiet text — the eyebrows over card titles, the line under each screen title, stat labels, handles, timestamps, +2 more — was rendering at 62% white where the design uses 40%. The bell, the Edit pill and the fight nav buttons also had a grey fill the design does not have, and the bell itself was three points too big. Buttons are the mockups' size now, and a part-filled progress bar is no longer two translucent whites stacked up."
        ),
        ReleaseNote(
            version: "0.4.2",
            year: 2026,
            month: 8,
            day: 23,
            notes: "Another measuring pass over the mockups. The Top/Features/Bugs switcher was seven points too tall, a fight card with people still to accept grew taller than one without, and the kickers above every card title sat two points high. All fixed."
        ),
        ReleaseNote(
            version: "0.4.1",
            year: 2026,
            month: 8,
            day: 23,
            notes: "Everyone has their face back: Leo, Sam, Nina, Theo, Ivy and you now use the photographs from the design instead of coloured initials. Settings rows, the pending pill and the option rows on New fight are the sizes the mockups use."
        ),
        ReleaseNote(
            version: "0.4.0",
            year: 2026,
            month: 8,
            day: 23,
            notes: "The app now uses Manrope, the typeface the design was drawn in, instead of the system font. Every title, name and number is the shape it is in the mockups."
        ),
        ReleaseNote(
            version: "0.3.1",
            year: 2026,
            month: 8,
            day: 23,
            notes: "Rebuilt every screen against pixel measurements of the design screenshots: inline standings bars, tinted card footers, the rank ring on a fight, and the real spacing everywhere."
        ),
        ReleaseNote(
            version: "0.3.0",
            year: 2026,
            month: 8,
            day: 22,
            notes: "The approved look, as a real iOS app. Four tabs matching the screenshots: Fights, New, Requests, You. Dark/light plus ten accents."
        ),
        ReleaseNote(
            version: "0.2.0",
            year: 2026,
            month: 8,
            day: 22,
            notes: "Placeholder themes (Arena, Pulse, Locker, Rogue). Superseded."
        ),
        ReleaseNote(
            version: "0.1.0",
            year: 2026,
            month: 8,
            day: 22,
            notes: "First TestFlight. App name on screen, version at the top, and a Versions list for every release."
        ),
    ]

    /// Array is newest-first; same-day rows keep that order.
    static var newestFirst: [ReleaseNote] {
        releases.enumerated().sorted { lhs, rhs in
            if lhs.element.date != rhs.element.date {
                return lhs.element.date > rhs.element.date
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// TestFlight keeps the full build history. Production starts at 1.0.
    static var visible: [ReleaseNote] {
        guard AppVersion.backend == "prod" else { return newestFirst }
        return newestFirst.filter { !$0.version.hasPrefix("0.") }
    }

    static var current: ReleaseNote? {
        newestFirst.first { $0.version == AppVersion.marketing }
    }
}
