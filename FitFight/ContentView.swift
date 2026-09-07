import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var testFlightUpdate = TestFlightUpdateChecker()

    var body: some View {
        VStack(spacing: 0) {
            VersionBanner {
                model.showingVersions = true
            }
            if let build = testFlightUpdate.newerBuild {
                FFToast(
                    glyph: "↑",
                    title: String(localized: "New version on TestFlight"),
                    message: String(
                        localized: "testflight.update-ready",
                        defaultValue: "Build \(build) is ready. Open TestFlight and tap Update."
                    ),
                    tone: .moss,
                    onClose: { testFlightUpdate.dismiss() },
                    raised: false
                )
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.bottom, theme.space.base)
                .onTapGesture { testFlightUpdate.openTestFlight() }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if session.isSignedIn {
                signedInRoot
            } else {
                WelcomeView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .animation(theme.motion.sheet.animation, value: testFlightUpdate.newerBuild)
        .task {
            await testFlightUpdate.check()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await testFlightUpdate.check() }
        }
        .sheet(isPresented: $model.showingVersions) {
            VersionsView()
                .fitFightTheme(themeStore.theme)
                .presentationBackground(themeStore.theme.bg)
        }
        .sheet(isPresented: $model.showingRequests) {
            RequestsView()
                .environmentObject(session)
                .fitFightTheme(themeStore.theme)
                .presentationBackground(themeStore.theme.bg)
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
                        if let fight = model.fight(id: id) {
                            FightDetailView(fight: fight)
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
        .fitFightTheme(themeStore.theme)
}
