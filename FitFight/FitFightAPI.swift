import Foundation

enum FitFightAPIError: LocalizedError {
    case notConfigured
    case http(status: Int, code: String?, message: String?)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return String(localized: "FitFight API is not configured. Set FFAPIBaseURL.")
        case .http(let status, let code, let message):
            switch code {
            case "handle_not_found":
                return String(localized: "That username does not have a FitFight account yet.")
            case "already_member":
                return String(localized: "That person is already in this fight.")
            case "fight_not_joinable":
                return String(localized: "This fight is invite-only.")
            case "fight_full":
                return String(localized: "This fight is full.")
            case "join_rate_limited":
                return String(localized: "Too many join attempts. Try again later.")
            case "unauthorized":
                return String(localized: "Your session expired. Sign in again.")
            case "fight_not_startable", "fight_not_cancellable", "conflict":
                return String(localized: "This fight changed. Refresh and try again.")
            case "validation":
                return message ?? String(localized: "Check the title and details, then try again.")
            case "rate_limited":
                return message ?? String(localized: "You’ve posted a few times recently. Try again later.")
            case "not_found":
                return message ?? String(localized: "That isn’t available anymore.")
            default:
                return String(
                    localized: "api.request-failed",
                    defaultValue: "Request failed (\(status))."
                )
            }
        case .decoding:
            return String(localized: "Couldn’t read the server response.")
        }
    }
}

struct FitFightDataSource: Codable, Equatable {
    var id: UUID
    var provider: String
    var sourceLabel: String
    var contributingSourceLabels: [String]?
}

struct FitFightHealthKitContext: Decodable, Equatable {
    struct FightWindow: Decodable, Equatable {
        var fightId: UUID
        var state: String
        var startsAt: Date
        var endsAt: Date
        var cutoffAt: Date

        enum CodingKeys: String, CodingKey {
            case fightId = "fight_id"
            case state
            case startsAt = "starts_at"
            case endsAt = "ends_at"
            case cutoffAt = "cutoff_at"
        }
    }

    var serverNow: Date
    var fightWindows: [FightWindow]

    enum CodingKeys: String, CodingKey {
        case serverNow = "server_now"
        case fightWindows = "fight_windows"
    }
}

struct FitFightHealthKitStepSync: Encodable, Equatable {
    struct MergedDay: Encodable, Equatable {
        var day: String
        var startsAt: String
        var endsAt: String
        var steps: Int

        enum CodingKeys: String, CodingKey {
            case day
            case startsAt = "starts_at"
            case endsAt = "ends_at"
            case steps
        }
    }

    struct FightAggregate: Encodable, Equatable {
        var fightId: String
        var startsAt: String
        var endsAt: String
        var cutoffAt: String
        var steps: Int

        enum CodingKeys: String, CodingKey {
            case fightId = "fight_id"
            case startsAt = "starts_at"
            case endsAt = "ends_at"
            case cutoffAt = "cutoff_at"
            case steps
        }
    }

    var completeThrough: String
    var timeZone: String
    var mergedDays: [MergedDay]
    var fightAggregates: [FightAggregate]

    enum CodingKeys: String, CodingKey {
        case completeThrough = "complete_through"
        case timeZone = "time_zone"
        case mergedDays = "merged_days"
        case fightAggregates = "fight_aggregates"
    }
}

struct FitFightHealthKitStepSyncResult: Decodable, Equatable {
    var completeThrough: Date
    var syncedDays: Int
    var syncedFights: Int

    enum CodingKeys: String, CodingKey {
        case completeThrough = "complete_through"
        case syncedDays = "synced_days"
        case syncedFights = "synced_fights"
    }
}

struct FitFightHealthKitDiagnosticSnapshot: Encodable {
    var backgroundRefreshStatus: String
    var deliveryRegistrationStatus: String
    var lastObserverWake: Date?
    var lastSyncAttempt: Date?
    var lastAutomaticSync: Date?
    var lastManualSync: Date?
    var lastTriggerContext: String?
    var errorCode: String?
    var appVersion: String
    var appBuild: String
    var attempts: [HealthKitSyncTrace.Attempt]

    init(_ diagnostics: HealthKitStepsStore.Diagnostics, attempts: [HealthKitSyncTrace.Attempt]) {
        backgroundRefreshStatus = diagnostics.backgroundRefreshStatus.rawValue
        deliveryRegistrationStatus = diagnostics.deliveryRegistrationStatus.rawValue
        lastObserverWake = diagnostics.lastObserverWake
        lastSyncAttempt = diagnostics.lastSyncAttempt
        lastAutomaticSync = diagnostics.lastAutomaticSync
        lastManualSync = diagnostics.lastManualSync
        lastTriggerContext = diagnostics.lastTrigger?.rawValue
        errorCode = diagnostics.errorCode?.rawValue
        appVersion = AppVersion.marketing
        appBuild = AppVersion.build
        self.attempts = attempts
    }

    enum CodingKeys: String, CodingKey {
        case backgroundRefreshStatus = "background_refresh_status"
        case deliveryRegistrationStatus = "delivery_registration_status"
        case lastObserverWake = "last_observer_wake"
        case lastSyncAttempt = "last_sync_attempt"
        case lastAutomaticSync = "last_automatic_sync"
        case lastManualSync = "last_manual_sync"
        case lastTriggerContext = "last_trigger_context"
        case errorCode = "error_code"
        case appVersion = "app_version"
        case appBuild = "app_build"
        case attempts
    }
}

struct FitFightHealthKitDiagnosticSnapshotResult: Decodable {
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
    }
}

struct FitFightCreateFight: Encodable, Equatable {
    var name: String
    var startsAt: Date
    var endsAt: Date
    var timeZone: String
    var outcomeRule: String
    var goalPolicy: String?
    var defaultGoalValue: Double?
    var stakeKind: String
    var stakeMinor: Int?
    var currency: String?
    var actionText: String?
    var inviteHandles: [String]?
    var start: String?
    var visibility: String?
    var recurring: Bool?
}

struct FitFightJoinableFight: Decodable, Equatable, Identifiable {
    var fightId: UUID
    var seriesId: UUID
    var name: String
    var joinCode: String
    var ownerHandle: String
    var actionText: String?
    var startsAt: String
    var endsAt: String
    var memberCount: Int
    var recurring: Bool
    var alreadyMember: Bool

    var id: UUID { fightId }
}

private struct FitFightJoinableList: Decodable {
    var fights: [FitFightJoinableFight]
}

struct FitFightSummary: Codable, Equatable {
    var id: UUID
    var state: String
}

struct FitFightInviteCreated: Codable, Equatable {
    var token: String
    var invitedUserId: UUID
}

struct FitFightSnapshot: Decodable {
    let fights: [FightRow]
    let members: [MemberRow]
    let profiles: [FitFightProfile]
    let series: [SeriesRow]
    let stepDays: [StepDayRow]

    enum CodingKeys: String, CodingKey {
        case fights, members, profiles, series
        case stepDays = "step_days"
    }
}

struct FitFightAccountDeletion: Decodable, Equatable {
    var appleAuthorizationRevoked: Bool
    var deleted: Bool

    enum CodingKeys: String, CodingKey {
        case appleAuthorizationRevoked = "apple_authorization_revoked"
        case deleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appleAuthorizationRevoked = try container.decodeIfPresent(
            Bool.self,
            forKey: .appleAuthorizationRevoked
        ) ?? false
        deleted = try container.decode(Bool.self, forKey: .deleted)
    }
}

struct FitFightFeedbackPost: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var kind: String
    var title: String
    var body: String
    var voteCount: Int
    var commentCount: Int
    var voted: Bool
    var authorHandle: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case body
        case voteCount = "vote_count"
        case commentCount = "comment_count"
        case voted
        case authorHandle = "author_handle"
        case createdAt = "created_at"
    }
}

struct FitFightFeedbackComment: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var body: String
    var authorHandle: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case body
        case authorHandle = "author_handle"
        case createdAt = "created_at"
    }
}

struct FitFightFeedbackList: Decodable, Equatable {
    var posts: [FitFightFeedbackPost]
}

struct FitFightFeedbackDetail: Decodable, Equatable {
    var post: FitFightFeedbackPost
    var comments: [FitFightFeedbackComment]
}

struct FitFightFeedbackPostResponse: Decodable, Equatable {
    var post: FitFightFeedbackPost
}

struct FitFightFeedbackCommentResponse: Decodable, Equatable {
    var comment: FitFightFeedbackComment
}

struct FitFightFeedbackVote: Decodable, Equatable {
    var voted: Bool
    var voteCount: Int

    enum CodingKeys: String, CodingKey {
        case voted
        case voteCount = "vote_count"
    }
}

struct FitFightCreateFeedback: Encodable, Equatable {
    var kind: String
    var title: String
    var body: String
}

struct FitFightAPI {
    var baseURL: URL?

    var isConfigured: Bool { baseURL != nil }

    init(baseURL: URL? = FitFightAPI.resolvedBaseURL) {
        self.baseURL = baseURL
    }

    static var resolvedBaseURL: URL? {
        if let url = APIConfig.baseURL { return url }
        let raw = ProcessInfo.processInfo.environment["FFAPIBaseURL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    func connectAppleHealth(accessToken: String) async throws -> FitFightDataSource {
        try await post(
            path: "provider-connections/apple-health",
            accessToken: accessToken,
            body: EmptyJSON(),
            expected: [200]
        )
    }

    func healthKitUploadContext(
        accessToken: String,
        trace: HealthKitSyncTrace
    ) async throws -> FitFightHealthKitContext {
        try await get(
            path: "provider-uploads/context?provider=apple_health&metric=steps",
            accessToken: accessToken,
            expected: [200],
            trace: trace,
            traceStage: .context
        )
    }

    func syncHealthKitSteps(
        _ sync: FitFightHealthKitStepSync,
        accessToken: String,
        trace: HealthKitSyncTrace
    ) async throws -> FitFightHealthKitStepSyncResult {
        let body = try Self.encoder.encode(sync)
        trace.recordUpload(fights: sync.fightAggregates.count, days: sync.mergedDays.count, bytes: body.count)
        return try await request(
            path: "healthkit/steps",
            method: "POST",
            accessToken: accessToken,
            body: body,
            idempotencyKey: nil,
            expected: [200],
            trace: trace,
            traceStage: .upload
        )
    }

    func saveHealthKitDiagnostics(
        _ diagnostics: FitFightHealthKitDiagnosticSnapshot,
        accessToken: String
    ) async throws -> FitFightHealthKitDiagnosticSnapshotResult {
        try await post(
            path: "healthkit/diagnostics",
            accessToken: accessToken,
            body: diagnostics,
            expected: [200]
        )
    }

    func fightsSnapshot(accessToken: String, trace: HealthKitSyncTrace) async throws -> FitFightSnapshot {
        try await request(
            path: "fights/refresh",
            method: "POST",
            accessToken: accessToken,
            body: Self.encoder.encode(["time_zone": Calendar.current.timeZone.identifier]),
            idempotencyKey: nil,
            expected: [200],
            trace: trace,
            traceStage: .fightsRefresh
        )
    }

    func storeAppleAuthorizationCode(
        _ authorizationCode: String,
        accessToken: String
    ) async throws {
        let _: DiscardBody = try await post(
            path: "auth/apple",
            accessToken: accessToken,
            body: AppleAuthorizationBody(authorizationCode: authorizationCode),
            expected: [200]
        )
    }

    func deleteAccount(accessToken: String) async throws -> FitFightAccountDeletion {
        try await delete(
            path: "me",
            accessToken: accessToken,
            expected: [200]
        )
    }

    func createFight(
        _ payload: FitFightCreateFight,
        accessToken: String,
        idempotencyKey: String
    ) async throws -> FitFightSummary {
        try await post(
            path: "fights",
            accessToken: accessToken,
            body: payload,
            idempotencyKey: idempotencyKey,
            expected: [200, 201]
        )
    }

    func listJoinableFights(accessToken: String) async throws -> [FitFightJoinableFight] {
        let list: FitFightJoinableList = try await get(
            path: "fights/joinable",
            accessToken: accessToken,
            expected: [200]
        )
        return list.fights
    }

    func joinableFight(code: String, accessToken: String) async throws -> FitFightJoinableFight {
        try await get(
            path: "fights/joinable/\(code)",
            accessToken: accessToken,
            expected: [200]
        )
    }

    func joinFight(
        code: String? = nil,
        fightID: UUID? = nil,
        accessToken: String
    ) async throws -> FitFightSummary {
        try await post(
            path: "fights/join",
            accessToken: accessToken,
            body: JoinFightBody(code: code, fightId: fightID),
            expected: [200]
        )
    }

    func leaveFight(fightID: UUID, accessToken: String) async throws -> FitFightSummary {
        try await post(
            path: "fights/leave",
            accessToken: accessToken,
            body: LeaveFightBody(fightId: fightID),
            expected: [200]
        )
    }

    func invite(
        fightID: UUID,
        handle: String,
        accessToken: String
    ) async throws -> FitFightInviteCreated {
        try await post(
            path: "fights/\(fightID.uuidString.lowercased())/invites",
            accessToken: accessToken,
            body: HandleBody(handle: handle),
            expected: [200]
        )
    }

    func accept(
        token: String,
        accessToken: String,
        personalTarget: Double? = nil
    ) async throws -> FitFightSummary {
        try await post(
            path: "invites/\(token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? token)/accept",
            accessToken: accessToken,
            body: AcceptBody(personalTarget: personalTarget),
            expected: [200]
        )
    }

    func acceptFight(
        fightID: UUID,
        accessToken: String,
        personalTarget: Double? = nil
    ) async throws -> FitFightSummary {
        try await post(
            path: "fights/\(fightID.uuidString.lowercased())/accept",
            accessToken: accessToken,
            body: AcceptBody(personalTarget: personalTarget),
            expected: [200]
        )
    }

    func declineFight(fightID: UUID, accessToken: String) async throws -> FitFightSummary {
        try await post(
            path: "fights/\(fightID.uuidString.lowercased())/decline",
            accessToken: accessToken,
            body: EmptyJSON(),
            expected: [200]
        )
    }

    func start(
        fightID: UUID,
        accessToken: String,
        when: String = "now"
    ) async throws -> FitFightSummary {
        try await post(
            path: "fights/\(fightID.uuidString.lowercased())/start",
            accessToken: accessToken,
            body: StartBody(when: when),
            expected: [200]
        )
    }

    func cancel(fightID: UUID, accessToken: String) async throws {
        let _: DiscardBody = try await post(
            path: "fights/\(fightID.uuidString.lowercased())/cancel",
            accessToken: accessToken,
            body: EmptyJSON(),
            expected: [200]
        )
    }

    func listFeedback(kind: String?, accessToken: String) async throws -> FitFightFeedbackList {
        var path = "feedback"
        if let kind {
            path += "?kind=\(kind)"
        }
        return try await get(path: path, accessToken: accessToken, expected: [200])
    }

    func feedbackDetail(postID: UUID, accessToken: String) async throws -> FitFightFeedbackDetail {
        try await get(
            path: "feedback/\(postID.uuidString.lowercased())",
            accessToken: accessToken,
            expected: [200]
        )
    }

    func createFeedback(
        _ payload: FitFightCreateFeedback,
        accessToken: String
    ) async throws -> FitFightFeedbackPostResponse {
        try await post(
            path: "feedback",
            accessToken: accessToken,
            body: payload,
            expected: [201]
        )
    }

    func toggleFeedbackVote(
        postID: UUID,
        accessToken: String
    ) async throws -> FitFightFeedbackVote {
        try await post(
            path: "feedback/\(postID.uuidString.lowercased())/vote",
            accessToken: accessToken,
            body: EmptyJSON(),
            expected: [200]
        )
    }

    func createFeedbackComment(
        postID: UUID,
        body: String,
        accessToken: String
    ) async throws -> FitFightFeedbackCommentResponse {
        try await post(
            path: "feedback/\(postID.uuidString.lowercased())/comments",
            accessToken: accessToken,
            body: FeedbackCommentBody(body: body),
            expected: [201]
        )
    }

    private func post<Body: Encodable, Response: Decodable>(
        path: String,
        accessToken: String,
        body: Body,
        idempotencyKey: String? = nil,
        expected: Set<Int>
    ) async throws -> Response {
        try await request(
            path: path,
            method: "POST",
            accessToken: accessToken,
            body: Self.encoder.encode(body),
            idempotencyKey: idempotencyKey,
            expected: expected
        )
    }

    private func delete<Response: Decodable>(
        path: String,
        accessToken: String,
        expected: Set<Int>
    ) async throws -> Response {
        try await request(
            path: path,
            method: "DELETE",
            accessToken: accessToken,
            body: nil,
            idempotencyKey: nil,
            expected: expected
        )
    }

    private func get<Response: Decodable>(
        path: String,
        accessToken: String,
        expected: Set<Int>,
        trace: HealthKitSyncTrace? = nil,
        traceStage: HealthKitSyncTrace.StageName? = nil
    ) async throws -> Response {
        try await request(
            path: path,
            method: "GET",
            accessToken: accessToken,
            body: nil,
            idempotencyKey: nil,
            expected: expected,
            trace: trace,
            traceStage: traceStage
        )
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        accessToken: String,
        body: Data?,
        idempotencyKey: String?,
        expected: Set<Int>,
        trace: HealthKitSyncTrace? = nil,
        traceStage: HealthKitSyncTrace.StageName? = nil
    ) async throws -> Response {
        let span = traceStage.flatMap { trace?.begin($0) }
        var succeeded = false
        var serverTiming: [String: Double]?
        defer {
            trace?.end(span, outcome: Task.isCancelled ? .cancelled : (succeeded ? .succeeded : .failed), serverTiming: serverTiming)
        }
        try Task.checkCancellation()
        guard let requestURL = endpoint(path) else {
            throw FitFightAPIError.notConfigured
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let trace {
            request.setValue(trace.id.uuidString.lowercased(), forHTTPHeaderField: "X-FitFight-Trace-ID")
        }
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        if trace != nil, let header = http?.value(forHTTPHeaderField: "Server-Timing") {
            var timing: [String: Double] = [:]
            for entry in header.split(separator: ",") {
                let parts = entry.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
                guard let name = parts.first, ["auth", "db", "maintenance", "total"].contains(name),
                      let duration = parts.dropFirst().first(where: { $0.hasPrefix("dur=") }),
                      let value = Double(duration.dropFirst(4)), value.isFinite,
                      value >= 0, value <= 604_800_000 else { continue }
                timing[name + "_ms"] = value
            }
            if !timing.isEmpty { serverTiming = timing }
        }
        let status = http?.statusCode ?? -1
        guard expected.contains(status) else {
            let payload = try? Self.decoder.decode(APIErrorResponse.self, from: data)
            throw FitFightAPIError.http(
                status: status,
                code: payload?.code,
                message: payload?.error
            )
        }
        if Response.self == DiscardBody.self {
            succeeded = true
            return DiscardBody() as! Response
        }
        if data.isEmpty, let empty = EmptyJSON() as? Response {
            succeeded = true
            return empty
        }
        do {
            let decoded = try Self.decoder.decode(Response.self, from: data)
            succeeded = true
            return decoded
        } catch {
            throw FitFightAPIError.decoding(error)
        }
    }

    private func endpoint(_ path: String) -> URL? {
        guard let baseURL else { return nil }
        var root = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !root.lowercased().contains("/api/v1") {
            root += "/api/v1"
        }
        return URL(string: root + "/" + path)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private struct EmptyJSON: Codable {}

private struct APIErrorResponse: Decodable {
    var code: String
    var error: String?
}

private struct JoinFightBody: Encodable {
    var code: String?
    var fightId: UUID?
}

private struct LeaveFightBody: Encodable {
    var fightId: UUID
}

private struct HandleBody: Encodable {
    var handle: String
}

private struct AcceptBody: Encodable {
    var personalTarget: Double?
}

private struct StartBody: Encodable {
    var when: String
}

private struct AppleAuthorizationBody: Encodable {
    var authorizationCode: String

    enum CodingKeys: String, CodingKey {
        case authorizationCode = "authorization_code"
    }
}

private struct FeedbackCommentBody: Encodable {
    var body: String
}

private struct DiscardBody: Decodable {
    init() {}
}
