import SwiftUI

/// First-run Apple Health ask, right after the username. Permission stays on this phone.
struct HealthOnboardingView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme

    @State private var isConnecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 24)
            Text("Connect Apple Health")
                .ffType(.title)
                .foregroundStyle(theme.text)
            Text("FitFight reads your step count to score fights. We’ll ask iPhone for permission next. You can change this later in You.")
                .ffType(.body)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(3)
                .padding(.top, 10)
            FFScreenCTA(
                title: isConnecting ? String(localized: "Connecting…") : String(localized: "Continue"),
                enabled: !isConnecting
            ) {
                Task { await connect() }
            }
            .padding(.top, 28)
            Button {
                session.finishHealthOnboarding()
            } label: {
                Text("Not now")
                    .ffType(.label)
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
            }
            .buttonStyle(FFHapticPlainStyle())
            .disabled(isConnecting)
            Spacer(minLength: 24)
        }
        .padding(.horizontal, theme.space.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(theme.bg)
    }

    private func connect() async {
        isConnecting = true
        defer { isConnecting = false }
        await model.refreshFights(session: session, steps: steps, trigger: .manual, requestAccess: true)
        session.finishHealthOnboarding()
    }
}
