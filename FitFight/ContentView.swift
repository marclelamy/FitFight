import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appUpdate: AppUpdateChecker
    @EnvironmentObject private var push: PushNotificationService
    @EnvironmentObject private var steps: HealthKitStepsStore
    @State private var dismissedUpdatePrompt = false

    var body: some View {
        VStack(spacing: 0) {
            VersionBanner(onTap: versionBannerTap)
            appContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg.ignoresSafeArea())
        .task(id: scenePhase) {
            guard scenePhase == .active, !ScreenshotExport.isEnabled else { return }
            await appUpdate.check()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                await appUpdate.check()
            }
        }
        .onChange(of: appUpdate.status) { previous, status in
            if status != .updateRequired {
                dismissedUpdatePrompt = false
            }
            if status == .current, previous != .checking, session.isSignedIn, session.profile == nil {
                Task { await session.loadProfile() }
            }
        }
        .alert(
            String(localized: "There’s a new update, please update"),
            isPresented: updatePromptPresented
        ) {
            if let release = appUpdate.policy?.latest {
                Button(String(localized: "Update FitFight")) {
                    openURL(release.updateURL)
                }
            }
            Button(String(localized: "Not now"), role: .cancel) {}
        }
    }

    private var updatePromptPresented: Binding<Bool> {
        Binding(
            get: {
                appUpdate.status == .updateRequired
                    && appUpdate.policy?.latest != nil
                    && !dismissedUpdatePrompt
                    && !ScreenshotExport.isEnabled
            },
            set: { if !$0 { dismissedUpdatePrompt = true } }
        )
    }

    private var appContent: some View {
        Group {
            if session.isSignedIn {
                signedInRoot
            } else {
                WelcomeView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $model.showingVersions) {
            VersionsView()
                .fitFightTheme(themeStore.theme)
                .presentationBackground(themeStore.theme.bg)
        }
        .sheet(isPresented: $model.showingDebugMenu) {
            DebugMenuView()
                .environmentObject(themeStore)
                .environmentObject(steps)
                .fitFightTheme(themeStore.theme)
                .presentationBackground(themeStore.theme.bg)
        }
        .onChange(of: session.isFitFightAdmin) { _, isAdmin in
            if !isAdmin { model.showingDebugMenu = false }
        }
        .sheet(isPresented: $model.showingRequests) {
            RequestsView()
                .environmentObject(session)
                .fitFightTheme(themeStore.theme)
                .presentationBackground(themeStore.theme.bg)
        }
        .sheet(item: $model.dailyStatusRecap) { recap in
            DailyStatusRecapView(recap: recap) {
                model.dailyStatusRecap = nil
            }
            .fitFightTheme(themeStore.theme)
            .presentationBackground(themeStore.theme.bg)
            .presentationDetents([.medium])
        }
        .alert("Couldn’t save referral", isPresented: Binding(
            get: { model.pendingReferralError != nil },
            set: { if !$0 { model.pendingReferralError = nil } }
        )) {
            Button("Try again") {
                Task { await model.consumePendingLinks(session: session) }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text(model.pendingReferralError ?? "")
        }
        .alert(
            String(localized: "Get fight-end reminders?"),
            isPresented: Binding(
                get: {
                    push.showPrePrompt
                        && !session.needsOnboarding
                        && !session.needsHealthOnboarding
                        && !session.needsNotificationOnboarding
                        && !session.needsRequestsOnboarding
                },
                set: { if !$0 { push.declinePrePrompt() } }
            )
        ) {
            Button(String(localized: "Allow notifications")) {
                Task { await push.requestSystemPermission() }
            }
            Button(String(localized: "Not now"), role: .cancel) {
                push.declinePrePrompt()
            }
        } message: {
            Text(String(localized: "FitFight can remind you when a fight ends and when to sync your steps. Lock-screen alerts never show scores or fight titles."))
        }
    }

    private var versionBannerTap: (() -> Void)? {
        guard session.isFitFightAdmin else { return nil }
        return { model.showingDebugMenu = true }
    }

    @ViewBuilder
    private var signedInRoot: some View {
        if session.profile == nil {
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    session.profileUnavailable
                        ? String(localized: "Couldn't load your account")
                        : String(localized: "Loading your account…")
                )
                    .ffType(.heading)
                    .foregroundStyle(theme.text)
                if session.profileUnavailable {
                    Text("Your profile is missing or the account was deleted. Sign out and start again.")
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let authError = session.authError {
                    Text(authError)
                        .ffType(.body)
                        .foregroundStyle(theme.emberText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if session.profileUnavailable {
                    // Without this the screen is a dead end — you cannot get back to
                    // the welcome screen to sign in as anyone else.
                    FFButton(title: String(localized: "Sign out"), kind: .secondary) {
                        Task { await session.signOut() }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, theme.space.screenPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else if session.needsOnboarding {
            OnboardingView()
        } else if session.needsHealthOnboarding {
            HealthOnboardingView()
        } else if session.needsNotificationOnboarding {
            NotificationOnboardingView()
        } else if session.needsRequestsOnboarding {
            RequestsOnboardingView()
        } else {
            signedInApp
        }
    }

    private var signedInApp: some View {
        ZStack {
            tabBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FFTabBar(tab: $model.tab, onReselect: {
                model.openFightID = nil
            })
        }
    }

    @ViewBuilder
    private var tabBody: some View {
        switch model.tab {
        case .fights:
            fightsStack
        case .newFight:
            NewFightView()
        case .feed:
            FeedView()
        case .you:
            YouView()
        }
    }

    private var fightsPath: Binding<[String]> {
        Binding(
            get: { model.openFightID.map { [$0] } ?? [] },
            set: { model.openFightID = $0.last }
        )
    }

    private var fightsStack: some View {
        NavigationStack(path: fightsPath) {
            FightsListView()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: String.self) { id in
                    Group {
                        if let fight = model.canonicalFight(for: id) {
                            FightDetailView(fight: fight)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(String(localized: "That fight isn’t on your list."))
                                    .ffType(.heading)
                                    .foregroundStyle(theme.text)
                                FFButton(title: String(localized: "Close"), kind: .secondary) {
                                    model.openFightID = nil
                                }
                            }
                            .padding(.horizontal, theme.space.screenPadding)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        }
                    }
                    .background(InteractivePopGestureEnabler(canPop: true, ownsDelegate: false))
                }
                .background(InteractivePopGestureEnabler(canPop: model.openFightID != nil, ownsDelegate: true))
        }
    }
}

/// Hidden nav bars disable edge-swipe back. The Fights stack owns the gesture
/// delegate so the list cannot freeze after a pop. `canPop` (not the list's
/// window) decides whether swipe is on, because NavigationStack detaches the
/// list view while a fight is open.
private struct InteractivePopGestureEnabler: UIViewRepresentable {
    var canPop: Bool
    var ownsDelegate: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(canPop: canPop, ownsDelegate: ownsDelegate)
    }

    func makeUIView(context: Context) -> SentinelView {
        let view = SentinelView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: SentinelView, context: Context) {
        uiView.coordinator = context.coordinator
        context.coordinator.canPop = canPop
        context.coordinator.ownsDelegate = ownsDelegate
        context.coordinator.sync(from: uiView)
    }

    final class SentinelView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.sync(from: self)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            coordinator?.sync(from: self)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var canPop: Bool
        var ownsDelegate: Bool
        weak var navigationController: UINavigationController?

        init(canPop: Bool, ownsDelegate: Bool) {
            self.canPop = canPop
            self.ownsDelegate = ownsDelegate
        }

        func sync(from view: UIView) {
            var responder: UIResponder? = view
            while let current = responder {
                if let found = current as? UINavigationController {
                    navigationController = found
                    break
                }
                if let controller = current as? UIViewController, let found = controller.navigationController {
                    navigationController = found
                    break
                }
                responder = current.next
            }
            guard let nav = navigationController else { return }
            if ownsDelegate {
                nav.interactivePopGestureRecognizer?.delegate = self
                nav.interactivePopGestureRecognizer?.isEnabled = canPop
            } else if canPop {
                nav.interactivePopGestureRecognizer?.isEnabled = true
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            canPop && (navigationController?.viewControllers.count ?? 0) > 1
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            canPop && otherGestureRecognizer is UIPanGestureRecognizer
        }
    }
}

#Preview {
    let themeStore = ThemeStore()
    let session = SessionStore(preview: ())
    return ContentView()
        .environmentObject(themeStore)
        .environmentObject(AppModel())
        .environmentObject(session)
        .environmentObject(HealthKitStepsStore())
        .environmentObject(FeedStore())
        .environmentObject(AppUpdateChecker.shared)
        .environmentObject(PushNotificationService.shared)
        .fitFightTheme(themeStore.theme)
}
