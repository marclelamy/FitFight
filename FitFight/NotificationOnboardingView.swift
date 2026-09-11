import SwiftUI

/// First-run notification ask, after Apple Health. Pre-prompt before iPhone’s sheet.
struct NotificationOnboardingView: View {
    var skipsIfAlreadyDetermined: Bool = true
    var onFinished: (() -> Void)? = nil

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var push: PushNotificationService
    @Environment(\.ffTheme) private var theme

    @State private var isAsking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 24)
            Text("Challenge reminders")
                .ffType(.title)
                .foregroundStyle(theme.text)
            Text("FitFight will send challenge reminders. Lock-screen alerts never include step counts.")
                .ffType(.body)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(3)
                .padding(.top, 10)
            FFScreenCTA(
                title: String(localized: "Continue"),
                enabled: !isAsking,
                busy: isAsking
            ) {
                Task { await allow() }
            }
            .padding(.top, 28)
            Button {
                skip()
            } label: {
                Text("Not now")
                    .ffType(.label)
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
            }
            .buttonStyle(FFHapticPlainStyle())
            .disabled(isAsking)
            Spacer(minLength: 24)
        }
        .padding(.horizontal, theme.space.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(theme.bg)
        .task {
            await push.refreshAuthorizationStatus()
            guard skipsIfAlreadyDetermined else { return }
            if push.permissionStatus != .notDetermined {
                push.markPromptHandledThisSession()
                if push.permissionStatus == .authorized {
                    push.registerIfAuthorized()
                }
                finish()
            }
        }
    }

    private func allow() async {
        isAsking = true
        defer { isAsking = false }
        await push.requestSystemPermission()
        finish()
    }

    private func skip() {
        push.declinePrePrompt()
        finish()
    }

    private func finish() {
        session.finishNotificationOnboarding()
        onFinished?()
    }
}
