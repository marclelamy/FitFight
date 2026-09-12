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
            case "update_required":
                return String(localized: "Update FitFight to continue")
            case "release_unavailable":
                return String(localized: "Couldn’t check for updates")
            case "handle_not_found":
                return String(localized: "That username does not have a FitFight account yet.")
            case "already_member":
                return String(localized: "That person is already in this fight.")
            case "fight_not_joinable":
                return String(localized: "This fight cannot be joined.")
            case "fight_full":
                return String(localized: "This fight is full.")
            case "join_rate_limited":
                return String(localized: "Too many join attempts. Try again later.")
            case "unauthorized":
                return String(localized: "Your session expired. Sign in again.")
            case "forbidden":
                return message ?? String(localized: "This is only available to the FitFight admin.")
            case "config":
                return message ?? String(localized: "Cursor isn’t configured yet.")
            case "fight_not_startable", "fight_not_cancellable", "conflict":
                return String(localized: "This fight changed. Refresh and try again.")
            case "validation":
                return message ?? String(localized: "Check the title and details, then try again.")
            case "rate_limited":
                return message ?? String(localized: "You’ve posted a few times recently. Try again later.")
            case "not_found":
                return message ?? String(localized: "That isn’t available anymore.")
            case "internal":
                return message ?? String(
                    localized: "api.request-failed",
                    defaultValue: "Request failed (\(status))."
                )
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

    struct ActivityDay: Encodable, Equatable {
        var day: String
        var startsAt: String
        var endsAt: String
        var metric: String
        var value: Double
        var unit: String

        enum CodingKeys: String, CodingKey {
            case day
            case startsAt = "starts_at"
            case endsAt = "ends_at"
            case metric
            case value
            case unit
        }
    }

    struct Workout: Encodable, Equatable {
        var healthkitUuid: String
        var startedAt: String
        var endedAt: String
        var activityType: String
        var durationSeconds: Double
        var distanceM: Double?
        var energyKcal: Double?
        var effort: Double?

        enum CodingKeys: String, CodingKey {
            case healthkitUuid = "healthkit_uuid"
            case startedAt = "started_at"
            case endedAt = "ended_at"
            case activityType = "activity_type"
            case durationSeconds = "duration_seconds"
            case distanceM = "distance_m"
            case energyKcal = "energy_kcal"
            case effort
        }
    }

    var completeThrough: String
    var timeZone: String
    var mergedDays: [MergedDay]
    var fightAggregates: [FightAggregate]
    var activityDays: [ActivityDay]? = nil
    var workouts: [Workout]? = nil

    enum CodingKeys: String, CodingKey {
        case completeThrough = "complete_through"
        case timeZone = "time_zone"
        case mergedDays = "merged_days"
        case fightAggregates = "fight_aggregates"
        case activityDays = "activity_days"
        case workouts
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
    var canJoinNext: Bool?

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
    var authorId: UUID
    var authorHandle: String
    var mine: Bool
    var createdAt: Date
    var metadata: FitFightFeedbackMetadata

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case body
        case voteCount = "vote_count"
        case commentCount = "comment_count"
        case voted
        case authorId = "author_id"
        case authorHandle = "author_handle"
        case mine
        case createdAt = "created_at"
        case metadata
    }

    init(
        id: UUID,
        kind: String,
        title: String,
        body: String,
        voteCount: Int,
        commentCount: Int,
        voted: Bool,
        authorId: UUID,
        authorHandle: String,
        mine: Bool,
        createdAt: Date,
        metadata: FitFightFeedbackMetadata = FitFightFeedbackMetadata()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.voteCount = voteCount
        self.commentCount = commentCount
        self.voted = voted
        self.authorId = authorId
        self.authorHandle = authorHandle
        self.mine = mine
        self.createdAt = createdAt
        self.metadata = metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(String.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        voteCount = try container.decode(Int.self, forKey: .voteCount)
        commentCount = try container.decode(Int.self, forKey: .commentCount)
        voted = try container.decode(Bool.self, forKey: .voted)
        authorId = try container.decode(UUID.self, forKey: .authorId)
        authorHandle = try container.decode(String.self, forKey: .authorHandle)
        mine = try container.decode(Bool.self, forKey: .mine)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        metadata = try container.decodeIfPresent(FitFightFeedbackMetadata.self, forKey: .metadata)
            ?? FitFightFeedbackMetadata()
    }
}

struct FitFightFeedbackComment: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var body: String
    var authorHandle: String
    var createdAt: Date
    var metadata: FitFightFeedbackMetadata

    enum CodingKeys: String, CodingKey {
        case id
        case body
        case authorHandle = "author_handle"
        case createdAt = "created_at"
        case metadata
    }

    init(
        id: UUID,
        body: String,
        authorHandle: String,
        createdAt: Date,
        metadata: FitFightFeedbackMetadata = FitFightFeedbackMetadata()
    ) {
        self.id = id
        self.body = body
        self.authorHandle = authorHandle
        self.createdAt = createdAt
        self.metadata = metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        body = try container.decode(String.self, forKey: .body)
        authorHandle = try container.decode(String.self, forKey: .authorHandle)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        metadata = try container.decodeIfPresent(FitFightFeedbackMetadata.self, forKey: .metadata)
            ?? FitFightFeedbackMetadata()
    }
}

struct FitFightFeedbackList: Decodable, Equatable {
    var posts: [FitFightFeedbackPost]
}

struct FitFightFeedbackDetail: Decodable, Equatable {
    var post: FitFightFeedbackPost
    var comments: [FitFightFeedbackComment]
    var canLaunchFix: Bool

    enum CodingKeys: String, CodingKey {
        case post
        case comments
        case canLaunchFix = "can_launch_fix"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        post = try container.decode(FitFightFeedbackPost.self, forKey: .post)
        comments = try container.decode([FitFightFeedbackComment].self, forKey: .comments)
        canLaunchFix = try container.decodeIfPresent(Bool.self, forKey: .canLaunchFix) ?? false
    }
}

struct FitFightFeedbackFixAgent: Decodable, Equatable {
    var agentId: String
    var agentURL: URL

    enum CodingKeys: String, CodingKey {
        case agentId = "agent_id"
        case agentURL = "agent_url"
    }
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
    var metadata: FitFightFeedbackMetadata
}

struct FitFightReferralLink: Encodable {
    let code: UUID
}

struct FitFightReferralClaim: Decodable {
    let recorded: Bool
}

struct FitFightDailyStatusRecap: Decodable {
    let recap: String
    let sentAt: Date

    enum CodingKeys: String, CodingKey {
        case recap
        case sentAt = "sent_at"
    }
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

    func claimReferral(code: UUID, accessToken: String) async throws -> FitFightReferralClaim {
        try await post(
            path: "referrals",
            accessToken: accessToken,
            body: FitFightReferralLink(code: code),
            expected: [200]
        )
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

    func dailyStatusRecap(fightID: UUID, accessToken: String) async throws -> FitFightDailyStatusRecap {
        try await get(
            path: "fights/\(fightID.uuidString.lowercased())/daily-status",
            accessToken: accessToken,
            expected: [200]
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

    func profile(accessToken: String) async throws -> FitFightProfile {
        try await get(path: "me", accessToken: accessToken, expected: [200])
    }

    func updateProfile(
        handle: String? = nil,
        displayName: String? = nil,
        avatarMediaId: UUID? = nil,
        accessToken: String
    ) async throws -> FitFightProfile {
        try await request(
            path: "me",
            method: "PATCH",
            accessToken: accessToken,
            body: Self.encoder.encode(ProfileUpdate(
                handle: handle,
                displayName: displayName,
                avatarMediaId: avatarMediaId
            )),
            idempotencyKey: nil,
            expected: [200]
        )
    }

    func createMediaUpload(
        purpose: String,
        kind: String = "photo",
        filename: String,
        contentType: String,
        byteSize: Int,
        width: Int,
        height: Int,
        durationMs: Int? = nil,
        sha256: String,
        accessToken: String
    ) async throws -> FitFightMediaUpload {
        try await post(
            path: "media",
            accessToken: accessToken,
            body: MediaUploadBody(
                purpose: purpose,
                kind: kind,
                originalFilename: filename,
                contentType: contentType,
                byteSize: byteSize,
                width: width,
                height: height,
                durationMs: durationMs,
                sha256: sha256
            ),
            expected: [201]
        )
    }

    func commitMedia(id: UUID, accessToken: String) async throws -> FitFightMediaResponse {
        try await post(
            path: "media/\(id.uuidString.lowercased())/commit",
            accessToken: accessToken,
            body: EmptyJSON(),
            expected: [200]
        )
    }

    func feed(scope: String? = nil, cursor: String?, accessToken: String) async throws -> FitFightFightPostList {
        var parts: [String] = []
        if let scope, let encoded = scope.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            parts.append("scope=\(encoded)")
        }
        if let cursor, let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            parts.append("cursor=\(encoded)")
        }
        let path = parts.isEmpty ? "feed" : "feed?\(parts.joined(separator: "&"))"
        return try await get(path: path, accessToken: accessToken, expected: [200])
    }

    func createFeedPosts(
        body: String,
        mediaIDs: [UUID],
        destinations: [FeedPostDestination],
        taggedUserIDs: [UUID],
        accessToken: String
    ) async throws -> FitFightFightPostBatch {
        try await post(
            path: "feed/posts",
            accessToken: accessToken,
            body: FeedPostsBody(
                body: body,
                mediaIds: mediaIDs,
                destinations: destinations,
                taggedUserIds: taggedUserIDs
            ),
            expected: [201]
        )
    }

    func feedPeople(main: Bool, fightIDs: [UUID], accessToken: String) async throws -> FitFightFeedPeople {
        var parts: [String] = []
        if main { parts.append("main=true") }
        if !fightIDs.isEmpty {
            let value = fightIDs.map { $0.uuidString.lowercased() }.joined(separator: ",")
            parts.append("fight_ids=\(value)")
        }
        let path = parts.isEmpty ? "feed/people" : "feed/people?\(parts.joined(separator: "&"))"
        return try await get(path: path, accessToken: accessToken, expected: [200])
    }

    func fightPostComments(postID: UUID, cursor: String?, accessToken: String) async throws -> FitFightFightPostCommentList {
        var path = "posts/\(postID.uuidString.lowercased())/comments"
        if let cursor, let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "?cursor=\(encoded)"
        }
        return try await get(path: path, accessToken: accessToken, expected: [200])
    }

    func createFightPostComment(
        postID: UUID,
        body: String,
        parentID: UUID?,
        accessToken: String
    ) async throws -> FitFightFightPostCommentResponse {
        try await post(
            path: "posts/\(postID.uuidString.lowercased())/comments",
            accessToken: accessToken,
            body: FightPostCommentBody(body: body, parentId: parentID),
            expected: [201]
        )
    }

    func deleteFightPostComment(postID: UUID, commentID: UUID, accessToken: String) async throws {
        let _: DiscardBody = try await delete(
            path: "posts/\(postID.uuidString.lowercased())/comments/\(commentID.uuidString.lowercased())",
            accessToken: accessToken,
            expected: [200]
        )
    }

    func reportFightPostComment(postID: UUID, commentID: UUID, accessToken: String) async throws {
        let _: DiscardBody = try await post(
            path: "posts/\(postID.uuidString.lowercased())/comments/\(commentID.uuidString.lowercased())/report",
            accessToken: accessToken,
            body: FightPostReportBody(reason: "other"),
            expected: [200]
        )
    }

    func reactToFightPost(postID: UUID, emoji: String, accessToken: String) async throws -> FitFightFightPostReactionList {
        try await post(
            path: "posts/\(postID.uuidString.lowercased())/reactions",
            accessToken: accessToken,
            body: FightPostReactionBody(emoji: emoji),
            expected: [200]
        )
    }

    func fightPosts(fightID: UUID, cursor: String?, accessToken: String) async throws -> FitFightFightPostList {
        var path = "fights/\(fightID.uuidString.lowercased())/posts"
        if let cursor, let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "?cursor=\(encoded)"
        }
        return try await get(path: path, accessToken: accessToken, expected: [200])
    }

    func createFightPost(
        fightID: UUID,
        body: String,
        mediaIDs: [UUID],
        accessToken: String
    ) async throws -> FitFightFightPostResponse {
        try await post(
            path: "fights/\(fightID.uuidString.lowercased())/posts",
            accessToken: accessToken,
            body: FightPostBody(body: body, mediaIds: mediaIDs),
            expected: [201]
        )
    }

    func deleteFightPost(fightID: UUID? = nil, postID: UUID, accessToken: String) async throws {
        let path = fightID == nil
            ? "posts/\(postID.uuidString.lowercased())"
            : "fights/\(fightID!.uuidString.lowercased())/posts/\(postID.uuidString.lowercased())"
        let _: DiscardBody = try await delete(
            path: path,
            accessToken: accessToken,
            expected: [200]
        )
    }

    func reportFightPost(fightID: UUID? = nil, postID: UUID, reason: String, accessToken: String) async throws {
        let path = fightID == nil
            ? "posts/\(postID.uuidString.lowercased())/report"
            : "fights/\(fightID!.uuidString.lowercased())/posts/\(postID.uuidString.lowercased())/report"
        let _: DiscardBody = try await post(
            path: path,
            accessToken: accessToken,
            body: FightPostReportBody(reason: reason),
            expected: [200]
        )
    }

    func blockFeedAuthor(userID: UUID, accessToken: String) async throws {
        let _: DiscardBody = try await post(
            path: "feed/blocks",
            accessToken: accessToken,
            body: FeedBlockBody(userId: userID),
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

    func notificationDeliveryStatus() async throws -> FitFightNotificationDeliveryStatus {
        try await get(path: "notifications/status", accessToken: "", expected: [200])
    }

    func registerDeviceInstallation(
        token: String,
        apnsEnvironment: String,
        locale: String,
        permissionStatus: String,
        accessToken: String
    ) async throws {
        let _: FitFightDeviceInstallationRegistered = try await post(
            path: "device-installations",
            accessToken: accessToken,
            body: FitFightDeviceInstallationBody(
                token: token,
                apnsEnvironment: apnsEnvironment,
                locale: locale,
                permissionStatus: permissionStatus
            ),
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
        accessToken: String,
        start: String = "now"
    ) async throws -> FitFightSummary {
        try await post(
            path: "fights/join",
            accessToken: accessToken,
            body: JoinFightBody(code: code, fightId: fightID, start: start),
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
        personalTarget: Double? = nil,
        start: String = "now"
    ) async throws -> FitFightSummary {
        try await post(
            path: "invites/\(token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? token)/accept",
            accessToken: accessToken,
            body: AcceptBody(personalTarget: personalTarget, start: start),
            expected: [200]
        )
    }

    func acceptFight(
        fightID: UUID,
        accessToken: String,
        personalTarget: Double? = nil,
        start: String = "now"
    ) async throws -> FitFightSummary {
        try await post(
            path: "fights/\(fightID.uuidString.lowercased())/accept",
            accessToken: accessToken,
            body: AcceptBody(personalTarget: personalTarget, start: start),
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
        metadata: FitFightFeedbackMetadata,
        accessToken: String
    ) async throws -> FitFightFeedbackCommentResponse {
        try await post(
            path: "feedback/\(postID.uuidString.lowercased())/comments",
            accessToken: accessToken,
            body: FeedbackCommentBody(body: body, metadata: metadata),
            expected: [201]
        )
    }

    func launchFeedbackFix(
        postID: UUID,
        accessToken: String
    ) async throws -> FitFightFeedbackFixAgent {
        try await post(
            path: "feedback/\(postID.uuidString.lowercased())/fix-agent",
            accessToken: accessToken,
            body: EmptyJSON(),
            expected: [201]
        )
    }

    func reportFeedbackPost(postID: UUID, reason: String, accessToken: String) async throws {
        let _: DiscardBody = try await post(
            path: "feedback/\(postID.uuidString.lowercased())/report",
            accessToken: accessToken,
            body: FightPostReportBody(reason: reason),
            expected: [200]
        )
    }

    func blockFeedbackAuthor(userID: UUID, accessToken: String) async throws {
        let _: DiscardBody = try await post(
            path: "feedback/blocks",
            accessToken: accessToken,
            body: FeedBlockBody(userId: userID),
            expected: [200]
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
        var failure: Error?
        var serverTiming: [String: Double]?
        defer {
            trace?.end(span, outcome: Task.isCancelled ? .cancelled : (succeeded ? .succeeded : .failed), serverTiming: serverTiming, error: failure)
        }
        do {
            try Task.checkCancellation()
            guard await AppUpdateChecker.shared.permitsRequests() else {
                let requiresUpdate = await AppUpdateChecker.shared.status == .updateRequired
                throw FitFightAPIError.http(
                    status: requiresUpdate ? 426 : 503,
                    code: requiresUpdate ? "update_required" : "release_unavailable",
                    message: nil
                )
            }
            guard let requestURL = endpoint(path) else {
                throw FitFightAPIError.notConfigured
            }

            var request = URLRequest(url: requestURL)
            request.httpMethod = method
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(AppVersion.marketing, forHTTPHeaderField: "X-FitFight-Version")
            request.setValue(AppVersion.build, forHTTPHeaderField: "X-FitFight-Build")
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
                if payload?.code == "update_required" || payload?.code == "release_unavailable" {
                    await AppUpdateChecker.shared.rejectRequest(updateRequired: payload?.code == "update_required")
                }
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
        } catch {
            failure = error
            throw error
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
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: raw) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date \(raw)"
            )
        }
        return decoder
    }()
}

private struct EmptyJSON: Codable {}

private struct ProfileUpdate: Encodable {
    let handle: String?
    let displayName: String?
    let avatarMediaId: UUID?

    enum CodingKeys: String, CodingKey {
        case handle
        case displayName = "display_name"
        case avatarMediaId = "avatar_media_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(handle, forKey: .handle)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(avatarMediaId, forKey: .avatarMediaId)
    }
}

private struct MediaUploadBody: Encodable {
    let purpose: String
    let kind: String
    let originalFilename: String
    let contentType: String
    let byteSize: Int
    let width: Int
    let height: Int
    let durationMs: Int?
    let sha256: String

    enum CodingKeys: String, CodingKey {
        case purpose, kind, width, height, sha256
        case originalFilename = "original_filename"
        case contentType = "content_type"
        case byteSize = "byte_size"
        case durationMs = "duration_ms"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(purpose, forKey: .purpose)
        try container.encode(kind, forKey: .kind)
        try container.encode(originalFilename, forKey: .originalFilename)
        try container.encode(contentType, forKey: .contentType)
        try container.encode(byteSize, forKey: .byteSize)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encodeIfPresent(durationMs, forKey: .durationMs)
        try container.encode(sha256, forKey: .sha256)
    }
}

struct FeedPostDestination: Encodable, Hashable {
    let type: String
    let fightId: UUID?

    static var main: FeedPostDestination { FeedPostDestination(type: "main", fightId: nil) }

    static func fight(_ id: UUID) -> FeedPostDestination {
        FeedPostDestination(type: "fight", fightId: id)
    }

    enum CodingKeys: String, CodingKey {
        case type
        case fightId = "fight_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(fightId, forKey: .fightId)
    }
}

private struct FightPostBody: Encodable {
    let body: String
    let mediaIds: [UUID]

    enum CodingKeys: String, CodingKey {
        case body
        case mediaIds = "media_ids"
    }
}

private struct FeedPostsBody: Encodable {
    let body: String
    let mediaIds: [UUID]
    let destinations: [FeedPostDestination]
    let taggedUserIds: [UUID]

    enum CodingKeys: String, CodingKey {
        case body
        case mediaIds = "media_ids"
        case destinations
        case taggedUserIds = "tagged_user_ids"
    }
}

private struct FightPostCommentBody: Encodable {
    let body: String
    let parentId: UUID?

    enum CodingKeys: String, CodingKey {
        case body
        case parentId = "parent_id"
    }
}

private struct FightPostReactionBody: Encodable {
    let emoji: String
}

private struct FightPostReportBody: Encodable {
    let reason: String
}

private struct FeedBlockBody: Encodable {
    let userId: UUID

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}

private struct APIErrorResponse: Decodable {
    var code: String
    var error: String?
}

private struct JoinFightBody: Encodable {
    var code: String?
    var fightId: UUID?
    var start: String?
}

private struct LeaveFightBody: Encodable {
    var fightId: UUID
}

private struct HandleBody: Encodable {
    var handle: String
}

private struct AcceptBody: Encodable {
    var personalTarget: Double?
    var start: String?
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
    var metadata: FitFightFeedbackMetadata
}

private struct DiscardBody: Decodable {
    init() {}
}

struct FitFightNotificationDeliveryStatus: Decodable {
    var apnsConfigured: Bool

    enum CodingKeys: String, CodingKey {
        case apnsConfigured = "apns_configured"
    }
}

private struct FitFightDeviceInstallationBody: Encodable {
    var token: String
    var apnsEnvironment: String
    var locale: String
    var permissionStatus: String

    enum CodingKeys: String, CodingKey {
        case token
        case apnsEnvironment = "apns_environment"
        case locale
        case permissionStatus = "permission_status"
    }
}

private struct FitFightDeviceInstallationRegistered: Decodable {
    var registered: Bool
}
