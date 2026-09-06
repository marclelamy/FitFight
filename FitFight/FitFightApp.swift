import SwiftUI
import UIKit

@MainActor
final class FitFightAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        HealthKitStepsStore.shared.installObserverAtLaunch()
        return true
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
    @StateObject private var session: SessionStore
    @StateObject private var steps: HealthKitStepsStore

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
                .fitFightTheme(themeStore.theme)
                .task {
                    if ScreenshotExport.isEnabled {
                        ScreenshotExport.exportAll()
                    }
                    #if DEBUG
                    await session.devAdoptSessionIfNeeded()
                    #endif
                }
                .task(id: session.authSession?.user.id) {
                    steps.activate(userId: session.authSession?.user.id)
                    model.restoreCachedFights(session: session)
                    await model.refreshFights(session: session, steps: steps)
                    await model.consumePendingJoinCode(session: session)
                }
                .onOpenURL { url in
                    Task { await model.handleOpenURL(url, session: session) }
                }
                .onChange(of: session.needsOnboarding) { _, needsOnboarding in
                    guard !needsOnboarding, session.profile != nil else { return }
                    Task { await model.consumePendingJoinCode(session: session) }
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
