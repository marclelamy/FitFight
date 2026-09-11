import Foundation
import SwiftUI

enum MetricKind: String, Codable, Hashable {
    case steps

    var eyebrow: String {
        String(localized: "Steps total")
    }
}

enum FightStatus: String, Codable, Hashable {
    case live
    case invited
    case pending
    case finished
}

enum FightRefreshPhase: Equatable {
    case idle
    case readingHealth
    case uploading
    case updatingFights

    func statusText(line: Int) -> String {
        let lines: [String]
        switch self {
        case .idle:
            return ""
        case .readingHealth:
            lines = [
                String(localized: "Syncing your step activity…"),
                String(localized: "Asking Apple Health how far you walked…"),
            ]
        case .uploading:
            lines = [
                String(localized: "Updating the database…"),
                String(localized: "Filing your steps where they belong…"),
            ]
        case .updatingFights:
            lines = [
                String(localized: "Updating the challenges…"),
                String(localized: "Counting how far you are from your friend…"),
                String(localized: "Checking whether you’re still ahead…"),
            ]
        }
        return lines[line % lines.count]
    }
}

struct Person: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var handle: String
    var initials: String
    var isYou: Bool = false
    var photoURL: URL? = nil

    /// The design's cast photographs, cut out of the mocks into the asset catalogue.
    var photo: String { "Avatar-\(isYou ? "maya" : id)" }
}

extension FFAvatar {
    init(_ person: Person?, size: CGFloat = 24, selected: Bool = false, pending: Bool = false) {
        self.init(
            monogram: person?.initials ?? "?",
            size: size,
            selected: selected,
            photo: person?.photo,
            photoURL: person?.photoURL,
            dimmed: pending
        )
    }
}

struct Standing: Codable, Identifiable, Hashable {
    var person: Person
    var score: Double
    var invited: Bool = false
    var deferred: Bool = false
    var lastSyncedAt: Date? = nil
    var finalStepsComplete: Bool? = nil
    var rank: Int? = nil

    var id: String { person.id }
}

struct DayScore: Codable, Identifiable, Hashable {
    var person: Person
    var value: Double

    var id: String { person.id }
}

struct FightDay: Codable, Identifiable, Hashable {
    var label: String
    var scores: [DayScore]

    var id: String { label }
}

struct Fight: Codable, Identifiable, Hashable {
    var id: String
    var code: String
    var name: String
    var metric: MetricKind
    var lengthDays: Int
    var daysLeft: Int? = nil
    var endedLabel: String? = nil
    var actionText: String
    var status: FightStatus
    var rank: Int
    var of: Int
    var pending: Int
    var kickerPrefix: String = ""
    var kickerEmphasis: String
    var kickerRest: String = ""
    var listSubtitle: String
    var inviter: Person? = nil
    var invitePitch: String? = nil
    var inviteAction: String? = nil
    var paceNote: String? = nil
    var standingsMeta: String? = nil
    var standings: [Standing]
    var days: [FightDay] = []
    var windowStart: Date = Date()
    var windowEnd: Date = Date().addingTimeInterval(86400)
    var graceEndsAt: Date? = nil
    var serverState: String? = nil
    var joinCode: String? = nil
    var seriesId: String? = nil
    var recurring: Bool = false
    var pendingJoin: Bool = false
    var offersJoinNext: Bool = false

    var hasAction: Bool {
        !actionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Title shown on Fights. A typed name wins; otherwise the action; otherwise the stored name.
    var listTitle: String {
        Self.displayTitle(name: name, actionText: actionText)
    }

    static func displayTitle(name: String, actionText: String?) -> String {
        let stored = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = actionText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if stored.isEmpty || stored == "Steps Fight" || stored == "Défi de pas" {
            return action.isEmpty ? (stored.isEmpty ? String(localized: "Steps Fight") : stored) : action
        }
        return stored
    }

    var isTiedForFirst: Bool {
        standings.filter { !$0.invited && !$0.deferred && $0.rank == 1 }.count > 1
    }

    var durationLabel: String {
        let hours = max(1, Int((windowEnd.timeIntervalSince(windowStart) / 3_600).rounded()))
        return localizedDuration(hours: hours, days: lengthDays)
    }

    var timeLeftLabel: String {
        if hasPassedDeadline {
            return deadlineLabel
        }
        let remaining = RemainingTime.phrase(until: windowEnd)
        return String(
            localized: "fight.time-left",
            defaultValue: "\(remaining) left"
        )
    }

    /// Exact stored cutoff, in the phone’s local date and time.
    var deadlineLabel: String {
        let stamp = Self.deadlineStamp(windowEnd)
        if hasPassedDeadline {
            return endedLabel ?? String(
                localized: "fight.ended-on",
                defaultValue: "Ended \(stamp)"
            )
        }
        return String(
            localized: "fight.ends-at",
            defaultValue: "Ends \(stamp)"
        )
    }

    var timeAndDeadlineLabel: String {
        if hasPassedDeadline {
            return deadlineLabel
        }
        return String(
            localized: "fight.duration-end",
            defaultValue: "\(timeLeftLabel) · ends \(Self.deadlineStamp(windowEnd))"
        )
    }

    private var hasPassedDeadline: Bool {
        daysLeft == nil || status == .finished || status == .pending || windowEnd <= Date()
    }

    static func deadlineStamp(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var tab: FFTab = .fights {
        didSet {
            if oldValue != tab {
                openFightID = nil
            }
        }
    }

    @Published var openFightID: String?
    @Published var showingVersions = false
    @Published var showingRequests = false
    @Published var joined: Set<String> = []
    @Published var createError: String?
    @Published var pendingJoinable: Fight?
    @Published var pendingReferralError: String?
    @Published private(set) var isCreatingFight = false
    @Published private(set) var isJoiningFight = false
    @Published private(set) var isRefreshingFights = false
    @Published private(set) var refreshPhase: FightRefreshPhase = .idle
    @Published private(set) var refreshLine = 0

    var refreshStatusText: String {
        refreshPhase.statusText(line: refreshLine)
    }

    @Published var you: Person
    @Published var fights: [Fight]

    private var session: SessionStore?
    private let api = FitFightAPI()
    private var inviteTokens: [String: String] = [:]
    private var cachedUserID: UUID?
    private var refreshTask: Task<Void, Never>?
    private var refreshLineTask: Task<Void, Never>?
    private var pendingRefresh: (
        session: SessionStore,
        steps: HealthKitStepsStore,
        trigger: HealthKitStepsStore.SyncTrigger,
        requestAccess: Bool
    )?
    private static let pendingJoinCodeKey = "fitfight.pendingJoinCode"
    private static let pendingReferralCodeKey = "fitfight.pendingReferralCode"
    private static let pendingReferralUserKey = "fitfight.pendingReferralUser"

    private static var fightsCachePrefix: String {
        "fitfight.fights.\(Bundle.main.preferredLocalizations.first ?? "en")."
    }

    static var preview: AppModel { AppModel(fixtures: true) }

    static var shouldLoadFixtures: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["FF_SHOOT"] == "1" || env["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    convenience init() {
        self.init(fixtures: Self.shouldLoadFixtures)
    }

    convenience init(preview: Void) {
        self.init(fixtures: true)
    }

    init(fixtures: Bool) {
        let bundle = AppModelFixtures.load()
        you = bundle.you
        if fixtures {
            fights = bundle.fights
        } else {
            fights = []
        }
    }

    func fight(id: String) -> Fight? {
        fights.first { $0.id.caseInsensitiveCompare(id) == .orderedSame }
            ?? pendingJoinable.flatMap { $0.id.caseInsensitiveCompare(id) == .orderedSame ? $0 : nil }
    }

    func canonicalFight(for id: String) -> Fight? {
        guard let fight = fight(id: id) else { return nil }
        guard let seriesId = fight.seriesId else { return fight }
        return fights
            .filter { $0.seriesId == seriesId }
            .max(by: { Self.preferredCanonicalFight($0, $1) == $0 })
    }

    func seriesHistory(for fight: Fight) -> [Fight] {
        guard let seriesId = fight.seriesId else { return [] }
        return fights
            .filter { $0.seriesId == seriesId && $0.id != fight.id }
            .sorted { $0.windowStart > $1.windowStart }
    }

    func fightResult(for fight: Fight) -> FFResult {
        if fight.standings.contains(where: { $0.person.isYou && $0.deferred }) {
            return .draw
        }
        if fight.status == .pending {
            return .pending
        }
        if let state = fight.serverState, state != "final", state != "cancelled" {
            return .pending
        }
        if fight.isTiedForFirst {
            return .draw
        }
        return fight.rank == 1 ? .win : .loss
    }

    private var canonicalFights: [Fight] {
        var chosen: [String: Fight] = [:]
        for fight in fights {
            let key = fight.seriesId ?? fight.id
            if let existing = chosen[key] {
                chosen[key] = Self.preferredCanonicalFight(existing, fight)
            } else {
                chosen[key] = fight
            }
        }
        return Array(chosen.values)
    }

    var live: [Fight] {
        canonicalFights
            .filter { $0.status == .live }
            .sorted { $0.windowStart > $1.windowStart }
    }
    var invitations: [Fight] {
        canonicalFights
            .filter { $0.status == .invited }
            .sorted { $0.windowStart > $1.windowStart }
    }
    var finished: [Fight] {
        canonicalFights
            .filter { $0.status == .pending || $0.status == .finished }
            .sorted { $0.windowStart > $1.windowStart }
    }

    func youStanding(in fight: Fight) -> Standing? {
        fight.standings.first { $0.person.isYou }
    }

    func formatScore(_ value: Double, metric _: MetricKind) -> String {
        value.formatted(
            .number
                .notation(.compactName)
                .precision(.fractionLength(value >= 1_000 ? 0...1 : 0...0))
        )
    }

    func formatLastSync(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return String(localized: "Not synced yet") }
        let elapsed = max(0, now.timeIntervalSince(date))
        if elapsed < 60 { return String(localized: "Just now") }
        if elapsed < 3_600 {
            let minutes = Int(elapsed / 60)
            return String(localized: "health.minutes-ago", defaultValue: "\(minutes) minutes ago")
        }
        if elapsed < 86_400 {
            let hours = Int(elapsed / 3_600)
            return String(localized: "health.hours-ago", defaultValue: "\(hours) hours ago")
        }
        let days = Int(elapsed / 86_400)
        return String(localized: "health.days-ago", defaultValue: "\(days) days ago")
    }

    func formatStandingFreshness(_ standing: Standing, fight: Fight, now: Date) -> String {
        guard fight.windowEnd <= now else { return formatLastSync(standing.lastSyncedAt, now: now) }
        if standing.finalStepsComplete == true {
            guard let lastSyncedAt = standing.lastSyncedAt else {
                return String(localized: "Final steps synced")
            }
            let freshness = formatLastSync(lastSyncedAt, now: now)
            return String(
                localized: "health.final-steps-synced-at",
                defaultValue: "Final steps synced · \(freshness)"
            )
        }
        if fight.serverState == "final", !standing.invited, !standing.deferred {
            return String(localized: "Did not sync · forfeited")
        }
        let finalized = fight.serverState == "final" || fight.serverState == "cancelled"
        if let lastSyncedAt = standing.lastSyncedAt {
            let freshness = formatLastSync(lastSyncedAt, now: now)
            return finalized
                ? String(
                    localized: "health.finalized-last-steps-at",
                    defaultValue: "Finalized from last available steps · \(freshness)"
                )
                : String(
                    localized: "health.waiting-final-steps-at",
                    defaultValue: "Waiting for final steps · \(freshness)"
                )
        }
        return finalized
            ? String(localized: "Finalized without synced steps")
            : String(localized: "Waiting for first sync")
    }

    func refreshFromServer() async {
        guard let session else { return }
        await refreshFromServer(session: session)
    }

    func restoreCachedFights(session: SessionStore) {
        guard let userID = session.authSession?.user.id ?? session.client.auth.currentUser?.id else {
            cachedUserID = nil
            fights = []
            return
        }
        guard cachedUserID != userID else { return }
        cachedUserID = userID
        guard
            let data = UserDefaults.standard.data(forKey: Self.fightsCachePrefix + userID.uuidString),
            let cached = try? JSONDecoder().decode([Fight].self, from: data)
        else {
            fights = []
            return
        }
        fights = cached
    }

    func refreshFights(
        session: SessionStore,
        steps: HealthKitStepsStore,
        trigger: HealthKitStepsStore.SyncTrigger = .foreground,
        requestAccess: Bool = false
    ) async {
        if refreshTask != nil {
            pendingRefresh = (session, steps, trigger, requestAccess)
            return
        }
        isRefreshingFights = true
        refreshPhase = .readingHealth
        let work = Task { @MainActor in
            defer {
                self.refreshLineTask?.cancel()
                self.refreshLineTask = nil
                self.refreshTask = nil
                self.isRefreshingFights = false
                self.refreshPhase = .idle
                self.refreshLine = 0
            }
            var current = (session: session, steps: steps, trigger: trigger, requestAccess: requestAccess)
            repeat {
                self.pendingRefresh = nil
                await self.performRefreshFights(
                    session: current.session,
                    steps: current.steps,
                    trigger: current.trigger,
                    requestAccess: current.requestAccess
                )
                if let pending = self.pendingRefresh {
                    current = pending
                }
            } while self.pendingRefresh != nil
        }
        refreshTask = work
        guard !Task.isCancelled else { return }
        await work.value
    }

    private func performRefreshFights(
        session: SessionStore,
        steps: HealthKitStepsStore,
        trigger: HealthKitStepsStore.SyncTrigger,
        requestAccess: Bool
    ) async {
        let userID = session.authSession?.user.id ?? session.client.auth.currentUser?.id
        let trace = HealthKitSyncTrace(trigger: trigger)

        await holdRefreshPhase(.readingHealth) {
            await steps.refresh(requestAccess: requestAccess, trace: trace)
        }
        guard (session.authSession?.user.id ?? session.client.auth.currentUser?.id) == userID else {
            trace.fail(.attemptExpired)
            steps.completeAttempt(trace, session: session, userID: userID)
            return
        }
        if session.authSession != nil {
            await holdRefreshPhase(.uploading) {
                await steps.syncToBackend(session: session, trigger: trigger, trace: trace)
            }
        }
        guard (session.authSession?.user.id ?? session.client.auth.currentUser?.id) == userID else {
            trace.fail(.attemptExpired)
            steps.completeAttempt(trace, session: session, userID: userID)
            return
        }
        await holdRefreshPhase(.updatingFights) {
            await refreshFromServer(session: session, trace: trace)
        }
        steps.completeAttempt(trace, session: session, userID: userID)
    }

    private func holdRefreshPhase(_ phase: FightRefreshPhase, work: () async -> Void) async {
        refreshPhase = phase
        refreshLine = 0
        refreshLineTask?.cancel()
        refreshLineTask = Task { @MainActor in
            var line = 0
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1.15)) } catch { return }
                line += 1
                self.refreshLine = line
            }
        }
        let start = ContinuousClock.now
        await work()
        refreshLineTask?.cancel()
        refreshLineTask = nil
        let elapsed = start.duration(to: .now)
        let minimum = Duration.milliseconds(480)
        if elapsed < minimum {
            try? await Task.sleep(for: minimum - elapsed)
        }
    }

    func applyLocalHealthKitScores(_ sync: FitFightHealthKitStepSync) {
        let totals = Dictionary(uniqueKeysWithValues: sync.fightAggregates.map {
            ($0.fightId.lowercased(), Double($0.steps))
        })
        guard !totals.isEmpty else { return }
        let now = Date()
        fights = fights.map { fight in
            guard fight.status == .live || fight.status == .pending,
                  let score = totals[fight.id.lowercased()],
                  let index = fight.standings.firstIndex(where: {
                      $0.person.isYou && !$0.invited && !$0.deferred
                  })
            else { return fight }
            var next = fight
            next.standings[index].score = score
            next.standings[index].lastSyncedAt = now
            if next.status == .pending {
                next.standings[index].finalStepsComplete = true
            }
            next.standings = Self.orderedStandings(next.standings, status: next.status)
            let joined = next.standings.filter { !$0.invited && !$0.deferred }
            next.rank = joined.firstIndex { $0.person.isYou }.map { $0 + 1 } ?? next.rank
            next.of = max(joined.count, 1)
            return next
        }
    }

    func removeCachedFights(for userID: UUID) {
        UserDefaults.standard.removeObject(forKey: Self.fightsCachePrefix + userID.uuidString)
        if cachedUserID == userID {
            cachedUserID = nil
            fights = []
        }
    }

    func refreshFromServer(session: SessionStore, trace: HealthKitSyncTrace? = nil) async {
        self.session = session
        guard let userId = session.authSession?.user.id ?? session.client.auth.currentUser?.id else {
            return
        }
        if let profile = session.profile {
            you = Self.person(from: profile, isYou: true)
        }
        let attempt = trace ?? HealthKitSyncTrace(trigger: .foreground)
        defer {
            if trace == nil {
                HealthKitStepsStore.shared.completeAttempt(attempt, session: session, userID: userId)
            }
        }

        do {
            let token = try await attempt.measure(.session) { try await session.freshAccessToken() }
            guard session.authSession?.user.id == userId else { throw CancellationError() }
            let snapshot = try await api.fightsSnapshot(accessToken: token, trace: attempt)
            try Task.checkCancellation()
            let profiles = Dictionary(uniqueKeysWithValues: snapshot.profiles.map { ($0.userId, $0) })
            let members = Dictionary(grouping: snapshot.members, by: \.fightId)
            let mine = Dictionary(uniqueKeysWithValues: snapshot.members.filter { $0.userId == userId }.map { ($0.fightId, $0) })
            let series = Dictionary(uniqueKeysWithValues: snapshot.series.map { ($0.id, $0) })
            let loaded = snapshot.fights.compactMap { row -> Fight? in
                guard var fight = Self.mapFight(
                    row, members: members[row.id] ?? [], mine: mine[row.id], profiles: profiles,
                    series: row.seriesId.flatMap { series[$0] }, userId: userId, formatScore: formatScore
                ) else { return nil }
                fight.days = Self.dayCards(
                    from: snapshot.stepDays, standings: fight.standings, window: Self.fightDayWindow(fight)
                )
                return fight
            }
            guard session.authSession?.user.id == userId else { throw CancellationError() }
            fights = loaded
            cachedUserID = userId
            if let data = try? JSONEncoder().encode(loaded) {
                UserDefaults.standard.set(data, forKey: Self.fightsCachePrefix + userId.uuidString)
            }
        } catch {
            attempt.fail(HealthKitStepsStore.errorCode(for: error))
            // Keep the last successful result visible while the phone is offline.
        }
    }

    /// Locks Start fight immediately so extra taps cannot insert another row.
    func beginCreateFight() -> Bool {
        guard !isCreatingFight else { return false }
        isCreatingFight = true
        createError = nil
        return true
    }

    func createAndStartFight(
        name: String = "",
        startsAt: Date,
        endsAt: Date,
        actionText: String,
        inviteHandles: [String],
        visibility: String = "invite_only",
        recurring: Bool = true
    ) async {
        if !isCreatingFight {
            isCreatingFight = true
        }
        defer { isCreatingFight = false }
        createError = nil
        guard let access = session?.authSession?.accessToken, api.isConfigured else {
            createError = String(localized: "Sign in to start a fight.")
            return
        }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = actionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count <= 120 else {
            createError = String(localized: "Keep the title to 120 characters.")
            return
        }
        guard action.count <= 120 else {
            createError = String(localized: "Keep the action to 120 characters.")
            return
        }
        let storedName = title.isEmpty
            ? (action.isEmpty ? String(localized: "Steps Fight") : action)
            : title

        let handles = inviteHandles.reduce(into: [String]()) { result, raw in
            let handle = SessionStore.strippedHandle(raw)
            if SessionStore.isValidHandle(handle), !result.contains(handle) {
                result.append(handle)
            }
        }
        let payload = FitFightCreateFight(
            name: storedName,
            startsAt: startsAt,
            endsAt: max(endsAt, startsAt.addingTimeInterval(60)),
            timeZone: TimeZone.current.identifier,
            outcomeRule: "highest_total",
            goalPolicy: "shared",
            defaultGoalValue: nil,
            stakeKind: "action",
            stakeMinor: nil,
            currency: nil,
            actionText: action.isEmpty ? nil : action,
            inviteHandles: handles.isEmpty ? nil : handles,
            start: "now",
            visibility: visibility,
            recurring: recurring
        )

        do {
            let created = try await api.createFight(
                payload,
                accessToken: access,
                idempotencyKey: UUID().uuidString
            )
            await refreshFromServer()
            tab = .fights
            openFightID = created.id.uuidString
        } catch {
            createError = (error as? LiveFightError)?.errorDescription
                ?? (error as? FitFightAPIError)?.errorDescription
                ?? String(localized: "Couldn’t start the fight.")
        }
    }

    func acceptInvite(token: String, start: String = "now") async throws {
        createError = nil
        guard let access = session?.authSession?.accessToken else {
            throw FitFightAPIError.notConfigured
        }
        let summary = try await api.accept(token: token, accessToken: access, start: start)
        inviteTokens[summary.id.uuidString] = token
        await refreshFromServer()
    }

    func acceptFight(id: String, start: String = "now") async {
        guard !isJoiningFight else { return }
        isJoiningFight = true
        defer { isJoiningFight = false }
        createError = nil
        if let pending = pendingJoinable, pending.id == id, pending.pendingJoin {
            await joinPendingFight(pending, start: start)
            return
        }
        if let token = inviteTokens[id], api.isConfigured {
            do {
                try await acceptInvite(token: token, start: start)
            } catch {
                createError = (error as? FitFightAPIError)?.errorDescription
                    ?? String(localized: "Couldn’t accept.")
            }
            return
        }
        guard let session, session.authSession != nil, let fightID = UUID(uuidString: id) else {
            createError = String(localized: "Sign in to accept this fight.")
            return
        }
        do {
            let token = try await session.freshAccessToken()
            _ = try await api.acceptFight(fightID: fightID, accessToken: token, start: start)
            joined.insert(id)
            await refreshFromServer()
        } catch {
            createError = String(localized: "Couldn’t accept.")
        }
    }

    func declineFight(id: String) async {
        createError = nil
        if pendingJoinable?.id == id {
            pendingJoinable = nil
            openFightID = nil
            return
        }
        guard let session, session.authSession != nil, let fightID = UUID(uuidString: id) else {
            createError = String(localized: "Sign in to decline this fight.")
            return
        }
        do {
            let token = try await session.freshAccessToken()
            _ = try await api.declineFight(fightID: fightID, accessToken: token)
            await refreshFromServer()
        } catch {
            createError = String(localized: "Couldn’t decline.")
        }
    }

    func listJoinableFights(session: SessionStore) async -> [FitFightJoinableFight] {
        self.session = session
        guard let access = session.authSession?.accessToken, api.isConfigured else {
            return []
        }
        do {
            return try await api.listJoinableFights(accessToken: access)
        } catch {
            createError = (error as? FitFightAPIError)?.errorDescription
                ?? String(localized: "Couldn’t load joinable fights.")
            return []
        }
    }

    func openJoinable(_ summary: FitFightJoinableFight, session: SessionStore) async {
        self.session = session
        createError = nil
        if summary.alreadyMember {
            pendingJoinable = nil
            tab = .fights
            openFightID = summary.fightId.uuidString
            await refreshFromServer()
            return
        }
        pendingJoinable = Self.fight(from: summary, you: you)
        if tab != .newFight {
            tab = .newFight
        }
    }

    func openJoinCode(_ raw: String, session: SessionStore) async {
        self.session = session
        createError = nil
        let code = raw.replacingOccurrences(of: "[\\s-]", with: "", options: .regularExpression).uppercased()
        guard code.count == 4 else {
            createError = String(localized: "Enter the 4-character code.")
            return
        }
        guard let userID = session.authSession?.user.id,
              let access = session.authSession?.accessToken, api.isConfigured,
              session.profile != nil, !session.needsOnboarding else {
            UserDefaults.standard.set(code, forKey: Self.pendingJoinCodeKey)
            createError = String(localized: "Sign in to join this fight.")
            return
        }
        do {
            let summary = try await api.joinableFight(code: code, accessToken: access)
            guard session.authSession?.user.id == userID else { return }
            if UserDefaults.standard.string(forKey: Self.pendingJoinCodeKey) == code {
                UserDefaults.standard.removeObject(forKey: Self.pendingJoinCodeKey)
            }
            await openJoinable(summary, session: session)
        } catch {
            guard session.authSession?.user.id == userID else { return }
            createError = (error as? FitFightAPIError)?.errorDescription
                ?? String(localized: "Couldn’t find that fight.")
        }
    }

    func handleOpenURL(_ url: URL, session: SessionStore) async {
        guard url.scheme == "https", url.host == APIConfig.publicOrigin.host,
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return }
        let parts = url.path.split(separator: "/")
        guard parts.count == 2 else { return }
        let referral: UUID?
        if parts[0] == "r", let code = UUID(uuidString: String(parts[1])) {
            referral = code
        } else if let code = Self.joinCode(from: url) {
            UserDefaults.standard.set(code, forKey: Self.pendingJoinCodeKey)
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            referral = items.first(where: { $0.name == "ref" })
                .flatMap { $0.value }.flatMap { UUID(uuidString: $0) }
        } else {
            return
        }
        if let referral {
            UserDefaults.standard.set(referral.uuidString, forKey: Self.pendingReferralCodeKey)
            UserDefaults.standard.set(session.authSession?.user.id.uuidString, forKey: Self.pendingReferralUserKey)
        }
        await consumePendingLinks(session: session)
    }

    func consumePendingLinks(session: SessionStore) async {
        guard !session.needsOnboarding, let profile = session.profile,
              session.authSession?.user.id == profile.userId else { return }
        if let code = UserDefaults.standard.string(forKey: Self.pendingJoinCodeKey) {
            await openJoinCode(code, session: session)
            guard session.authSession?.user.id == profile.userId else { return }
            if createError != nil { tab = .newFight }
        }
        guard let raw = UserDefaults.standard.string(forKey: Self.pendingReferralCodeKey),
              let code = UUID(uuidString: raw) else { return }
        if let owner = UserDefaults.standard.string(forKey: Self.pendingReferralUserKey),
           owner != profile.userId.uuidString {
            UserDefaults.standard.removeObject(forKey: Self.pendingReferralCodeKey)
            UserDefaults.standard.removeObject(forKey: Self.pendingReferralUserKey)
            return
        }
        UserDefaults.standard.set(profile.userId.uuidString, forKey: Self.pendingReferralUserKey)
        pendingReferralError = nil
        do {
            let access = try await session.freshAccessToken()
            guard session.authSession?.user.id == profile.userId else { return }
            _ = try await api.claimReferral(code: code, accessToken: access)
            guard session.authSession?.user.id == profile.userId else { return }
            if UserDefaults.standard.string(forKey: Self.pendingReferralCodeKey) == raw {
                UserDefaults.standard.removeObject(forKey: Self.pendingReferralCodeKey)
                UserDefaults.standard.removeObject(forKey: Self.pendingReferralUserKey)
            }
        } catch {
            guard session.authSession?.user.id == profile.userId else { return }
            pendingReferralError = String(localized: "Your referral hasn’t been saved yet. Check your connection and try again.")
        }
    }

    private func joinPendingFight(_ fight: Fight, start: String = "now") async {
        guard let access = session?.authSession?.accessToken, api.isConfigured else {
            createError = String(localized: "Sign in to join this fight.")
            return
        }
        guard let fightID = UUID(uuidString: fight.id) else {
            createError = String(localized: "Couldn’t join.")
            return
        }
        do {
            _ = try await api.joinFight(code: fight.joinCode, fightID: fightID, accessToken: access, start: start)
            joined.insert(fight.id)
            await refreshFromServer()
            pendingJoinable = nil
            tab = .fights
            openFightID = fight.id
        } catch {
            createError = (error as? FitFightAPIError)?.errorDescription
                ?? String(localized: "Couldn’t join.")
        }
    }

    func leaveFight(id: String) async {
        createError = nil
        guard let access = session?.authSession?.accessToken, api.isConfigured else {
            createError = String(localized: "Sign in to leave this fight.")
            return
        }
        guard let fightID = UUID(uuidString: id) else {
            createError = String(localized: "Couldn’t leave.")
            return
        }
        do {
            _ = try await api.leaveFight(fightID: fightID, accessToken: access)
            openFightID = nil
            joined.remove(id)
            await refreshFromServer()
        } catch {
            createError = (error as? FitFightAPIError)?.errorDescription
                ?? String(localized: "Couldn’t leave.")
        }
    }

    static func joinCode(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 2, parts[0] == "j" else {
            return nil
        }
        let code = parts[1]
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
        let alphabet = CharacterSet(charactersIn: "23456789ABCDEFGHJKMNPQRSTVWXYZ")
        guard code.count == 4, code.unicodeScalars.allSatisfy({ alphabet.contains($0) }) else {
            return nil
        }
        return code
    }

    private static func fight(from summary: FitFightJoinableFight, you: Person) -> Fight {
        let starts = FightRow.parse(summary.startsAt) ?? Date()
        let ends = FightRow.parse(summary.endsAt) ?? starts.addingTimeInterval(86400)
        let lengthDays = max(1, Calendar.current.dateComponents([.day], from: starts, to: ends).day ?? 1)
        let owner = Person(
            id: summary.ownerHandle,
            name: "@\(summary.ownerHandle)",
            handle: "@\(summary.ownerHandle)",
            initials: String(summary.ownerHandle.prefix(2)).uppercased()
        )
        let action = summary.actionText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let offersJoinNext = summary.canJoinNext ?? (summary.recurring && Self.isAfterFightStartDay(starts) && !summary.alreadyMember)
        return Fight(
            id: summary.fightId.uuidString,
            code: summary.joinCode,
            name: summary.name,
            metric: .steps,
            lengthDays: lengthDays,
            daysLeft: max(1, Calendar.current.dateComponents([.day], from: Date(), to: ends).day ?? 1),
            actionText: (action?.isEmpty == false ? action : nil) ?? "",
            status: .invited,
            rank: 0,
            of: max(summary.memberCount, 1),
            pending: 0,
            kickerEmphasis: String(
                localized: "fight.challenged-you",
                defaultValue: "@\(summary.ownerHandle) challenged you"
            ),
            listSubtitle: "@\(summary.ownerHandle) · \(summary.memberCount)",
            inviter: owner,
            invitePitch: String(
                localized: "fight.challenged-you",
                defaultValue: "@\(summary.ownerHandle) challenged you"
            ),
            inviteAction: String(localized: "Join fight"),
            standings: [
                Standing(person: you, score: 0),
                Standing(person: owner, score: 0),
            ],
            windowStart: starts,
            windowEnd: ends,
            joinCode: summary.joinCode,
            recurring: summary.recurring,
            pendingJoin: true,
            offersJoinNext: offersJoinNext
        )
    }

    private static func fightDayWindow(_ fight: Fight) -> Set<String> {
        let calendar = Calendar.current
        var days: [String] = []
        var cursor = calendar.startOfDay(for: fight.windowStart)
        while cursor < fight.windowEnd && days.count <= 40 {
            days.append(dayStamp(cursor))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return Set(days)
    }

    private static func dayCards(
        from days: [StepDayRow],
        standings: [Standing],
        window: Set<String>
    ) -> [FightDay] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let label = DateFormatter()
        label.locale = .autoupdatingCurrent
        label.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return window.sorted().map { day in
            let scores = standings.filter { !$0.invited && !$0.deferred }.map { row in
                let personID = UUID(uuidString: row.person.id)
                let value = days.first { $0.userId == personID && $0.day == day }?.steps ?? 0
                return DayScore(person: row.person, value: Double(value))
            }
            let date = formatter.date(from: day) ?? Date()
            return FightDay(label: label.string(from: date), scores: scores)
        }
    }

    private static func dayStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func person(from profile: FitFightProfile, isYou: Bool) -> Person {
        Person(
            id: profile.userId.uuidString,
            name: profile.atHandle,
            handle: profile.atHandle,
            initials: profile.initials,
            isYou: isYou,
            photoURL: profile.avatar?.url
        )
    }

    func openFightFromFeed(id: String) {
        let fightID = canonicalFight(for: id)?.id ?? id
        tab = .fights
        Task { @MainActor in
            self.openFightID = fightID
        }
    }

    private static func mapFight(
        _ row: FightRow,
        members: [MemberRow],
        mine: MemberRow?,
        profiles: [UUID: FitFightProfile],
        series: SeriesRow?,
        userId: UUID,
        formatScore: (Double, MetricKind) -> String
    ) -> Fight? {
        if row.state == "draft" || mine?.state == "declined" || mine?.state == "withdrawn" { return nil }

        let pendingMembers = members.filter { $0.state == "invited" }

        let starts = row.startsAtDate
        let ends = row.endsAtDate
        let lengthDays = max(1, Calendar.current.dateComponents([.day], from: starts, to: ends).day ?? 1)
        let lengthHours = max(1, Int((ends.timeIntervalSince(starts) / 3_600).rounded()))
        let durationLabel = localizedDuration(hours: lengthHours, days: lengthDays)

        let status: FightStatus
        if mine?.state == "invited" && row.state != "final" && row.state != "cancelled" {
            status = .invited
        } else if row.state == "final" || row.state == "cancelled" {
            status = .finished
        } else if row.state == "awaiting_final_sync" || (row.state == "live" && ends < Date()) {
            status = .pending
        } else {
            status = .live
        }

        let daysLeft: Int?
        if row.state == "awaiting_final_sync" {
            daysLeft = 0
        } else if status == .finished {
            daysLeft = nil
        } else {
            let remaining = Calendar.current.dateComponents([.day, .hour, .minute, .second], from: Date(), to: ends)
            let hasPartialDay = (remaining.hour ?? 0) > 0
                || (remaining.minute ?? 0) > 0
                || (remaining.second ?? 0) > 0
            daysLeft = max(1, (remaining.day ?? 0) + (hasPartialDay ? 1 : 0))
        }
        let remainingLabel = RemainingTime.phrase(until: ends)

        let peopleUnsorted = members.map { member -> Standing in
            let profile = profiles[member.userId]
            let person: Person
            if let profile {
                person = Self.person(from: profile, isYou: member.userId == userId)
            } else {
                person = Person(
                    id: member.userId.uuidString,
                    name: member.userId == userId ? String(localized: "You") : "@user",
                    handle: "@user",
                    initials: "FF",
                    isYou: member.userId == userId
                )
            }
            let score = member.currentValue ?? member.finalValue ?? 0
            return Standing(
                person: person,
                score: member.state == "deferred" ? 0 : score,
                invited: member.state == "invited",
                deferred: member.state == "deferred",
                lastSyncedAt: member.lastSyncedAt,
                finalStepsComplete: member.finalStepsComplete,
                rank: member.rank
            )
        }
        let people = orderedStandings(peopleUnsorted, status: status)

        let joined = people.filter { !$0.invited && !$0.deferred }
        let waiting = people.filter(\.deferred)
        let youRow = people.first { $0.person.isYou }
        let listRank = youRow.flatMap { row in joined.firstIndex { $0.person.id == row.person.id }.map { $0 + 1 } }
            ?? mine?.rank
            ?? 0
        let rank = (status == .finished ? mine?.rank : nil) ?? listRank
        let tiedForFirst = people.filter { !$0.invited && !$0.deferred && $0.rank == 1 }.count > 1
        let of = max(joined.count, 1)
        let owner = profiles[row.ownerId].map { Self.person(from: $0, isYou: $0.userId == userId) }
        let ownerName = owner?.name ?? String(localized: "Someone")

        let actionText = row.actionText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = actionText?.isEmpty == false ? (actionText ?? "") : ""

        var kickerPrefix = ""
        var kickerEmphasis = ""
        var kickerRest = ""
        var listSubtitle = ""
        var invitePitch: String?
        var inviteAction: String?
        var endedLabel: String?

        switch status {
        case .invited:
            invitePitch = String(
                localized: "fight.challenged-you",
                defaultValue: "\(ownerName) challenged you"
            )
            inviteAction = String(localized: "Accept")
            kickerEmphasis = invitePitch ?? ""
            listSubtitle = "\(ownerName) · \(durationLabel)"
        case .finished:
            endedLabel = String(
                localized: "fight.ended-on",
                defaultValue: "Ended \(Fight.deadlineStamp(ends))"
            )
            if youRow?.deferred == true {
                listSubtitle = endedLabel ?? String(localized: "Ended")
                kickerEmphasis = String(localized: "Started next round")
            } else if row.state == "final" && tiedForFirst {
                listSubtitle = String(
                    localized: "fight.finished-tied",
                    defaultValue: "\(endedLabel ?? String(localized: "Ended")) · Tied"
                )
                kickerEmphasis = String(localized: "Tied")
            } else {
                listSubtitle = String(
                    localized: "fight.finished-position",
                    defaultValue: "\(endedLabel ?? String(localized: "Ended")) · \(Self.ordinal(rank)) of \(of)"
                )
                if row.state == "final" {
                    kickerPrefix = rank == 1 ? String(localized: "Won by") : String(localized: "Finished")
                } else {
                    kickerPrefix = String(localized: "Finished")
                }
                kickerEmphasis = Self.ordinal(rank)
            }
        case .pending:
            endedLabel = String(
                localized: "fight.ended-on",
                defaultValue: "Ended \(Fight.deadlineStamp(ends))"
            )
            listSubtitle = String(
                localized: "fight.pending-ended-on",
                defaultValue: "Pending · Ended \(Fight.deadlineStamp(ends))"
            )
            if youRow?.deferred == true {
                kickerEmphasis = String(localized: "Started next round")
            } else if youRow?.finalStepsComplete == true {
                let submitted = people.filter { !$0.invited && !$0.deferred && $0.finalStepsComplete == true }
                let submittedRank = youRow.flatMap { you in
                    submitted.firstIndex { $0.person.id == you.person.id }.map { $0 + 1 }
                } ?? 0
                kickerEmphasis = submittedRank == 1
                    ? String(localized: "Tentative lead")
                    : String(localized: "Tentative loss")
            } else {
                kickerEmphasis = String(localized: "Pending — open the app")
            }
        case .live:
            if row.state == "awaiting_final_sync" {
                kickerEmphasis = String(localized: "Syncing final steps")
                listSubtitle = kickerEmphasis
            } else if youRow?.deferred == true {
                kickerEmphasis = String(localized: "Starts next round")
                listSubtitle = kickerEmphasis
            } else if let youRow, let leader = joined.first, !youRow.invited {
                if youRow.person.id == leader.person.id, let runnerUp = joined.dropFirst().first {
                    let gap = leader.score - runnerUp.score
                    kickerPrefix = gap == 0 ? "" : String(localized: "Leading by")
                    kickerEmphasis = gap == 0
                        ? String(localized: "Tied")
                        : String(
                            localized: "fight.steps-value",
                            defaultValue: "\(formatScore(gap, .steps)) steps"
                        )
                    kickerRest = String(
                        localized: "fight.time-to-go",
                        defaultValue: "with \(remainingLabel) to go"
                    )
                    listSubtitle = gap == 0
                        ? String(
                            localized: "fight.tied-time-to-go",
                            defaultValue: "Tied with \(remainingLabel) to go"
                        )
                        : String(
                            localized: "fight.leading-time-to-go",
                            defaultValue: "Leading by \(kickerEmphasis) with \(remainingLabel) to go"
                        )
                } else if youRow.person.id == leader.person.id {
                    kickerEmphasis = String(
                        localized: "fight.time-left",
                        defaultValue: "\(remainingLabel) left"
                    )
                    listSubtitle = kickerEmphasis
                } else {
                    let gap = leader.score - youRow.score
                    kickerEmphasis = gap == 0
                        ? String(localized: "Tied")
                        : String(
                            localized: "fight.steps-value",
                            defaultValue: "\(formatScore(gap, .steps)) steps"
                        )
                    kickerRest = gap == 0
                        ? ""
                        : String(
                            localized: "fight.behind-person",
                            defaultValue: "behind \(leader.person.name)"
                        )
                    listSubtitle = gap == 0
                        ? String(localized: "Tied")
                        : String(
                            localized: "fight.steps-behind-person",
                            defaultValue: "\(kickerEmphasis) behind \(leader.person.name)"
                        )
                }
            } else {
                kickerEmphasis = String(
                    localized: "fight.time-left",
                    defaultValue: "\(remainingLabel) left"
                )
                listSubtitle = kickerEmphasis
            }
        }

        let short = row.id.uuidString.replacingOccurrences(of: "-", with: "")
        let code = series?.joinCode ?? ("FIGHT-" + String(short.prefix(3)).uppercased())

        return Fight(
            id: row.id.uuidString,
            code: code,
            name: row.name,
            metric: .steps,
            lengthDays: lengthDays,
            daysLeft: daysLeft,
            endedLabel: endedLabel,
            actionText: action,
            status: status,
            rank: rank,
            of: of,
            pending: pendingMembers.count,
            kickerPrefix: kickerPrefix,
            kickerEmphasis: kickerEmphasis,
            kickerRest: kickerRest,
            listSubtitle: listSubtitle,
            inviter: owner,
            invitePitch: invitePitch,
            inviteAction: inviteAction,
            standingsMeta: waiting.isEmpty
                ? nil
                : String(
                    localized: "fight.standings-next",
                    defaultValue: "\(joined.count) racing · \(waiting.count) start next"
                ),
            standings: people,
            windowStart: starts,
            windowEnd: ends,
            graceEndsAt: row.graceEndsAtDate,
            serverState: row.state,
            joinCode: series?.joinCode,
            seriesId: series?.id.uuidString,
            recurring: series?.recurring ?? false,
            offersJoinNext: (series?.recurring ?? false)
                && Self.isAfterFightStartDay(starts)
                && mine?.state == "invited"
        )
    }

    private static func isAfterFightStartDay(_ start: Date, now: Date = Date()) -> Bool {
        let calendar = Calendar.current
        return calendar.startOfDay(for: now) > calendar.startOfDay(for: start)
    }

    private static func fightStatusPriority(_ status: FightStatus) -> Int {
        switch status {
        case .live: return 4
        case .pending: return 3
        case .invited: return 2
        case .finished: return 1
        }
    }

    static func preferredCanonicalFight(_ a: Fight, _ b: Fight) -> Fight {
        let left = fightStatusPriority(a.status)
        let right = fightStatusPriority(b.status)
        if left != right { return left > right ? a : b }
        if a.windowStart != b.windowStart { return a.windowStart > b.windowStart ? a : b }
        return a
    }

    private static func ordinal(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: value)) ?? value.formatted()
    }

    private static func orderedStandings(_ standings: [Standing], status: FightStatus) -> [Standing] {
        standings.sorted { lhs, rhs in
            if status == .pending {
                let lhsOpen = !lhs.invited && !lhs.deferred && lhs.finalStepsComplete != true
                let rhsOpen = !rhs.invited && !rhs.deferred && rhs.finalStepsComplete != true
                if lhsOpen != rhsOpen { return lhsOpen && !rhsOpen }
            }
            if lhs.invited != rhs.invited { return !lhs.invited && rhs.invited }
            if lhs.deferred != rhs.deferred { return !lhs.deferred && rhs.deferred }
            if status == .finished, let lhsRank = lhs.rank, let rhsRank = rhs.rank, lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            if lhs.score == rhs.score { return lhs.person.name < rhs.person.name }
            return lhs.score > rhs.score
        }
    }
}

enum LiveFightError: LocalizedError {
    case notSignedIn
    case unknownHandle(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return String(localized: "Sign in to start a fight.")
        case .unknownHandle(let handle):
            return String(
                localized: "fight.unknown-handle",
                defaultValue: "No one with @\(handle). They need to open the app and pick a username first."
            )
        }
    }
}

private func localizedDuration(hours: Int, days: Int) -> String {
    if hours <= 6 {
        return String(
            localized: "duration.hours",
            defaultValue: "\(hours) hours"
        )
    }
    return String(
        localized: "duration.days",
        defaultValue: "\(days) days"
    )
}

private enum AppModelFixtures {
    struct Bundle {
        var you: Person
        var fights: [Fight]
    }

    static func load() -> Bundle {
        let isFrench = Foundation.Bundle.main.preferredLocalizations.first?.hasPrefix("fr") == true
        let leo = Person(id: "leo", name: "@leo_runs", handle: "@leo_runs", initials: "L")
        let sam = Person(id: "sam", name: "@sam_sweats", handle: "@sam_sweats", initials: "S")
        let ivy = Person(id: "ivy", name: "@ivy_climbs", handle: "@ivy_climbs", initials: "I")
        let theo = Person(id: "theo", name: "@theo_rows", handle: "@theo_rows", initials: "T")
        let nina = Person(id: "nina", name: "@nina_lifts", handle: "@nina_lifts", initials: "N")
        let you = Person(id: "you", name: "@maya_moves", handle: "@maya_moves", initials: "MM", isYou: true)
        let syncedJustNow = Date().addingTimeInterval(-4 * 60)
        let syncedToday = Date().addingTimeInterval(-2 * 3_600)
        let syncedYesterday = Date().addingTimeInterval(-22 * 3_600)

        let fights = [
            Fight(
                id: "sweat",
                code: "FIGHT-742",
                name: isFrench ? "Défi transpiration 7 jours" : "7-Day Sweat Ladder",
                metric: .steps,
                lengthDays: 7,
                daysLeft: 4,
                actionText: isFrench ? "Le perdant organise la prochaine balade" : "Loser plans the next walk",
                status: .live,
                rank: 2,
                of: 3,
                pending: 0,
                kickerEmphasis: "12.0k",
                kickerRest: String(localized: "behind @leo_runs"),
                listSubtitle: String(localized: "12.0k behind @leo_runs"),
                standings: [
                    Standing(person: leo, score: 54_000, lastSyncedAt: syncedJustNow),
                    Standing(person: you, score: 42_000, lastSyncedAt: syncedToday),
                    Standing(person: sam, score: 37_000, lastSyncedAt: syncedYesterday)
                ],
                days: [
                    FightDay(label: String(localized: "Day 1"), scores: [
                        DayScore(person: leo, value: 20_000),
                        DayScore(person: you, value: 12_000),
                        DayScore(person: sam, value: 15_000)
                    ]),
                    FightDay(label: String(localized: "Day 2"), scores: [
                        DayScore(person: leo, value: 18_000),
                        DayScore(person: you, value: 16_000),
                        DayScore(person: sam, value: 10_000)
                    ]),
                    FightDay(label: String(localized: "Day 3"), scores: [
                        DayScore(person: leo, value: 16_000),
                        DayScore(person: you, value: 14_000),
                        DayScore(person: sam, value: 12_000)
                    ])
                ],
                windowEnd: Date().addingTimeInterval(4 * 24 * 60 * 60)
            ),
            Fight(
                id: "derby",
                code: "FIGHT-118",
                name: isFrench ? "Derby des pas" : "Step Derby",
                metric: .steps,
                lengthDays: 7,
                daysLeft: 2,
                actionText: isFrench ? "Les perdants préparent le dîner dimanche" : "Losers cook Sunday dinner",
                status: .live,
                rank: 1,
                of: 5,
                pending: 1,
                kickerPrefix: String(localized: "Holding"),
                kickerEmphasis: String(localized: "1st"),
                kickerRest: String(localized: "with 2d to go"),
                listSubtitle: String(localized: "Holding 1st with 2d to go"),
                standings: [
                    Standing(person: you, score: 61400, lastSyncedAt: syncedJustNow),
                    Standing(person: ivy, score: 59800, lastSyncedAt: syncedToday),
                    Standing(person: theo, score: 55200, lastSyncedAt: syncedYesterday),
                    Standing(person: leo, score: 40100, lastSyncedAt: syncedYesterday),
                    Standing(person: nina, score: 22000, invited: true)
                ],
                windowEnd: Date().addingTimeInterval(1 * 24 * 60 * 60 + 8 * 60 * 60)
            ),
            Fight(
                id: "club",
                code: "FIGHT-655",
                name: isFrench ? "Club des 10 000" : "10K Club",
                metric: .steps,
                lengthDays: 7,
                daysLeft: 3,
                actionText: isFrench ? "Les perdants organisent la prochaine randonnée" : "Losers organize the next hike",
                status: .live,
                rank: 2,
                of: 4,
                pending: 2,
                kickerEmphasis: String(localized: "3.2k steps"),
                kickerRest: String(localized: "behind @sam_sweats"),
                listSubtitle: String(localized: "3.2k steps behind @sam_sweats"),
                standings: [
                    Standing(person: sam, score: 44800, lastSyncedAt: syncedToday),
                    Standing(person: you, score: 41600, lastSyncedAt: syncedJustNow),
                    Standing(person: nina, score: 31900, lastSyncedAt: syncedYesterday),
                    Standing(person: ivy, score: 28100, lastSyncedAt: syncedYesterday)
                ],
                windowEnd: Date().addingTimeInterval(3 * 24 * 60 * 60)
            ),
            Fight(
                id: "desk",
                code: "FIGHT-556",
                name: isFrench ? "Revanche du bureau" : "Desk Job Revenge",
                metric: .steps,
                lengthDays: 3,
                daysLeft: 3,
                actionText: isFrench ? "Les perdants prennent les escaliers toute la journée" : "Losers take the stairs all day",
                status: .invited,
                rank: 0,
                of: 4,
                pending: 2,
                kickerEmphasis: String(localized: "@theo_rows challenged you"),
                listSubtitle: String(localized: "@theo_rows · 3 days"),
                inviter: theo,
                invitePitch: String(localized: "@theo_rows challenged you"),
                inviteAction: String(localized: "Accept"),
                standingsMeta: String(localized: "2 in · 2 not replied"),
                standings: [
                    Standing(person: theo, score: 0),
                    Standing(person: nina, score: 0),
                    Standing(person: ivy, score: 0, invited: true)
                ]
            ),
            Fight(
                id: "sprint",
                code: "FIGHT-221",
                name: isFrench ? "Sprint en ville" : "City Sprint",
                metric: .steps,
                lengthDays: 7,
                daysLeft: 7,
                actionText: isFrench ? "Les perdants organisent une balade au parc" : "Losers plan a park walk",
                status: .invited,
                rank: 0,
                of: 3,
                pending: 0,
                kickerEmphasis: String(localized: "@ivy_climbs challenged you"),
                listSubtitle: String(localized: "@ivy_climbs · 7 days"),
                inviter: ivy,
                invitePitch: String(localized: "@ivy_climbs challenged you"),
                inviteAction: String(localized: "Join"),
                standings: [
                    Standing(person: ivy, score: 0)
                ]
            ),
            Fight(
                id: "weekend",
                code: "FIGHT-088",
                name: isFrench ? "Duel de pas du week-end" : "Weekend Step Duel",
                metric: .steps,
                lengthDays: 2,
                endedLabel: String(localized: "Ended Jul 13"),
                actionText: isFrench ? "Le perdant choisit le prochain parcours" : "Loser plans the next route",
                status: .finished,
                rank: 1,
                of: 2,
                pending: 0,
                kickerPrefix: String(localized: "Leading by"),
                kickerEmphasis: String(localized: "2.2k steps"),
                listSubtitle: String(localized: "Ended Jul 13 · 1st of 2"),
                standingsMeta: String(localized: "2 in"),
                standings: [
                    Standing(person: you, score: 24100, lastSyncedAt: syncedYesterday),
                    Standing(person: leo, score: 21900, lastSyncedAt: syncedYesterday)
                ]
            )
        ]

        return Bundle(
            you: you,
            fights: fights
        )
    }
}
