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
    case finished
}

struct Person: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var handle: String
    var initials: String
    var isYou: Bool = false

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
            dimmed: pending
        )
    }
}

struct Standing: Codable, Identifiable, Hashable {
    var person: Person
    var score: Double
    var invited: Bool = false
    var lastSyncedAt: Date? = nil
    var finalStepsComplete: Bool? = nil

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
    var serverState: String? = nil
    var joinCode: String? = nil
    var recurring: Bool = false
    var pendingJoin: Bool = false

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

    var shareURL: URL? {
        guard let joinCode, !joinCode.isEmpty else { return nil }
        return APIConfig.joinShareURL(code: joinCode)
    }

    var durationLabel: String {
        let hours = max(1, Int((windowEnd.timeIntervalSince(windowStart) / 3_600).rounded()))
        return localizedDuration(hours: hours, days: lengthDays)
    }

    /// Short test fights count in hours; a day count would round them away.
    var timeLeftLabel: String {
        let durationHours = windowEnd.timeIntervalSince(windowStart) / 3_600
        if durationHours <= 6, daysLeft != nil {
            let hours = max(1, Int(ceil(windowEnd.timeIntervalSinceNow / 3_600)))
            return String(
                localized: "fight.hours-left",
                defaultValue: "\(hours) hours left"
            )
        }
        if let daysLeft {
            return String(
                localized: "fight.days-left",
                defaultValue: "\(daysLeft) days left"
            )
        }
        return endedLabel ?? String(localized: "Ended")
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
    @Published private(set) var isCreatingFight = false
    @Published private(set) var isRefreshingFights = false

    @Published var you: Person
    @Published var fights: [Fight]

    private var session: SessionStore?
    private let api = FitFightAPI()
    private var inviteTokens: [String: String] = [:]
    private var cachedUserID: UUID?
    private var activeRefresh: (id: UUID, userID: UUID?)?
    private static let pendingJoinCodeKey = "fitfight.pendingJoinCode"

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
        fights.first { $0.id == id } ?? pendingJoinable.flatMap { $0.id == id ? $0 : nil }
    }

    var live: [Fight] { fights.filter { $0.status == .live } }
    var invitations: [Fight] { fights.filter { $0.status == .invited } }
    var finished: [Fight] { fights.filter { $0.status == .finished } }

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
        let userID = session.authSession?.user.id ?? session.client.auth.currentUser?.id
        if let activeRefresh, activeRefresh.userID == userID { return }
        let trace = HealthKitSyncTrace(trigger: trigger)
        activeRefresh = (trace.id, userID)
        isRefreshingFights = true
        defer {
            if activeRefresh?.id == trace.id {
                activeRefresh = nil
                isRefreshingFights = false
            }
        }

        await steps.refresh(requestAccess: requestAccess, trace: trace)
        guard (session.authSession?.user.id ?? session.client.auth.currentUser?.id) == userID else {
            trace.fail(.attemptExpired)
            steps.completeAttempt(trace, session: session, userID: userID)
            return
        }
        if session.authSession != nil, !Task.isCancelled {
            await steps.syncToBackend(session: session, trigger: trigger, trace: trace)
        }
        guard (session.authSession?.user.id ?? session.client.auth.currentUser?.id) == userID else {
            trace.fail(.attemptExpired)
            steps.completeAttempt(trace, session: session, userID: userID)
            return
        }
        if !Task.isCancelled { await refreshFromServer(session: session, trace: trace) }
        steps.completeAttempt(trace, session: session, userID: userID)
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
        recurring: Bool = false
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
        if visibility != "joinable", handles.isEmpty {
            createError = String(localized: "Add at least one other username.")
            return
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

    func acceptInvite(token: String) async throws {
        createError = nil
        guard let access = session?.authSession?.accessToken else {
            throw FitFightAPIError.notConfigured
        }
        let summary = try await api.accept(token: token, accessToken: access)
        inviteTokens[summary.id.uuidString] = token
        await refreshFromServer()
    }

    func acceptFight(id: String) async {
        createError = nil
        if let pending = pendingJoinable, pending.id == id, pending.pendingJoin {
            await joinPendingFight(pending)
            return
        }
        if let token = inviteTokens[id], api.isConfigured {
            do {
                try await acceptInvite(token: token)
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
            _ = try await api.acceptFight(fightID: fightID, accessToken: token)
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
        tab = .fights
        openFightID = summary.fightId.uuidString
    }

    func openJoinCode(_ raw: String, session: SessionStore) async {
        self.session = session
        createError = nil
        let code = raw.replacingOccurrences(of: "[\\s-]", with: "", options: .regularExpression).uppercased()
        guard code.count == 4 else {
            createError = String(localized: "Enter the 4-character code.")
            return
        }
        if let stored = UserDefaults.standard.string(forKey: Self.pendingJoinCodeKey), stored == code {
            UserDefaults.standard.removeObject(forKey: Self.pendingJoinCodeKey)
        }
        guard let access = session.authSession?.accessToken, api.isConfigured else {
            UserDefaults.standard.set(code, forKey: Self.pendingJoinCodeKey)
            createError = String(localized: "Sign in to join this fight.")
            return
        }
        do {
            let summary = try await api.joinableFight(code: code, accessToken: access)
            await openJoinable(summary, session: session)
        } catch {
            createError = (error as? FitFightAPIError)?.errorDescription
                ?? String(localized: "Couldn’t find that fight.")
        }
    }

    func handleOpenURL(_ url: URL, session: SessionStore) async {
        guard let code = Self.joinCode(from: url) else { return }
        await openJoinCode(code, session: session)
    }

    func consumePendingJoinCode(session: SessionStore) async {
        guard !session.needsOnboarding, session.profile != nil else { return }
        guard let code = UserDefaults.standard.string(forKey: Self.pendingJoinCodeKey) else { return }
        await openJoinCode(code, session: session)
    }

    private func joinPendingFight(_ fight: Fight) async {
        guard let access = session?.authSession?.accessToken, api.isConfigured else {
            createError = String(localized: "Sign in to join this fight.")
            return
        }
        guard let fightID = UUID(uuidString: fight.id) else {
            createError = String(localized: "Couldn’t join.")
            return
        }
        do {
            _ = try await api.joinFight(code: fight.joinCode, fightID: fightID, accessToken: access)
            pendingJoinable = nil
            joined.insert(fight.id)
            await refreshFromServer()
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
        guard let index = parts.firstIndex(of: "j"), parts.indices.contains(index + 1) else {
            return nil
        }
        let code = parts[index + 1]
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
            pendingJoin: true
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
            let scores = standings.map { row in
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
            isYou: isYou
        )
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
        } else if row.state == "final" || row.state == "cancelled" || ends < Date() {
            status = .finished
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
        let remainingLabel = localizedDuration(
            hours: max(1, Int(ceil(ends.timeIntervalSinceNow / 3_600))),
            days: daysLeft ?? 0
        )

        let people = members.map { member -> Standing in
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
                score: score,
                invited: member.state == "invited",
                lastSyncedAt: member.lastSyncedAt,
                finalStepsComplete: member.finalStepsComplete
            )
        }
        .sorted { lhs, rhs in
            if lhs.invited != rhs.invited { return !lhs.invited && rhs.invited }
            if lhs.score == rhs.score { return lhs.person.name < rhs.person.name }
            return lhs.score > rhs.score
        }

        let joined = people.filter { !$0.invited }
        let youRow = people.first { $0.person.isYou }
        let rank = youRow.flatMap { row in joined.firstIndex { $0.person.id == row.person.id }.map { $0 + 1 } }
            ?? mine?.rank
            ?? 0
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
            let formatter = DateFormatter()
            formatter.locale = .autoupdatingCurrent
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
            endedLabel = String(
                localized: "fight.ended-on",
                defaultValue: "Ended \(formatter.string(from: ends))"
            )
            listSubtitle = String(
                localized: "fight.finished-position",
                defaultValue: "\(endedLabel ?? String(localized: "Ended")) · \(Self.ordinal(rank)) of \(of)"
            )
            kickerPrefix = rank == 1 ? String(localized: "Won by") : String(localized: "Finished")
            kickerEmphasis = Self.ordinal(rank)
        case .live:
            if row.state == "awaiting_final_sync" {
                kickerEmphasis = String(localized: "Syncing final steps")
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
            standingsMeta: nil,
            standings: people,
            windowStart: starts,
            windowEnd: ends,
            serverState: row.state,
            joinCode: series?.joinCode,
            recurring: series?.recurring ?? false
        )
    }

    private static func ordinal(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: value)) ?? value.formatted()
    }
}

enum LiveFightError: LocalizedError {
    case notSignedIn
    case noOpponents
    case unknownHandle(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return String(localized: "Sign in to start a fight.")
        case .noOpponents:
            return String(localized: "Add at least one other username.")
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

struct SeriesRow: Decodable {
    let id: UUID
    let joinCode: String?
    let visibility: String
    let recurring: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case joinCode = "join_code"
        case visibility
        case recurring
    }
}

struct StepDayRow: Decodable {
    let userId: UUID
    let day: String
    let steps: Int

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case day
        case steps
    }
}

struct FightRow: Decodable {
    let id: UUID
    let ownerId: UUID
    let name: String
    let state: String
    let startsAt: String
    let endsAt: String
    let actionText: String?
    let seriesId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case name
        case state
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case actionText = "action_text"
        case seriesId = "series_id"
    }

    var startsAtDate: Date { Self.parse(startsAt) ?? Date() }
    var endsAtDate: Date { Self.parse(endsAt) ?? Date().addingTimeInterval(86400) }

    fileprivate static func parse(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }
}

struct MemberRow: Decodable {
    let fightId: UUID
    let userId: UUID
    let state: String
    let currentValue: Double?
    let rank: Int?
    let finalValue: Double?
    let lastSyncedAt: Date?
    let finalStepsComplete: Bool?

    enum CodingKeys: String, CodingKey {
        case fightId = "fight_id"
        case userId = "user_id"
        case state
        case currentValue = "current_value"
        case rank
        case finalValue = "final_value"
        case lastSyncedAt = "last_synced_at"
        case finalStepsComplete = "final_steps_complete"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fightId = try container.decode(UUID.self, forKey: .fightId)
        userId = try container.decode(UUID.self, forKey: .userId)
        state = try container.decode(String.self, forKey: .state)
        rank = try container.decodeIfPresent(Int.self, forKey: .rank)
        currentValue = Self.number(container, .currentValue)
        finalValue = Self.number(container, .finalValue)
        finalStepsComplete = try container.decodeIfPresent(Bool.self, forKey: .finalStepsComplete)
        if let date = try? container.decode(Date.self, forKey: .lastSyncedAt) {
            lastSyncedAt = date
        } else if let raw = try container.decodeIfPresent(String.self, forKey: .lastSyncedAt) {
            lastSyncedAt = FightRow.parse(raw)
        } else {
            lastSyncedAt = nil
        }
    }

    private static func number(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let value = try? container.decode(Double.self, forKey: key) { return value }
        if let value = try? container.decode(Int.self, forKey: key) { return Double(value) }
        if let value = try? container.decode(String.self, forKey: key) { return Double(value) }
        return nil
    }
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
                ]
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
                ]
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
                ]
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
