import Combine
import Foundation
import HealthKit
import UIKit

@MainActor
final class HealthKitStepsStore: ObservableObject {
    enum Status: Equatable { case idle, reading, steps(count: Int), empty }
    enum SyncTrigger: String, Codable { case observer, foreground, manual }
    enum BackgroundRefreshStatus: String, Codable { case available, denied, restricted }
    enum DeliveryRegistrationStatus: String, Codable { case enabled, unavailable }
    enum SyncErrorCode: String, Codable {
        case authenticationUnavailable = "authentication_unavailable"
        case networkUnavailable = "network_unavailable"
        case protectedDataUnavailable = "protected_data_unavailable"
        case attemptExpired = "attempt_expired"
        case healthKitUnavailable = "healthkit_unavailable"
        case backgroundDeliveryUnavailable = "background_delivery_unavailable"
        case syncFailed = "sync_failed"
    }

    struct Diagnostics: Codable, Equatable {
        var backgroundRefreshStatus: BackgroundRefreshStatus
        var deliveryRegistrationStatus: DeliveryRegistrationStatus
        var lastObserverWake: Date?
        var lastSyncAttempt: Date?
        var lastAutomaticSync: Date?
        var lastManualSync: Date?
        var lastTrigger: SyncTrigger?
        var errorCode: SyncErrorCode?

        @MainActor static var current: Diagnostics {
            Diagnostics(
                backgroundRefreshStatus: HealthKitStepsStore.backgroundRefreshStatus,
                deliveryRegistrationStatus: .unavailable,
                lastObserverWake: nil,
                lastSyncAttempt: nil,
                lastAutomaticSync: nil,
                lastManualSync: nil,
                lastTrigger: nil,
                errorCode: nil
            )
        }
    }

    static let shared = HealthKitStepsStore()

    @Published private(set) var status: Status = .idle
    @Published private(set) var connection = HealthKitConnectionState.notConnected
    @Published private(set) var diagnostics = Diagnostics.current

    private let store = HKHealthStore()
    private let api = FitFightAPI()
    private let uploader = HealthKitTUSUploader()
    private var isSyncing = false
    private var observerQuery: HKObserverQuery?
    private weak var session: SessionStore?
    private var activeUserId: UUID?
    private static let pendingLocalDeletionKey = "ff.healthkit.pendingLocalDeletion"
    private static let pendingSyncKey = "ff.healthkit.pendingSync"
    private static let diagnosticsPrefix = "ff.healthkit.diagnostics."

    var hasAsked: Bool {
        guard let activeUserId else { return false }
        return UserDefaults.standard.bool(forKey: Self.askedKey(userId: activeUserId))
    }

    var detailText: String {
        switch connection {
        case .notConnected: return String(localized: "Not connected")
        case .syncing: return String(localized: "Syncing Steps…")
        case .upToDate:
            return diagnostics.deliveryRegistrationStatus == .unavailable
                ? String(localized: "Up to date · Background sync unavailable")
                : String(localized: "Up to date")
        case .noAccessibleSteps: return String(localized: "No accessible Steps")
        case .syncFailed: return String(localized: "Sync failed — tap to retry")
        }
    }

    var metaText: String {
        switch status {
        case .steps(let count):
            // NOTE: The catalog string uses %lld and pluralizes on the integer.
            // `format: .number` passes a FormatStyle value, so %lld printed garbage.
            return String(
                localized: "health.steps-today",
                defaultValue: "\(count) steps today"
            )
        default:
            return ""
        }
    }

    var isConnected: Bool { connection != .notConnected }

    var backgroundRefreshText: String {
        switch diagnostics.backgroundRefreshStatus {
        case .available: return String(localized: "Available")
        case .denied: return String(localized: "Denied")
        case .restricted: return String(localized: "Restricted by this device")
        }
    }

    var backgroundDeliveryText: String {
        diagnostics.deliveryRegistrationStatus == .enabled
            ? String(localized: "Enabled")
            : String(localized: "Unavailable")
    }

    var currentFailureText: String? {
        switch diagnostics.errorCode {
        case .authenticationUnavailable: return String(localized: "Sign in, then open FitFight to sync.")
        case .networkUnavailable: return String(localized: "Connect to the internet, then open FitFight.")
        case .protectedDataUnavailable: return String(localized: "Unlock your iPhone, then open FitFight.")
        case .attemptExpired: return String(localized: "Open FitFight to finish syncing.")
        case .healthKitUnavailable: return String(localized: "Apple Health isn’t available on this device.")
        case .backgroundDeliveryUnavailable: return String(localized: "Open FitFight to sync your Steps.")
        case .syncFailed: return String(localized: "Open FitFight and try the Apple Health sync again.")
        case nil: return nil
        }
    }

    func installObserverAtLaunch() {
        guard HKHealthStore.isHealthDataAvailable(),
              let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)
        else {
            if !HKHealthStore.isHealthDataAvailable() {
                updateDiagnostics { $0.errorCode = .healthKitUnavailable }
            }
            return
        }

        if observerQuery == nil {
            let query = HKObserverQuery(sampleType: stepsType, predicate: nil) { [weak self] _, completion, _ in
                let gate = ObserverCompletion(completion)
                Task { @MainActor [weak self] in
                    guard let self else { gate.finish(); return }
                    let trace = HealthKitSyncTrace(trigger: .observer)
                    UserDefaults.standard.set(true, forKey: Self.pendingSyncKey)
                    self.updateDiagnostics {
                        $0.lastObserverWake = Date()
                        $0.lastTrigger = .observer
                    }
                    guard UIApplication.shared.isProtectedDataAvailable else {
                        self.updateDiagnostics { $0.errorCode = .protectedDataUnavailable }
                        trace.fail(.protectedDataUnavailable)
                        _ = trace.finish()
                        gate.finish()
                        return
                    }
                    guard self.hasAsked else { _ = trace.finish(); gate.finish(); return }
                    guard let session = self.session,
                          session.authSession != nil || session.client.auth.currentUser != nil else {
                        self.updateDiagnostics { $0.errorCode = .authenticationUnavailable }
                        trace.fail(.authenticationUnavailable)
                        _ = trace.finish()
                        gate.finish()
                        return
                    }
                    let userID = self.activeUserId
                    let operation = Task { @MainActor in
                        _ = await self.syncToBackend(session: session, trigger: .observer, trace: trace)
                        self.completeAttempt(trace, session: session, userID: userID)
                        gate.finish()
                    }
                    Task { @MainActor in
                        do { try await Task.sleep(for: .seconds(25)) } catch { return }
                        guard !gate.isFinished else { return }
                        operation.cancel()
                        if self.activeUserId == userID {
                            UserDefaults.standard.set(true, forKey: Self.pendingSyncKey)
                            self.updateDiagnostics { $0.errorCode = .attemptExpired }
                        }
                        self.completeAttempt(trace, session: session, userID: userID, cancelled: true)
                        gate.finish()
                    }
                }
            }
            observerQuery = query
            store.execute(query)
        }
        store.enableBackgroundDelivery(for: stepsType, frequency: .immediate) { [weak self] success, _ in
            Task { @MainActor [weak self] in
                self?.updateDiagnostics {
                    $0.deliveryRegistrationStatus = success ? .enabled : .unavailable
                    if success, $0.errorCode == .backgroundDeliveryUnavailable {
                        $0.errorCode = nil
                    } else if !success {
                        $0.errorCode = .backgroundDeliveryUnavailable
                    }
                }
            }
        }
    }

    func configure(session: SessionStore) {
        self.session = session
        if let userId = session.authSession?.user.id ?? session.client.auth.currentUser?.id {
            activate(userId: userId)
        }
        if let rawUserId = UserDefaults.standard.string(forKey: Self.pendingLocalDeletionKey),
           let userId = UUID(uuidString: rawUserId) {
            Task { _ = await deleteLocalData(userId: userId) }
        }
    }

    func activate(userId: UUID?) {
        guard activeUserId != userId else { refreshBackgroundStatus(); return }
        activeUserId = userId
        status = .idle
        connection = .notConnected
        if let userId,
           let data = UserDefaults.standard.data(forKey: Self.diagnosticsKey(userId: userId)),
           let saved = try? JSONDecoder().decode(Diagnostics.self, from: data) {
            diagnostics = saved
            refreshBackgroundStatus()
        } else {
            diagnostics = .current
        }
    }

    func deleteLocalData(userId: UUID) async -> Bool {
        UserDefaults.standard.set(userId.uuidString, forKey: Self.pendingLocalDeletionKey)
        await uploader.discardLegacy(userId: userId)
        do { try HealthKitUploadState.discardLegacy(userId: userId) } catch { return false }
        UserDefaults.standard.removeObject(forKey: Self.askedKey(userId: userId))
        UserDefaults.standard.removeObject(forKey: Self.diagnosticsKey(userId: userId))
        UserDefaults.standard.removeObject(forKey: Self.pendingSyncKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingLocalDeletionKey)
        let cleanupActiveUserId = activeUserId
        if cleanupActiveUserId == userId || cleanupActiveUserId == nil {
            if let observerQuery {
                store.stop(observerQuery)
                self.observerQuery = nil
            }
            if let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) {
                await withCheckedContinuation { continuation in
                    store.disableBackgroundDelivery(for: stepsType) { _, _ in continuation.resume() }
                }
            }
            guard activeUserId == cleanupActiveUserId else { installObserverAtLaunch(); return true }
            status = .idle
            connection = .notConnected
            diagnostics = .current
        }
        return true
    }

    func refresh(requestAccess: Bool, trace: HealthKitSyncTrace) async {
        let userID = activeUserId
        refreshBackgroundStatus()
        guard HKHealthStore.isHealthDataAvailable(),
              let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)
        else {
            updateDiagnostics { $0.errorCode = .healthKitUnavailable }
            trace.fail(.healthKitUnavailable)
            if requestAccess || hasAsked { status = .empty }
            return
        }
        if requestAccess {
            do {
                try await trace.measure(.authorization) {
                    try await store.requestAuthorization(toShare: [], read: [stepsType])
                }
            } catch {
                trace.fail(Self.errorCode(for: error))
                if activeUserId == userID { status = .empty }
            }
            guard activeUserId == userID else { trace.fail(.attemptExpired); return }
            if let activeUserId {
                UserDefaults.standard.set(true, forKey: Self.askedKey(userId: activeUserId))
            }
            installObserverAtLaunch()
        }
        guard requestAccess || hasAsked else { return }
        status = .reading
        do {
            try Task.checkCancellation()
            let count = try await trace.measure(.todayTotal) {
                try await Self.todayTotal(store: store, type: stepsType)
            }
            try Task.checkCancellation()
            guard activeUserId == userID else { trace.fail(.attemptExpired); return }
            if let count {
                status = .steps(count: count)
            } else {
                status = .empty
            }
        } catch {
            trace.fail(Self.errorCode(for: error))
            if activeUserId == userID { status = .empty }
        }
    }

    @discardableResult
    func syncToBackend(session: SessionStore, trigger: SyncTrigger, trace: HealthKitSyncTrace) async -> Bool {
        guard hasAsked, api.isConfigured else {
            if trigger == .observer { updateDiagnostics { $0.errorCode = .authenticationUnavailable } }
            return false
        }
        guard !isSyncing else { return false }
        guard UIApplication.shared.isProtectedDataAvailable else {
            updateDiagnostics { $0.errorCode = .protectedDataUnavailable }
            trace.fail(.protectedDataUnavailable)
            return false
        }
        guard HKHealthStore.isHealthDataAvailable(),
              let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount),
              let userId = session.authSession?.user.id ?? session.client.auth.currentUser?.id
        else {
            updateDiagnostics { $0.errorCode = .healthKitUnavailable }
            trace.fail(.healthKitUnavailable)
            return false
        }

        isSyncing = true
        connection = .syncing
        updateDiagnostics { $0.lastSyncAttempt = Date(); $0.lastTrigger = trigger }
        defer { isSyncing = false }
        do {
            await uploader.discardLegacy(userId: userId)
            try HealthKitUploadState.discardLegacy(userId: userId)
            try Task.checkCancellation()
            let contextToken = try await trace.measure(.session) { try await session.freshAccessToken() }
            guard activeUserId == userId, session.authSession?.user.id == userId else { throw CancellationError() }
            let context = try await api.healthKitUploadContext(accessToken: contextToken, trace: trace)
            let sync = try await HealthKitStepAggregates.read(store: store, type: stepsType, context: context, trace: trace)
            try Task.checkCancellation()
            let syncToken = try await trace.measure(.session) { try await session.freshAccessToken() }
            guard activeUserId == userId, session.authSession?.user.id == userId else { throw CancellationError() }
            _ = try await api.syncHealthKitSteps(sync, accessToken: syncToken, trace: trace)
            try Task.checkCancellation()
            guard activeUserId == userId else { throw CancellationError() }
            connection = .upToDate
            UserDefaults.standard.removeObject(forKey: Self.pendingSyncKey)
            updateDiagnostics {
                if trigger == .observer { $0.lastAutomaticSync = Date() }
                else { $0.lastManualSync = Date() }
                $0.errorCode = nil
            }
            return true
        } catch {
            trace.fail(Self.errorCode(for: error))
            guard activeUserId == userId else { return false }
            if case HealthKitStepAggregates.ReadError.noAccessibleSteps = error {
                connection = .noAccessibleSteps
            } else {
                connection = .syncFailed
            }
            UserDefaults.standard.set(true, forKey: Self.pendingSyncKey)
            updateDiagnostics { $0.errorCode = Self.errorCode(for: error) }
            return false
        }
    }

    private func refreshBackgroundStatus() {
        updateDiagnostics { $0.backgroundRefreshStatus = Self.backgroundRefreshStatus }
    }

    private func updateDiagnostics(_ update: (inout Diagnostics) -> Void) {
        var next = diagnostics
        update(&next)
        diagnostics = next
        guard let activeUserId, let data = try? JSONEncoder().encode(next) else { return }
        UserDefaults.standard.set(data, forKey: Self.diagnosticsKey(userId: activeUserId))
    }

    func completeAttempt(
        _ trace: HealthKitSyncTrace,
        session: SessionStore,
        userID: UUID?,
        cancelled: Bool = false
    ) {
        guard let attempt = trace.finish(cancelled: cancelled || Task.isCancelled), let userID,
              activeUserId == userID, session.authSession?.user.id == userID else { return }
        let snapshot = FitFightHealthKitDiagnosticSnapshot(diagnostics, attempts: [attempt])
        Task { await reportDiagnostics(snapshot, session: session, userID: userID) }
    }

    private func reportDiagnostics(
        _ snapshot: FitFightHealthKitDiagnosticSnapshot,
        session: SessionStore,
        userID: UUID
    ) async {
        guard api.isConfigured, activeUserId == userID, session.authSession?.user.id == userID else { return }
        do {
            let token = try await session.freshAccessToken()
            guard activeUserId == userID, session.authSession?.user.id == userID else { return }
            _ = try await api.saveHealthKitDiagnostics(snapshot, accessToken: token)
        } catch { }
    }

    private static var backgroundRefreshStatus: BackgroundRefreshStatus {
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: return .available
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .restricted
        }
    }

    static func errorCode(for error: Error) -> SyncErrorCode {
        if error is CancellationError { return .attemptExpired }
        if let urlError = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
            .cannotFindHost, .timedOut].contains(urlError.code) { return .networkUnavailable }
        if case FitFightAPIError.http(let status, _, _) = error, status == 401 {
            return .authenticationUnavailable
        }
        return .syncFailed
    }

    private static func todayTotal(store: HKHealthStore, type: HKQuantityType) async throws -> Int? {
        let now = Date()
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.startOfDay(for: now), end: now, options: .strictStartDate
        )
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate), options: [.cumulativeSum]
        )
        guard let statistics = try await descriptor.result(for: store) else { return nil }
        guard let count = HealthKitStepAggregates.integerCount(from: statistics.sumQuantity()),
              count > 0 else { return nil }
        return count
    }

    private static func askedKey(userId: UUID) -> String {
        "ff.healthkit.stepsAsked.\(userId.uuidString.lowercased())"
    }

    private static func diagnosticsKey(userId: UUID) -> String {
        diagnosticsPrefix + userId.uuidString.lowercased()
    }
}

private final class ObserverCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private let completion: () -> Void

    init(_ completion: @escaping () -> Void) { self.completion = completion }

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }

    func finish() {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        lock.unlock()
        completion()
    }
}
