import SwiftUI

struct FightsListView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFScreen(refresh: fightsRefresh) {
            FFScreenTitle(title: String(localized: "Fights"), subtitle: subtitle)
                .padding(.bottom, 6)

            if isEmpty, !model.isRefreshingFights {
                FFEmptyState(
                    systemImage: "trophy",
                    title: String(localized: "No fights yet"),
                    message: String(localized: "Start one under New. Add people with their username — they must have signed in once."),
                    actionTitle: String(localized: "Start one"),
                    action: { model.tab = .newFight }
                )
            }

            if !model.invitations.isEmpty {
                FFSectionHeader(title: String(localized: "Invitations"))
                ForEach(model.invitations) { fight in
                    InvitationRow(fight: fight)
                }
            }

            ForEach(model.live) { fight in
                let standing = difference(in: fight)
                FFListRow(
                    monogram: initials(fight),
                    title: fight.listTitle,
                    subtitle: fight.timeLeftLabel,
                    metric: standing.text,
                    ahead: standing.ahead,
                    metricIsGap: standing.isGap,
                    action: { model.openFightID = fight.id }
                )
            }

            if !model.finished.isEmpty {
                FFSectionHeader(title: String(localized: "Finished"))
                    .padding(.top, theme.space.lg)
                ForEach(model.finished) { fight in
                    FinishedRow(fight: fight)
                }
            }
        }
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

    private var isEmpty: Bool {
        model.live.isEmpty && model.invitations.isEmpty && model.finished.isEmpty
    }

    private var subtitle: String {
        var parts: [String] = [
            String(
                localized: "fights.live-count",
                defaultValue: "\(model.live.count) live"
            ),
        ]
        if !model.invitations.isEmpty {
            parts.append(
                String(
                    localized: "fights.waiting-count",
                    defaultValue: "\(model.invitations.count) waiting"
                )
            )
        }
        return parts.joined(separator: " · ")
    }

    /// The number on the right is your distance from whoever you are actually
    /// racing: the leader when you are behind, the runner-up when you are ahead.
    /// Nobody else has a score yet in a fresh fight, so that row shows your total.
    private func difference(in fight: Fight) -> (text: String, ahead: Bool, isGap: Bool) {
        if model.youStanding(in: fight)?.deferred == true {
            return (String(localized: "Next round"), true, false)
        }
        let rivals = fight.standings.filter { !$0.person.isYou && !$0.invited && !$0.deferred }.map(\.score)
        guard let mine = model.youStanding(in: fight)?.score else {
            guard let leader = rivals.max() else { return ("—", true, false) }
            return (stepCount(leader), true, false)
        }
        guard let best = rivals.max() else { return (stepCount(mine), true, false) }
        let gap = mine - best
        guard gap != 0 else { return (String(localized: "Tied"), true, false) }
        return ("\(gap < 0 ? "−" : "+")\(stepCount(abs(gap)))", gap > 0, true)
    }

    /// Whole steps with the locale's grouping. A gap of 840 must not read "0.8k".
    private func stepCount(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    /// The other side of a head-to-head, so the avatar is who you are up against.
    private func initials(_ fight: Fight) -> String {
        let other = fight.standings.first { !$0.person.isYou && !$0.invited && !$0.deferred }
        return other?.person.initials ?? fight.standings.first?.person.initials ?? "?"
    }
}

struct InvitationRow: View {
    let fight: Fight
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 13) {
            FFAvatar(fight.inviter ?? fight.standings.first?.person, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(fight.listTitle)
                    .ffType(.heading)
                    .foregroundStyle(theme.text)
                Text(fight.listSubtitle)
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 8)
            Button {
                model.openFightID = fight.id
            } label: {
                FFPill(String(localized: "Join"), style: .solidMoss)
            }
            .buttonStyle(FFPressStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(theme.mossWash, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .ffBorder(theme.mossText.opacity(0.18), radius: theme.radius.card)
        .contentShape(Rectangle())
        .onTapGesture { model.openFightID = fight.id }
    }
}

struct FinishedRow: View {
    let fight: Fight
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        Button {
            model.openFightID = fight.id
        } label: {
            HStack(spacing: 13) {
                FFResultGlyph(fight.standings.contains(where: { $0.person.isYou && $0.deferred }) ? .draw : (fight.rank == 1 ? .win : .loss))
                VStack(alignment: .leading, spacing: 2) {
                    Text(fight.listTitle)
                        .ffType(.rowTitle)
                        .foregroundStyle(theme.text)
                    Text(fight.endedLabel ?? fight.listSubtitle)
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 8)
                FFAvatarStack(
                    monograms: fight.standings.map(\.person.initials),
                    visible: 2,
                    size: 26,
                    ring: theme.card
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
            .ffBorder(theme.hairline, radius: theme.radius.card)
        }
        .buttonStyle(FFPressStyle())
    }
}
