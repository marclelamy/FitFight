import Combine
import Foundation
import Supabase

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var authSession: Session?
    @Published private(set) var profile: FitFightProfile?
    @Published var authError: String?
    @Published private(set) var isBusy = false
    /// A missing account or failed profile load must not leave onboarding waiting forever.
    @Published private(set) var profileUnavailable = false
    private var screenshotSignedIn = false

    let client: SupabaseClient
    private let api = FitFightAPI()
    private static let handleChosenKey = "ff.handle.chosen"
    private static let needsHealthKey = "ff.onboarding.needsHealth"
    private static let needsNotificationKey = "ff.onboarding.needsNotifications"
    private static let needsRequestsKey = "ff.onboarding.needsRequests"
    private static let profileCachePrefix = "fitfight.profile."
    private static let adminHandle = "marc"

    var isSignedIn: Bool { authSession != nil || screenshotSignedIn }

    var needsOnboarding: Bool {
        guard isSignedIn, let profile else { return false }
        if UserDefaults.standard.bool(forKey: Self.handleChosenKey) { return false }
        if let setAt = profile.handleSetAt, !setAt.isEmpty { return false }
        return profile.looksGenerated
    }

    var needsHealthOnboarding: Bool {
        !needsOnboarding && UserDefaults.standard.bool(forKey: Self.needsHealthKey)
    }

    var needsNotificationOnboarding: Bool {
        !needsOnboarding && !needsHealthOnboarding
            && UserDefaults.standard.bool(forKey: Self.needsNotificationKey)
    }

    var needsRequestsOnboarding: Bool {
        !needsOnboarding && !needsHealthOnboarding && !needsNotificationOnboarding
            && UserDefaults.standard.bool(forKey: Self.needsRequestsKey)
    }

    var isFitFightAdmin: Bool {
        guard let handle = profile?.handle else { return false }
        return handle.caseInsensitiveCompare(Self.adminHandle) == .orderedSame
    }

    func finishHealthOnboarding() {
        UserDefaults.standard.set(false, forKey: Self.needsHealthKey)
        objectWillChange.send()
    }

    func finishNotificationOnboarding() {
        UserDefaults.standard.set(false, forKey: Self.needsNotificationKey)
        objectWillChange.send()
    }

    func finishRequestsOnboarding() {
        UserDefaults.standard.set(false, forKey: Self.needsRequestsKey)
        objectWillChange.send()
    }

    func freshAccessToken() async throws -> String {
        let userID = authSession?.user.id ?? client.auth.currentUser?.id
        let session = try await client.auth.session
        try Task.checkCancellation()
        guard session.user.id == userID, client.auth.currentUser?.id == userID,
              (authSession?.user.id ?? client.auth.currentUser?.id) == userID else {
            throw CancellationError()
        }
        authSession = session
        return session.accessToken
    }

    init(listenForSession: Bool = true) {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.projectURL,
            supabaseKey: SupabaseConfig.publishableKey.isEmpty
                ? "sb_publishable_missing"
                : SupabaseConfig.publishableKey
        )
        guard listenForSession else { return }
        Task { await listen() }
    }

    /// Screenshot / preview: no Keychain listener.
    convenience init(preview: Void) {
        self.init(listenForSession: false)
    }

    /// App Store screenshot fixture: signed in without touching Keychain or hosted data.
    convenience init(screenshot: Void) {
        self.init(listenForSession: false)
        screenshotSignedIn = true
        profile = FitFightProfile(
            userId: UUID(uuidString: "00CBEF0E-6851-4AAB-B47A-88B0D7946738")!,
            handle: "maya_moves",
            displayName: "Maya",
            handleSetAt: "2026-09-02T00:00:00Z",
            referralCode: nil,
            avatar: nil
        )
    }

    func signInWithApple(
        idToken: String,
        authorizationCode: String,
        nonce: String,
        fullName: String?
    ) async {
        authError = nil
        guard await AppUpdateChecker.shared.permitsRequests() else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let signedIn = try await client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: idToken,
                    nonce: nonce
                )
            )
            if let fullName, !fullName.isEmpty {
                try? await client.auth.update(
                    user: UserAttributes(
                        data: ["full_name": .string(fullName)]
                    )
                )
                if client.auth.currentUser?.id == signedIn.user.id {
                    _ = try? await api.updateProfile(displayName: fullName, accessToken: signedIn.accessToken)
                }
            }
            try? await api.storeAppleAuthorizationCode(
                authorizationCode,
                accessToken: signedIn.accessToken
            )
            await loadProfile()
        } catch {
            authError = Self.signInFailureMessage(error)
        }
    }

    #if DEBUG
    /// Adopts a session the run script minted. Same flow as the Next.js middleware:
    /// the script calls `admin/generate_link` with the secret key to mint a one-time
    /// token, exchanges it at `/auth/v1/verify`, and passes the resulting tokens here.
    /// The secret key never enters the app — only the finished session does.
    func devAdoptSessionIfNeeded() async {
        #if targetEnvironment(simulator)
        guard !isSignedIn else { return }
        let env = ProcessInfo.processInfo.environment
        guard let access = env["FF_DEV_ACCESS_TOKEN"], !access.isEmpty,
              let refresh = env["FF_DEV_REFRESH_TOKEN"], !refresh.isEmpty
        else { return }
        do {
            _ = try await client.auth.setSession(accessToken: access, refreshToken: refresh)
            await loadProfile()
        } catch {
            authError = String(
                localized: "session.dev-rejected",
                defaultValue: "Dev session rejected: \(error.localizedDescription)"
            )
        }
        #endif
    }

    #endif

    func signOut() async {
        authError = nil
        try? await client.auth.signOut()
        authSession = nil
        profile = nil
        profileUnavailable = false
        UserDefaults.standard.removeObject(forKey: Self.handleChosenKey)
        UserDefaults.standard.removeObject(forKey: Self.needsHealthKey)
        UserDefaults.standard.removeObject(forKey: Self.needsNotificationKey)
        UserDefaults.standard.removeObject(forKey: Self.needsRequestsKey)
    }

    static func signInFailureMessage(_ error: Error) -> String {
        let text = error.localizedDescription.lowercased()
        if text.contains("invalid api key") || text.contains("another supabase project") {
            return String(localized: "This build’s key doesn’t match the staging database.")
        }
        if text.contains("provider is not enabled")
            || text.contains("unsupported provider")
            || text.contains("provider not enabled") {
            return String(localized: "Apple Sign In is off on this database.")
        }
        if text.contains("nscurlerror")
            || text.contains("nsurlerrordomain")
            || text.contains("could not connect")
            || text.contains("hostname could not be found")
            || text.contains("not known") {
            return String(localized: "Can’t reach the staging database.")
        }
        return String(localized: "Couldn’t sign in. Try again.")
    }

    static func isValidHandle(_ raw: String) -> Bool {
        let handle = strippedHandle(raw)
        return handle.range(of: "^[a-z0-9_]{2,30}$", options: .regularExpression) != nil
    }

    static func strippedHandle(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
    }

    func setHandle(_ raw: String, avatarMediaId: UUID? = nil) async throws {
        guard await AppUpdateChecker.shared.permitsRequests() else {
            let requiresUpdate = AppUpdateChecker.shared.status == .updateRequired
            throw FitFightAPIError.http(
                status: requiresUpdate ? 426 : 503,
                code: requiresUpdate ? "update_required" : "release_unavailable",
                message: nil
            )
        }
        guard let userId = authSession?.user.id ?? client.auth.currentUser?.id else {
            throw HandleError.notSignedIn
        }
        let handle = Self.strippedHandle(raw)
        guard Self.isValidHandle(handle) else {
            throw HandleError.invalid
        }
        do {
            let token = try await freshAccessToken()
            let updated = try await api.updateProfile(
                handle: handle,
                avatarMediaId: avatarMediaId,
                accessToken: token
            )
            UserDefaults.standard.set(true, forKey: Self.handleChosenKey)
            UserDefaults.standard.set(true, forKey: Self.needsHealthKey)
            UserDefaults.standard.set(true, forKey: Self.needsNotificationKey)
            UserDefaults.standard.set(true, forKey: Self.needsRequestsKey)
            try Task.checkCancellation()
            guard authSession?.user.id == userId, client.auth.currentUser?.id == userId else {
                throw CancellationError()
            }
            profile = updated
            if let data = try? JSONEncoder().encode(updated) {
                UserDefaults.standard.set(data, forKey: Self.profileCachePrefix + userId.uuidString)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if case FitFightAPIError.http(_, let code, _) = error {
                if code == "handle_taken" { throw HandleError.taken }
                if code == "validation" { throw HandleError.invalid }
                if code == "profile_missing" {
                    markProfileMissing(for: userId)
                    throw HandleError.notSignedIn
                }
            }
            throw HandleError.failed
        }
    }

    func setAvatar(_ media: FitFightMedia) async throws {
        guard let userId = authSession?.user.id ?? client.auth.currentUser?.id else {
            throw HandleError.notSignedIn
        }
        let token = try await freshAccessToken()
        let updated = try await api.updateProfile(avatarMediaId: media.id, accessToken: token)
        try Task.checkCancellation()
        guard authSession?.user.id == userId else { throw CancellationError() }
        profile = updated
        if let data = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(data, forKey: Self.profileCachePrefix + userId.uuidString)
        }
    }

    @discardableResult
    func deleteAccount() async -> Bool {
        authError = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let userID = authSession?.user.id ?? client.auth.currentUser?.id
            let renewedSession = try await client.auth.refreshSession()
            try Task.checkCancellation()
            guard renewedSession.user.id == userID, client.auth.currentUser?.id == userID,
                  (authSession?.user.id ?? client.auth.currentUser?.id) == userID else {
                throw CancellationError()
            }
            authSession = renewedSession
            let deletion = try await api.deleteAccount(accessToken: renewedSession.accessToken)
            try? await client.auth.signOut()
            authSession = nil
            profile = nil
            profileUnavailable = false
            UserDefaults.standard.removeObject(forKey: Self.handleChosenKey)
            UserDefaults.standard.removeObject(forKey: Self.needsHealthKey)
            UserDefaults.standard.removeObject(forKey: Self.needsNotificationKey)
            UserDefaults.standard.removeObject(forKey: Self.needsRequestsKey)
            if let userID {
                UserDefaults.standard.removeObject(forKey: Self.profileCachePrefix + userID.uuidString)
            }
            if !deletion.appleAuthorizationRevoked {
                authError = String(localized: "Account deleted. To disconnect Apple too, open iPhone Settings, tap your name, then Sign in with Apple → FitFight → Stop Using Apple ID.")
            }
            return true
        } catch {
            authError = String(localized: "Couldn’t delete account. Try again.")
            return false
        }
    }

    private func listen() async {
        for await (event, session) in client.auth.authStateChanges {
            if let session {
                if event == .tokenRefreshed, authSession?.user.id == session.user.id,
                   profile?.userId == session.user.id {
                    authSession = session
                    continue
                }
                profileUnavailable = false
                if let data = UserDefaults.standard.data(
                    forKey: Self.profileCachePrefix + session.user.id.uuidString
                ),
                    let cached = try? JSONDecoder().decode(FitFightProfile.self, from: data),
                    cached.userId == session.user.id
                {
                    profile = cached
                } else {
                    profile = nil
                }
                authSession = session
                await loadProfile()
            } else {
                authSession = nil
                profile = nil
            }
        }
    }

    func loadProfile() async {
        guard await AppUpdateChecker.shared.permitsRequests() else { return }
        guard let userId = authSession?.user.id ?? client.auth.currentUser?.id else {
            profile = nil
            return
        }
        profileUnavailable = false
        for attempt in 0..<3 {
            do {
                let token = try await freshAccessToken()
                let row = try await api.profile(accessToken: token)
                try Task.checkCancellation()
                guard authSession?.user.id == userId, client.auth.currentUser?.id == userId else { return }
                profile = row
                if let data = try? JSONEncoder().encode(row) {
                    UserDefaults.standard.set(data, forKey: Self.profileCachePrefix + userId.uuidString)
                }
                return
            } catch {
                guard !Task.isCancelled, !(error is CancellationError),
                      authSession?.user.id == userId, client.auth.currentUser?.id == userId else { return }
                if case FitFightAPIError.http(_, let code, _) = error, code == "profile_missing" {
                    markProfileMissing(for: userId)
                    return
                }
                if attempt == 2 {
                    if profile?.userId != userId {
                        profile = nil
                        profileUnavailable = true
                    }
                } else {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
        }
    }

    private func markProfileMissing(for userId: UUID) {
        guard (authSession?.user.id ?? client.auth.currentUser?.id) == userId else { return }
        profile = nil
        profileUnavailable = true
        UserDefaults.standard.removeObject(forKey: Self.profileCachePrefix + userId.uuidString)
    }
}

enum HandleError: LocalizedError {
    case notSignedIn
    case invalid
    case taken
    case failed

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return String(localized: "Sign in first.")
        case .invalid: return String(localized: "Use 2–30 letters, numbers, or underscore.")
        case .taken: return String(localized: "That username is taken.")
        case .failed: return String(localized: "Couldn’t save that username.")
        }
    }
}
