import Foundation
import UserNotifications
import UIKit

@MainActor
final class PushNotificationService: NSObject, ObservableObject {
    static let shared = PushNotificationService()

    @Published private(set) var apnsConfigured = false
    @Published private(set) var permissionStatus: UNAuthorizationStatus = .notDetermined
    @Published var showPrePrompt = false

    private let api = FitFightAPI()
    private var session: SessionStore?
    private var askedThisSession = false
    private static let declinedPrePromptKey = "ff.push.declinedPrePrompt"

    func configure(session: SessionStore) {
        self.session = session
    }

    var canPromptForPermission: Bool {
        permissionStatus == .notDetermined && !askedThisSession
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permissionStatus = settings.authorizationStatus
    }

    func refreshServerStatus() async {
        guard api.isConfigured else {
            apnsConfigured = false
            return
        }
        do {
            let status = try await api.notificationDeliveryStatus()
            apnsConfigured = status.apnsConfigured
        } catch {
            apnsConfigured = false
        }
    }

    func considerPromptIfNeeded(fights: [Fight]) async {
        await refreshAuthorizationStatus()
        guard canPromptForPermission, !hasHandledPrePrompt else {
            return
        }
        let now = Date()
        let hasUpcomingLiveFight = fights.contains { fight in
            guard fight.status == .live else { return false }
            return fight.windowEnd > now
        }
        guard hasUpcomingLiveFight else { return }
        showPrePrompt = true
        markPrePromptHandled()
    }

    func declinePrePrompt() {
        askedThisSession = true
        showPrePrompt = false
        markPrePromptHandled()
    }

    func markPromptHandledThisSession() {
        askedThisSession = true
        showPrePrompt = false
        markPrePromptHandled()
    }

    func requestSystemPermission() async {
        askedThisSession = true
        showPrePrompt = false
        markPrePromptHandled()
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        await refreshAuthorizationStatus()
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func registerIfAuthorized() {
        guard permissionStatus == .authorized else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func handleDeviceToken(_ deviceToken: Data) async {
        guard apnsConfigured, permissionStatus == .authorized,
              let session, session.authSession != nil else { return }
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        let locale = Locale.current.language.languageCode?.identifier == "fr" ? "fr" : "en"
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        do {
            let access = try await session.freshAccessToken()
            try await api.registerDeviceInstallation(
                token: token,
                apnsEnvironment: environment,
                locale: locale,
                permissionStatus: "authorized",
                accessToken: access
            )
        } catch {
            // Push registration is best-effort; fights still work without it.
        }
    }

    func handleRegistrationFailure() {
        // Missing push capability or simulator — no user-facing error.
    }

    private var hasHandledPrePrompt: Bool {
        UserDefaults.standard.bool(forKey: Self.declinedPrePromptKey)
    }

    private func markPrePromptHandled() {
        UserDefaults.standard.set(true, forKey: Self.declinedPrePromptKey)
    }

    func revokeLocalRegistration() async {
        guard let session, let userId = session.authSession?.user.id else { return }
        await revokeInstallations(for: userId)
    }

    private func revokeInstallations(for userId: UUID) async {
        _ = userId
        // Tokens are revoked server-side on account delete; sign-out keeps the row for re-login.
    }
}

extension PushNotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let route = response.notification.request.content.userInfo["fitfight_route"] as? String
            ?? (response.notification.request.content.userInfo["fitfight"] as? [String: Any])?["route"] as? String
        guard let route else { return }
        await MainActor.run {
            AppModel.storePendingFightRoute(route)
        }
    }
}
