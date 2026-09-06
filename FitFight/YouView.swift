import SwiftUI
import UIKit

struct YouView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender
    @State private var confirmDelete = false
    @State private var copied = false

    var body: some View {
        FFScreen {
            profile
            if session.isSignedIn, let authError = session.authError {
                FFNotice(text: authError, tone: .ember, systemImage: "exclamationmark.triangle")
            }

            FFSection(title: String(localized: "Apple Health")) {
                health
            }

            FFSection(title: String(localized: "Settings")) {
                settings
            }

            FFSection(title: String(localized: "Look")) {
                appearance
            }
        }
        .task {
            guard !staticRender else { return }
            await model.refreshFights(session: session, steps: steps)
        }
        .confirmationDialog(
            "Delete account?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                Task {
                    let userId = session.authSession?.user.id
                    if await session.deleteAccount(), let userId {
                        model.removeCachedFights(for: userId)
                        if !(await steps.deleteLocalData(userId: userId)) {
                            let cleanupMessage = String(localized: "Your account was deleted. FitFight will retry removing its local Health cache when you reopen the app.")
                            if let authError = session.authError {
                                session.authError = "\(authError) \(cleanupMessage)"
                            } else {
                                session.authError = cleanupMessage
                            }
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your profile, uploaded Steps, invitations, fights you created, and bugs or requests you posted; removes you from other fights; and signs you out. This can’t be undone.")
        }
    }

    @ViewBuilder
    private var profile: some View {
        if session.isSignedIn {
            HStack(spacing: 14) {
                FFAvatar(monogram: session.profile?.initials ?? "FF", size: 68, selected: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: session.profile?.displayName ?? String(localized: "Signed in"))
                        .ffType(.heading)
                        .foregroundStyle(theme.text)
                    Text(verbatim: session.profile?.atHandle ?? String(localized: "Profile isn’t ready yet"))
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                    if session.profile != nil {
                        Button {
                            UIPasteboard.general.string = session.profile?.atHandle ?? ""
                            copied = true
                        } label: {
                            Text(copied ? String(localized: "Copied") : String(localized: "Copy username"))
                                .ffType(.micro)
                                .fontWeight(.heavy)
                                .foregroundStyle(theme.mossText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: 4)
            }
        } else {
            AppleSignInControl()
        }
    }

    private var health: some View {
        FFGroupedRows {
            Button {
                Task {
                    await model.refreshFights(session: session, steps: steps, trigger: .manual, requestAccess: true)
                }
            } label: {
                FFGroupedRow(
                    title: String(localized: "Apple Health Steps"),
                    subtitle: steps.metaText.isEmpty
                        ? steps.detailText
                        : "\(steps.detailText) · \(steps.metaText)",
                    systemImage: "heart",
                    enabled: steps.status != .reading && !model.isRefreshingFights,
                    subtitleTone: steps.isConnected ? .moss : .neutral,
                    trailing: AnyView(
                        FFPill(
                            steps.isConnected ? String(localized: "On") : String(localized: "Connect"),
                            style: steps.isConnected ? .softMoss : .solidMoss
                        )
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(steps.status == .reading || model.isRefreshingFights)
            FFDivider()
            FFGroupedRow(
                title: String(localized: "Background App Refresh"),
                subtitle: steps.backgroundRefreshText,
                systemImage: "arrow.clockwise",
                subtitleTone: steps.diagnostics.backgroundRefreshStatus == .available ? .moss : .neutral,
                trailing: steps.diagnostics.backgroundRefreshStatus == .denied
                    ? AnyView(FFPill(String(localized: "Open Settings"), style: .softMoss)) : nil,
                action: steps.diagnostics.backgroundRefreshStatus == .denied
                    ? { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                    : nil
            )
            FFDivider()
            FFGroupedRow(
                title: String(localized: "HealthKit background delivery"),
                subtitle: steps.backgroundDeliveryText,
                systemImage: "heart.text.square",
                subtitleTone: steps.diagnostics.deliveryRegistrationStatus == .enabled ? .moss : .neutral
            )
            FFDivider()
            FFGroupedRow(
                title: String(localized: "Last automatic sync"),
                subtitle: diagnosticDate(steps.diagnostics.lastAutomaticSync),
                systemImage: "bolt"
            )
            FFDivider()
            FFGroupedRow(
                title: String(localized: "Last manual or foreground sync"),
                subtitle: diagnosticDate(steps.diagnostics.lastManualSync),
                systemImage: "hand.tap"
            )
            if let failure = steps.currentFailureText {
                FFDivider()
                FFGroupedRow(
                    title: String(localized: "Current sync issue"),
                    subtitle: failure,
                    systemImage: "exclamationmark.triangle",
                    subtitleTone: .ember
                )
            }
        }
    }

    private func diagnosticDate(_ date: Date?) -> String {
        guard let date else { return String(localized: "Not yet") }
        return date.formatted(.relative(presentation: .named))
    }

    private var settings: some View {
        FFGroupedRows {
            navRow(String(localized: "Bugs & requests")) {
                model.showingRequests = true
            }
            FFDivider()
            linkRow(String(localized: "Privacy"), destination: sitePage("privacy"))
            FFDivider()
            linkRow(String(localized: "Support"), destination: sitePage("support"))
            FFDivider()
            navRow(String(localized: "Versions")) { model.showingVersions = true }
            if session.isSignedIn {
                FFDivider()
                navRow(String(localized: "Sign out")) {
                    Task { await session.signOut() }
                }
                FFDivider()
                navRow(String(localized: "Delete account"), destructive: true) {
                    confirmDelete = true
                }
            }
        }
    }

    private var appearance: some View {
        HStack(spacing: 10) {
            ForEach(Mode.allCases) { mode in
                let on = themeStore.mode == mode
                Button {
                    themeStore.mode = mode
                } label: {
                    Text(mode.label)
                        .ffType(.label)
                        .foregroundStyle(on ? theme.mossOn : theme.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            on ? theme.mossFill : theme.card,
                            in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous)
                        )
                        .ffBorder(on ? theme.mossEdge : theme.hairline, radius: theme.radius.field)
                }
                .buttonStyle(FFPressStyle(scale: 0.97))
            }
        }
    }

    private var siteURL: URL {
        URL(string: AppVersion.backend == "prod" ? "https://fitfight.app" : "https://staging.fitfight.app")!
    }

    private func sitePage(_ path: String) -> URL {
        let root = Bundle.main.preferredLocalizations.first?.hasPrefix("fr") == true
            ? siteURL.appending(path: "fr")
            : siteURL
        return root.appending(path: path)
    }

    private func linkRow(_ title: String, destination: URL) -> some View {
        Link(destination: destination) {
            rowLabel(title: title, destructive: false)
        }
        .buttonStyle(.plain)
    }

    private func navRow(
        _ title: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            rowLabel(title: title, destructive: destructive)
        }
        .buttonStyle(.plain)
        .disabled(session.isBusy)
    }

    private func rowLabel(title: String, destructive: Bool) -> some View {
        HStack {
            Text(title)
                .ffType(.rowTitle)
                .foregroundStyle(destructive ? theme.emberText : theme.text)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.textFaint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
