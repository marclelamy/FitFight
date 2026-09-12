import SwiftUI
import UIKit
import UserNotifications

extension AppUpdateChecker {
    static let shared = AppUpdateChecker(
        version: AppVersion.marketing,
        build: AppVersion.build,
        releaseURL: APIConfig.publicOrigin.appendingPathComponent("api/app-release")
    )
}

@MainActor
final class FitFightAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        HealthKitStepsStore.shared.installObserverAtLaunch()
        UNUserNotificationCenter.current().delegate = PushNotificationService.shared
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { await PushNotificationService.shared.handleDeviceToken(deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        PushNotificationService.shared.handleRegistrationFailure()
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        HealthKitTUSUploader.registerBackgroundEvents(
            identifier: identifier,
            completion: completionHandler
        )
    }
}

@main
struct FitFightApp: App {
    @UIApplicationDelegateAdaptor(FitFightAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var themeStore = ThemeStore()
    @StateObject private var model = AppModel()
    @StateObject private var appUpdate = AppUpdateChecker.shared
    @StateObject private var session: SessionStore
    @StateObject private var steps: HealthKitStepsStore
    @StateObject private var feed = FeedStore()
    @StateObject private var push = PushNotificationService.shared

    init() {
        let session = SessionStore()
        let steps = HealthKitStepsStore.shared
        steps.configure(session: session)
        _session = StateObject(wrappedValue: session)
        _steps = StateObject(wrappedValue: steps)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeStore)
                .environmentObject(model)
                .environmentObject(session)
                .environmentObject(steps)
                .environmentObject(feed)
                .environmentObject(appUpdate)
                .environmentObject(push)
                .fitFightTheme(themeStore.theme)
                .task {
                    steps.onLocalAggregates = { sync in
                        model.applyLocalHealthKitScores(sync)
                    }
                    steps.onBackendSync = {
                        await model.refreshFromServer(session: session)
                    }
                    push.configure(session: session)
                    await push.refreshServerStatus()
                    await push.refreshAuthorizationStatus()
                    push.registerIfAuthorized()
                    if ScreenshotExport.isEnabled {
                        ScreenshotExport.exportAll()
                    }
                    #if DEBUG
                    await session.devAdoptSessionIfNeeded()
                    #endif
                }
                .task(id: session.authSession?.user.id) {
                    model.pendingReferralError = nil
                    steps.activate(userId: session.authSession?.user.id)
                    model.restoreCachedFights(session: session)
                    await model.refreshFights(session: session, steps: steps)
                    if appUpdate.status != .updateRequired,
                       !session.needsOnboarding,
                       !session.needsHealthOnboarding,
                       !session.needsNotificationOnboarding {
                        await push.considerPromptIfNeeded(fights: model.fights)
                    }
                }
                .task(id: session.profile?.userId) {
                    await model.consumePendingLinks(session: session)
                }
                .onOpenURL { url in
                    Task { await model.handleOpenURL(url, session: session) }
                }
                .onChange(of: session.needsOnboarding) { _, needsOnboarding in
                    guard !needsOnboarding, session.profile != nil else { return }
                    Task { await model.consumePendingLinks(session: session) }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active, session.authSession != nil else { return }
                    Task {
                        await model.refreshFights(session: session, steps: steps)
                    }
                }
        }
    }
}
