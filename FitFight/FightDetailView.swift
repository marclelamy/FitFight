import Combine
import SwiftUI
import UIKit

private enum FightDetailPane: Hashable, CaseIterable {
    case stats
    case feed

    var title: String {
        switch self {
        case .stats:
            return String(localized: "Stats")
        case .feed:
            return String(localized: "Feed")
        }
    }
}

struct FightDetailView: View {
    private let initialFight: Fight
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme

    @State private var copiedCode = false
    @State private var copiedLink = false
    @State private var fightsRevision = 0
    @State private var pane: FightDetailPane = .stats

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
            && (fight.status == .live || fight.status == .pending)
            && fight.inviter?.isYou != true
            && (fight.recurring || fight.joinCode != nil)
    }

    private var youDeferred: Bool {
        you?.deferred == true
    }

    var body: some View {
        FFScreen(top: AnyView(nav), refresh: pendingJoin ? nil : fightsRefresh) {
            if pendingJoin {
                JoinFightPreview(
                    fight: fight,
                    joining: model.isJoiningFight,
                    onJoinNow: { Task { await join(start: "now") } },
                    onJoinNext: { Task { await join(start: "next") } },
                    onDismiss: {
                        Task {
                            await model.declineFight(id: fight.id)
                            if (model.createError ?? "").isEmpty {
                                model.openFightID = nil
                            }
                        }
                    }
                )
                .id(fightsRevision)
            } else {
                FFSegmented(items: FightDetailPane.allCases, selection: $pane) { item in
                    item.title
                }
                .padding(.bottom, 4)

                if pane == .stats {
                    statsPane
                } else if let fightID = UUID(uuidString: fight.id) {
                    FightPostsSection(fightID: fightID)
                }
            }
        }
        .onReceive(model.$fights) { _ in
            fightsRevision += 1
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var fightsRefresh: FFRefreshConfig {
        FFRefreshConfig(
            isRefreshing: model.isRefreshingFights,
            message: model.refreshStatusText,
            action: {
                await model.refreshFights(session: session, steps: steps, trigger: .manual)
            }
        )
    }

    private var you: Standing? { model.youStanding(in: fight) }

    private var isPendingSettlement: Bool {
        fight.status == .pending && !youDeferred
    }

    @ViewBuilder
    private var statsPane: some View {
        Group {
            if youDeferred {
                deferredHero
            } else if fight.status == .pending {
                settlementHero
            } else if let pair = headToHead {
                FFVSBlock(
                    you: pair.you,
                    them: pair.them,
                    delta: fight.kickerEmphasis,
                    ahead: fight.rank == 1 && !fight.isTiedForFirst,
                    footnote: "\(fight.metric.eyebrow) · \(fight.durationLabel) fight",
                    timeLeft: fight.deadlineLabel
                )
            } else {
                liveHero
            }
        }
        .id(fightsRevision)

        if isPendingSettlement {
            daysSection
            actionSection
            standingsSection
            shareSection
        } else {
            shareSection
            actionSection
            standingsSection
            daysSection
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

    @ViewBuilder
    private var shareSection: some View {
        if fight.joinCode != nil {
            FFSection(title: String(localized: "Share")) {
                shareCard
            }
        }
    }

    @ViewBuilder
    private var actionSection: some View {
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
    }

    private var standingsSection: some View {
        FFSection(title: String(localized: "Standings")) {
            VStack(alignment: .leading, spacing: theme.space.cardGap) {
                if let meta = fight.standingsMeta {
                    Text(meta)
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                ForEach(Array(fight.standings.enumerated()), id: \.element.id) { index, row in
                    standingRow(index: index, row: row)
                }
            }
            .id(fightsRevision)
        }
    }

    @ViewBuilder
    private var daysSection: some View {
        if !fight.days.isEmpty {
            FFSection(title: String(localized: "Every day so far")) {
                daysCard(initialKind: isPendingSettlement ? .pace : nil)
            }
        }
    }

    private var nav: some View {
        FFNavDetail(
            title: fight.listTitle,
            subtitle: fight.timeAndDeadlineLabel,
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

    private var joinRoundNext: String {
        Fight.deadlineStamp(fight.windowEnd)
    }

    private func join(start: String) async {
        await model.acceptFight(id: fight.id, start: start)
        if (model.createError ?? "").isEmpty {
            model.joined.insert(fight.id)
        }
    }

    private var settlementHero: some View {
        FFCard(padding: 24) {
            VStack(alignment: .leading, spacing: 10) {
                FFResultGlyph(.pending)
                Text(fight.kickerEmphasis)
                    .ffType(.title)
                    .foregroundStyle(settlementTitleColor)
                Text(fight.endedLabel ?? fight.deadlineLabel)
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                if let grace = fight.graceEndsAt {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        if grace > context.date {
                            Text(
                                String(
                                    localized: "fight.sync-time-left",
                                    defaultValue: "\(RemainingTime.phrase(from: context.date, until: grace)) left to sync"
                                )
                            )
                            .ffType(.caption)
                            .foregroundStyle(theme.goldInk)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var settlementTitleColor: Color {
        guard you?.finalStepsComplete == true else { return theme.emberText }
        let submitted = fight.standings.filter { !$0.invited && !$0.deferred && $0.finalStepsComplete == true }
        return submitted.first?.person.isYou == true ? theme.mossText : theme.emberText
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
                ? (fight.isTiedForFirst
                    ? String(localized: "Tied")
                    : String(
                        localized: "fight.finished-rank",
                        defaultValue: "Finished #\(fight.rank)"
                    ))
                : String(
                    localized: "fight.rank-of-count",
                    defaultValue: "#\(fight.rank) of \(fight.of)"
                ),
            subtitle: String(
                localized: "fight.metric-time-left",
                defaultValue: "\(fight.metric.eyebrow) · \(fight.timeAndDeadlineLabel)"
            ),
            metric: model.formatScore(you?.score ?? 0, metric: fight.metric),
            delta: fight.kickerEmphasis,
            ahead: fight.rank == 1 && !fight.isTiedForFirst
        )
    }

    private var ringProgress: Double {
        let leader = fight.standings.first?.score ?? 1
        let yours = you?.score ?? 0
        return leader == 0 ? 0 : min(yours / leader, 1)
    }

    private func standingRow(index: Int, row: Standing) -> some View {
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
            } else if fight.status == .pending {
                pendingStandingRow(row)
            } else {
                FFLeaderboardRow(
                    rank: fight.status == .finished ? (row.rank ?? (index + 1)) : index + 1,
                    monogram: row.person.initials,
                    name: row.person.name,
                    value: model.formatScore(row.score, metric: fight.metric),
                    move: .same,
                    isYou: row.person.isYou,
                    captionUrgent: false,
                    captionAt: { now in
                        model.formatStandingFreshness(row, fight: fight, now: now)
                    }
                )
            }
        }
    }

    private func pendingStandingRow(_ row: Standing) -> some View {
        let needsSync = row.finalStepsComplete != true
        let submitted = fight.standings.filter { !$0.invited && !$0.deferred && $0.finalStepsComplete == true }
        let rank = submitted.firstIndex { $0.id == row.id }.map { $0 + 1 }
        return HStack(spacing: 13) {
            Text(needsSync ? "—" : "\(rank ?? 0)")
                .ffType(.button)
                .foregroundStyle(needsSync ? theme.textFaint : (rank == 1 ? theme.gold : theme.textTertiary))
                .frame(width: 22)
            FFAvatar(row.person, size: 38, pending: needsSync)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.person.name)
                    .ffType(.rowTitle)
                    .foregroundStyle(needsSync ? theme.textSecondary : theme.text)
                    .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(model.formatStandingFreshness(row, fight: fight, now: context.date))
                        .ffType(.micro)
                        .foregroundStyle(needsSync && row.person.isYou ? theme.emberText : theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            FFPill(
                needsSync
                    ? String(localized: "fight.pending-sync", defaultValue: "Pending")
                    : String(localized: "Synced"),
                style: needsSync ? .gold : .neutral
            )
            Text(model.formatScore(row.score, metric: fight.metric))
                .font(.ff(17, 800))
                .tracking(17 * -0.02)
                .foregroundStyle(theme.text)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(
            row.person.isYou ? theme.mossWash : theme.card,
            in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
        )
        .ffBorder(row.person.isYou ? theme.mossEdge : theme.hairline, radius: theme.radius.card)
    }

    private func daysCard(initialKind: FightDayChartKind? = nil) -> some View {
        FFCard {
            VStack(alignment: .leading, spacing: 0) {
                FightDayChartsView(days: fight.days, initialKind: initialKind) { value in
                    model.formatScore(value, metric: fight.metric)
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

/// Title, rules, and Join — used before someone is in the fight. Not the live Stats view.
struct JoinFightPreview: View {
    let fight: Fight
    var joining: Bool
    let onJoinNow: () -> Void
    let onJoinNext: () -> Void
    let onDismiss: () -> Void

    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
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
                    .padding(.bottom, 8)
                Text(fight.deadlineLabel)
                    .ffType(.caption)
                    .fontWeight(.heavy)
                    .foregroundStyle(theme.gold)
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
                    FFScreenCTA(
                        title: joining ? String(localized: "Joining…") : String(localized: "Join this round"),
                        busy: joining
                    ) {
                        onJoinNow()
                    }
                    FFButton(
                        title: String(localized: "Start next round"),
                        kind: .ghost,
                        enabled: !joining,
                        fullWidth: true
                    ) {
                        onJoinNext()
                    }
                    .padding(.top, 8)
                } else {
                    FFScreenCTA(
                        title: joining
                            ? String(localized: "Joining…")
                            : (fight.pendingJoin ? String(localized: "Join fight") : String(localized: "Accept challenge")),
                        busy: joining
                    ) {
                        onJoinNow()
                    }
                }
                FFButton(
                    title: fight.pendingJoin ? String(localized: "Not now") : String(localized: "Decline"),
                    kind: .ghost,
                    enabled: !joining,
                    fullWidth: true
                ) {
                    onDismiss()
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
        Fight.deadlineStamp(fight.windowStart)
    }

    private var joinRoundNext: String {
        Fight.deadlineStamp(fight.windowEnd)
    }
}
