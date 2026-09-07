import Foundation
import HealthKit
import OSLog

/// One attempt owns its trace; the lock also covers HealthKit callbacks and cancellation.
final class HealthKitSyncTrace: @unchecked Sendable {
    enum StageName: String, Encodable {
        case authorization, session, context, upload
        case localState = "local_state"
        case todayTotal = "today_total"
        case healthKitDaily = "healthkit_daily"
        case healthKitFight = "healthkit_fight"
        case fightsRefresh = "fights_refresh"
    }

    enum Outcome: String, Encodable { case succeeded, failed, cancelled }

    struct Failure: Encodable {
        enum Kind: String, Encodable {
            case healthkit, network, storage, http, decoding, configuration, cancelled, unknown
            case noAccessibleSteps = "no_accessible_steps"
            case invalidStepCount = "invalid_step_count"
        }

        let kind: Kind
        let code: Int?

        init(_ error: Error) {
            let native = error as NSError
            var numericCode: Int?
            switch error {
            case is CancellationError: kind = .cancelled
            case FitFightAPIError.http(let status, _, _):
                kind = .http
                numericCode = status
            case FitFightAPIError.decoding(_), is DecodingError: kind = .decoding
            case FitFightAPIError.notConfigured: kind = .configuration
            case HealthKitStepAggregates.ReadError.noAccessibleSteps: kind = .noAccessibleSteps
            case HealthKitStepAggregates.ReadError.invalidStepCount: kind = .invalidStepCount
            default:
                // Error messages and userInfo can contain HealthKit predicates, URLs or credentials.
                switch native.domain {
                case HKErrorDomain: kind = .healthkit; numericCode = native.code
                case NSURLErrorDomain: kind = .network; numericCode = native.code
                case NSCocoaErrorDomain: kind = .storage; numericCode = native.code
                default: kind = .unknown
                }
            }
            code = numericCode.flatMap { Int32(exactly: $0).map(Int.init) }
        }

        var reference: String {
            kind.rawValue + (code.map { " (\($0))" } ?? "")
        }
    }

    struct Stage: Encodable {
        let stage: StageName
        let startedMs: Double
        var durationMs: Double
        var outcome: Outcome
        var serverTiming: [String: Double]?
        var error: Failure?

        enum CodingKeys: String, CodingKey {
            case stage, outcome, error
            case startedMs = "started_ms"
            case durationMs = "duration_ms"
            case serverTiming = "server_timing"
        }
    }

    struct Attempt: Encodable {
        let attemptId: UUID
        let trigger: HealthKitStepsStore.SyncTrigger
        let startedAt: Date
        let outcome: Outcome
        let errorCode: HealthKitStepsStore.SyncErrorCode?
        let totalMs: Double
        let stages: [Stage]
        let fightCount: Int?
        let dayCount: Int?
        let payloadBytes: Int?

        enum CodingKeys: String, CodingKey {
            case trigger, outcome, stages
            case attemptId = "attempt_id"
            case startedAt = "started_at"
            case errorCode = "error_code"
            case totalMs = "total_ms"
            case fightCount = "fight_count"
            case dayCount = "day_count"
            case payloadBytes = "payload_bytes"
        }
    }

    let id = UUID()
    let trigger: HealthKitStepsStore.SyncTrigger
    private let startedAt = Date()
    private let clock = ContinuousClock()
    private let origin = ContinuousClock().now
    private let lock = NSLock()
    private var stages: [Stage] = []
    private var pending: Set<Int> = []
    private var completed = false
    private var errorCode: HealthKitStepsStore.SyncErrorCode?
    private var fightCount: Int?
    private var dayCount: Int?
    private var payloadBytes: Int?
    private static let logger = Logger(subsystem: "com.fitfight.mvp", category: "HealthKitPerformance")

    init(trigger: HealthKitStepsStore.SyncTrigger) {
        self.trigger = trigger
    }

    private var elapsedMs: Double {
        let duration = origin.duration(to: clock.now).components
        return min(604_800_000, Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
    }

    func begin(_ stage: StageName) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard !completed, stages.count < 256 else { return nil }
        let index = stages.count
        stages.append(Stage(stage: stage, startedMs: elapsedMs, durationMs: 0, outcome: .succeeded))
        pending.insert(index)
        return index
    }

    func end(_ index: Int?, outcome: Outcome, serverTiming: [String: Double]? = nil, error: Error? = nil) {
        lock.lock()
        defer { lock.unlock() }
        guard let index, !completed, pending.remove(index) != nil else { return }
        stages[index].durationMs = elapsedMs - stages[index].startedMs
        stages[index].outcome = outcome
        stages[index].serverTiming = serverTiming
        stages[index].error = error.map(Failure.init)
    }

    func measure<T>(_ stage: StageName, operation: () async throws -> T) async rethrows -> T {
        let index = begin(stage)
        do {
            let result = try await operation()
            end(index, outcome: Task.isCancelled ? .cancelled : .succeeded)
            return result
        } catch {
            end(index, outcome: error is CancellationError || Task.isCancelled ? .cancelled : .failed, error: error)
            throw error
        }
    }

    func fail(_ code: HealthKitStepsStore.SyncErrorCode) {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return }
        errorCode = code
    }

    func recordUpload(fights: Int, days: Int, bytes: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return }
        fightCount = fights
        dayCount = days
        payloadBytes = bytes
    }

    func finish(cancelled: Bool = false) -> Attempt? {
        lock.lock()
        guard !completed else { lock.unlock(); return nil }
        completed = true
        let totalMs = elapsedMs
        for index in pending {
            stages[index].durationMs = totalMs - stages[index].startedMs
            stages[index].outcome = .cancelled
        }
        let outcome: Outcome = cancelled || errorCode == .attemptExpired || stages.contains(where: { $0.outcome == .cancelled })
            ? .cancelled
            : (errorCode != nil || stages.contains(where: { $0.outcome == .failed }) ? .failed : .succeeded)
        let attempt = Attempt(
            attemptId: id, trigger: trigger, startedAt: startedAt, outcome: outcome,
            errorCode: outcome == .cancelled ? .attemptExpired : errorCode,
            totalMs: totalMs, stages: stages, fightCount: fightCount,
            dayCount: dayCount, payloadBytes: payloadBytes
        )
        lock.unlock()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(attempt), let line = String(data: data, encoding: .utf8) {
            Self.logger.info("\(line, privacy: .public)")
        }
        return attempt
    }
}
