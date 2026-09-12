import SwiftUI

/// Last onboarding step: Settings can take a bug or a feature request.
struct RequestsOnboardingView: View {
    var onFinished: (() -> Void)? = nil

    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 24)
            Text("Bugs & requests")
                .ffType(.title)
                .foregroundStyle(theme.text)
            Text("You can go to Settings to submit a feature you want or a bug you see. Those will be fixed rapidly.")
                .ffType(.body)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(3)
                .padding(.top, 10)
            FFScreenCTA(title: String(localized: "OK")) {
                finish()
            }
            .padding(.top, 28)
            Spacer(minLength: 24)
        }
        .padding(.horizontal, theme.space.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(theme.bg)
    }

    private func finish() {
        session.finishRequestsOnboarding()
        onFinished?()
    }
}
