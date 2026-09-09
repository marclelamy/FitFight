import SwiftUI
import UIKit

struct FightDetailView: View {
    private let initialFight: Fight
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme

    @State private var copiedCode = false
    @State private var copiedLink = false

    init(fight: Fight) {
        initialFight = fight
    }

    private var fight: Fight {
        model.fight(id: initialFight.id) ?? initialFight
    }

    private var pendingJoin: Bool {
        (fight.status == .invited || fight.pendingJoin) && !model.joined.contains(fight.id)
    }

    private var canLeave: Bool {
        !pendingJoin
            && fight.status == .live
            && fight.inviter?.isYou != true
            && (fight.recurring || fight.joinCode != nil)
    }

    private var youDeferred: Bool {
        you?.deferred == true
    }

    var body: some View {
        FFScreen(top: AnyView(nav)) {
            if pendingJoin {
                invitedHero
            } else if youDeferred {
                deferredHero
            } else if let pair = headToHead {
                FFVSBlock(
                    you: pair.you,
                    them: pair.them,
                    delta: fight.kickerEmphasis,
                    ahead: fight.rank == 1,
                    footnote: "\(fight.metric.eyebrow) · \(fight.durationLabel) fight",
                    timeLeft: fight.timeLeftLabel
                )
            } else {
                liveHero
            }

            if !pendingJoin {
                if fight.joinCode != nil {
                    FFSection(title: String(localized: "Share")) {
                        shareCard
                    }
                }
                if fight.hasAction {
                    FFSection(title: String(localized: "Action")) {
                        FFCard {
                            Text(fight.actionText)
                                .ffType(.rowTitle)
                                .foregroundStyle(theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if let fightID = UUID(uuidString: fight.id) {
                    FFSection(title: String(localized: "Posts")) {
                        FightPostsSection(fightID: fightID, canPost: !youDeferred)
                    }
                }

                FFSection(title: String(localized: "Standings")) {
                    VStack(alignment: .leading, spacing: theme.space.cardGap) {
                        if let meta = fight.standingsMeta {
                            Text(meta)
                                .ffType(.caption)
                                .foregroundStyle(theme.textSecondary)
                        }
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            ForEach(Array(fight.standings.enumerated()), id: \.element.id) { index, row in
                                standingRow(index: index, row: row, now: context.date)
                            }
                        }
                    }
                }

                if !fight.days.isEmpty {
                    FFSection(title: String(localized: "Every day so far")) {
                        daysCard
                    }
                }

                if canLeave {
                    FFButton(
                        title: String(localized: "Leave fight"),
                        kind: .ghost,
                        fullWidth: true
                    ) {
                        Task {
                            await model.leaveFight(id: fight.id)
                        }
                    }
                    .padding(.top, theme.space.lg)
                    if let error = model.createError, !error.isEmpty {
                        Text(error)
                            .ffType(.caption)
                            .foregroundStyle(theme.emberText)
                            .padding(.top, 10)
                    }
                }
            }
        }
        .refreshable {
            await model.refreshFights(session: session, steps: steps)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var you: Standing? { model.youStanding(in: fight) }

    private var nav: some View {
        FFNavDetail(
            title: fight.listTitle,
            subtitle: fight.timeLeftLabel,
            onBack: { model.openFightID = nil }
        )
        .padding(.horizontal, theme.space.screenPadding)
        .padding(.bottom, 12)
        .background(theme.bg)
    }

    /// The kit's VS block only makes sense for two people.
    private var headToHead: (
        you: (monogram: String, name: String, value: String, progress: Double),
        them: (monogram: String, name: String, value: String, progress: Double)
    )? {
        let joined = fight.standings.filter { !$0.invited && !$0.deferred }
        guard joined.count == 2,
              let mine = joined.first(where: { $0.person.isYou }),
              let theirs = joined.first(where: { !$0.person.isYou })
        else { return nil }
        let peak = max(mine.score, theirs.score, 1)
        return (
            (mine.person.initials, String(localized: "You"), model.formatScore(mine.score, metric: fight.metric), mine.score / peak),
            (theirs.person.initials, theirs.person.name, model.formatScore(theirs.score, metric: fight.metric), theirs.score / peak)
        )
    }

    private var invitedHero: some View {
        FFCard(padding: 24) {
            VStack(spacing: 0) {
                FFTag(fight.metric.eyebrow)
                    .padding(.bottom, 12)
                Text(fight.listTitle)
                    .ffType(.title)
                    .foregroundStyle(theme.text)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)
                if let pitch = fight.invitePitch {
                    Text(pitch)
                        .ffType(.body)
                        .foregroundStyle(theme.text)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 8)
                }
                Text(
                    String(
                        localized: "fight.duration-rule",
                        defaultValue: "\(fight.durationLabel) · Most steps wins"
                    )
                )
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, fight.hasAction && fight.actionText != fight.listTitle ? 8 : 22)
                if fight.hasAction, fight.actionText != fight.listTitle {
                    Text(fight.actionText)
                        .ffType(.body)
                        .foregroundStyle(theme.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 22)
                }
                if fight.offersJoinNext {
                    Text(
                        String(
                            localized: "fight.join-now-copy",
                            defaultValue: "This round started \(joinRoundStarted). Join now and your steps count from that date."
                        )
                    )
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
                    Text(
                        String(
                            localized: "fight.join-next-copy",
                            defaultValue: "Or start next round, from \(joinRoundNext)."
                        )
                    )
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 22)
                    FFScreenCTA(title: String(localized: "Join this round")) {
                        Task { await join(start: "now") }
                    }
                    FFButton(
                        title: String(localized: "Start next round"),
                        kind: .ghost,
                        fullWidth: true
                    ) {
                        Task { await join(start: "next") }
                    }
                    .padding(.top, 8)
                } else {
                    FFScreenCTA(title: fight.pendingJoin ? String(localized: "Join fight") : String(localized: "Accept challenge")) {
                        Task { await join(start: "now") }
                    }
                }
                FFButton(
                    title: fight.pendingJoin ? String(localized: "Not now") : String(localized: "Decline"),
                    kind: .ghost,
                    fullWidth: true
                ) {
                    Task {
                        await model.declineFight(id: fight.id)
                        if (model.createError ?? "").isEmpty {
                            model.openFightID = nil
                        }
                    }
                }
                .padding(.top, 8)
                if let error = model.createError, !error.isEmpty {
                    Text(error)
                        .ffType(.caption)
                        .foregroundStyle(theme.emberText)
                        .padding(.top, 10)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var joinRoundStarted: String {
        fight.windowStart.formatted(date: .abbreviated, time: .omitted)
    }

    private var joinRoundNext: String {
        fight.windowEnd.formatted(date: .abbreviated, time: .omitted)
    }

    private func join(start: String) async {
        await model.acceptFight(id: fight.id, start: start)
        if (model.createError ?? "").isEmpty {
            model.joined.insert(fight.id)
        }
    }

    private var deferredHero: some View {
        FFCard(padding: 24) {
            VStack(alignment: .leading, spacing: 8) {
                FFTag(String(localized: "Next round"))
                Text(String(localized: "You start next round"))
                    .ffType(.title)
                    .foregroundStyle(theme.text)
                Text(
                    String(
                        localized: "fight.deferred-copy",
                        defaultValue: "Your steps count from \(joinRoundNext). This round’s standings are still visible."
                    )
                )
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var shareCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: 12) {
                if let code = fight.joinCode {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Code")
                                .ffType(.caption)
                                .foregroundStyle(theme.textSecondary)
                            Text(code)
                                .ffType(.heading)
                                .foregroundStyle(theme.text)
                        }
                        Spacer()
                        Button {
                            UIPasteboard.general.string = code
                            copiedCode = true
                        } label: {
                            Text(copiedCode ? String(localized: "Copied") : String(localized: "Copy code"))
                                .ffType(.caption)
                                .foregroundStyle(theme.mossText)
                        }
                        .buttonStyle(FFHapticPlainStyle())
                    }
                }
                if let code = fight.joinCode, let referralCode = session.profile?.referralCode {
                    let url = APIConfig.joinShareURL(code: code, referralCode: referralCode)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Link")
                                .ffType(.caption)
                                .foregroundStyle(theme.textSecondary)
                            Text(url.absoluteString)
                                .ffType(.caption)
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            UIPasteboard.general.string = url.absoluteString
                            copiedLink = true
                        } label: {
                            Text(copiedLink ? String(localized: "Copied") : String(localized: "Copy link"))
                                .ffType(.caption)
                                .foregroundStyle(theme.mossText)
                        }
                        .buttonStyle(FFHapticPlainStyle())
                    }
                    ShareLink(item: url) {
                        Label(String(localized: "Share fight"), systemImage: "square.and.arrow.up")
                            .ffType(.label)
                            .foregroundStyle(theme.mossText)
                    }
                }
            }
        }
    }

    private var liveHero: some View {
        FFRingCard(
            progress: ringProgress,
            title: fight.status == .finished
                ? String(
                    localized: "fight.finished-rank",
                    defaultValue: "Finished #\(fight.rank)"
                )
                : String(
                    localized: "fight.rank-of-count",
                    defaultValue: "#\(fight.rank) of \(fight.of)"
                ),
            subtitle: String(
                localized: "fight.metric-time-left",
                defaultValue: "\(fight.metric.eyebrow) · \(fight.timeLeftLabel)"
            ),
            metric: model.formatScore(you?.score ?? 0, metric: fight.metric),
            delta: fight.kickerEmphasis,
            ahead: fight.rank == 1
        )
    }

    private var ringProgress: Double {
        let leader = fight.standings.first?.score ?? 1
        let yours = you?.score ?? 0
        return leader == 0 ? 0 : min(yours / leader, 1)
    }

    private func standingRow(index: Int, row: Standing, now: Date) -> some View {
        Group {
            if row.invited || row.deferred {
                HStack(spacing: 13) {
                    Text("—")
                        .ffType(.button)
                        .foregroundStyle(theme.textFaint)
                        .frame(width: 22)
                    FFAvatar(row.person, size: 38, pending: true)
                    Text(row.person.name)
                        .ffType(.rowTitle)
                        .foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    FFPill(
                        row.deferred ? String(localized: "Next round") : String(localized: "Invited"),
                        style: .gold
                    )
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
                .ffBorder(theme.hairline, radius: theme.radius.card)
            } else {
                FFLeaderboardRow(
                    rank: index + 1,
                    monogram: row.person.initials,
                    name: row.person.name,
                    value: model.formatScore(row.score, metric: fight.metric),
                    move: .same,
                    isYou: row.person.isYou,
                    caption: model.formatStandingFreshness(row, fight: fight, now: now),
                    captionUrgent: false
                )
            }
        }
    }

    private var daysCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(fight.days.enumerated()), id: \.element.id) { index, day in
                    if index > 0 { Color.clear.frame(height: 20) }
                    FFEyebrow(day.label)
                        .padding(.bottom, 12)
                    let peak = day.scores.map(\.value).max() ?? 1
                    let leaderID = fight.standings.first?.person.id
                    VStack(spacing: 10) {
                        ForEach(day.scores) { row in
                            HStack(spacing: 10) {
                                Text(row.person.name)
                                    .ffType(.micro)
                                    .foregroundStyle(theme.textSecondary)
                                    .lineLimit(1)
                                    .frame(width: 56, alignment: .leading)
                                FFProgressBar(
                                    value: peak == 0 ? 0 : row.value / peak,
                                    fill: row.person.id == leaderID ? theme.mossFill : theme.textFaint
                                )
                                Text(model.formatScore(row.value, metric: fight.metric))
                                    .ffType(.micro)
                                    .foregroundStyle(theme.textSecondary)
                                    .frame(width: 56, alignment: .trailing)
                            }
                        }
                    }
                }
                if let note = fight.paceNote {
                    FFDivider(inset: 0)
                        .padding(.vertical, 18)
                    Text(note)
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .lineSpacing(3)
                }
            }
        }
    }
}
