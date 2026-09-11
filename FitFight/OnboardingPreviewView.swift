import SwiftUI

/// Marc-only replay of Health + notification onboarding. Does not change the account.
struct OnboardingPreviewView: View {
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var showingNotifications = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(String(localized: "Close")) { dismiss() }
                    .ffType(.label)
                    .foregroundStyle(theme.mossText)
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.vertical, 12)

            if showingNotifications {
                NotificationOnboardingView(skipsIfAlreadyDetermined: false) {
                    dismiss()
                }
            } else {
                HealthOnboardingView {
                    showingNotifications = true
                }
            }
        }
        .background(theme.bg.ignoresSafeArea())
    }
}
