import SwiftUI
import UIKit

// App chrome that the kit specifies outside the twelve sections: the tab bar
// (TabBarDark.dc.html) and the screen shell everything scrolls inside.

private struct FFStaticRenderKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while ScreenshotExport renders screens off-screen, where scroll views stay blank.
    var ffStaticRender: Bool {
        get { self[FFStaticRenderKey.self] }
        set { self[FFStaticRenderKey.self] = newValue }
    }
}

/// Pull-to-refresh that stays open with a spinner and a live status line.
struct FFRefreshConfig {
    var isRefreshing: Bool
    var message: String
    var action: @MainActor () async -> Void
}

/// Spinner plus the current sync sentence. Gold is progress.
struct FFRefreshStatus: View {
    let message: String
    var spinning: Bool = true

    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .tint(theme.gold)
                .opacity(spinning ? 1 : 0.55)
                .scaleEffect(spinning ? 1 : 0.86)
            if !message.isEmpty {
                Text(message)
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, theme.space.screenPadding)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("refresh-status")
        .accessibilityLabel(message)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// The screen shell: an optional pinned header, then scrolling content on the
/// screen background, with clearance for the tab bar.
struct FFScreen<Content: View>: View {
    var top: AnyView?
    var clearance: Bool = true
    var refresh: FFRefreshConfig? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.ffStaticRender) private var staticRender
    @Environment(\.ffTheme) private var theme
    @State private var holdOpen = false
    @State private var displayedMessage = ""

    private let restingHeight: CGFloat = 88

    private var showLockedHeader: Bool {
        !staticRender && ((refresh?.isRefreshing ?? false) || holdOpen)
    }

    var body: some View {
        Group {
            if staticRender {
                // Color.clear takes exactly the offered size, so an overlay on top of it
                // pins the screen to the top and lets anything taller run off the bottom
                // instead of being centred.
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .top) {
                        VStack(spacing: 0) {
                            if let top { top }
                            body(content())
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
            } else {
                liveScroll
            }
        }
        .background(theme.bg)
    }

    private var liveScroll: some View {
        ScrollView(.vertical) {
            body(content())
                // Root screens are one viewport wide. Child HStacks can wrap or
                // truncate, but can no longer widen the scroll view and rubber-band.
                .containerRelativeFrame(.horizontal)
                .background(alignment: .top) {
                    if refresh != nil {
                        FFAlwaysBounceVertical()
                    }
                }
        }
        .scrollBounceBehavior(.always, axes: .vertical)
        .ffRefreshable(refresh != nil) {
            await runRefresh()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if let top { top }
                if showLockedHeader {
                    FFRefreshStatus(
                        message: displayedMessage,
                        spinning: true
                    )
                    .frame(height: restingHeight)
                    .transition(.opacity)
                }
            }
        }
        .onChange(of: refresh?.isRefreshing ?? false) { _, refreshing in
            if !refreshing, !holdOpen {
                displayedMessage = ""
            }
        }
        .onChange(of: refresh?.message ?? "") { _, message in
            if !message.isEmpty {
                displayedMessage = message
            }
        }
        .onChange(of: showLockedHeader) { _, open in
            if open, displayedMessage.isEmpty, let message = refresh?.message, !message.isEmpty {
                displayedMessage = message
            }
            if !open {
                displayedMessage = ""
            }
        }
        .animation(theme.motion.sheet.animation, value: showLockedHeader)
        .animation(theme.motion.quick.animation, value: displayedMessage)
    }

    @MainActor
    private func runRefresh() async {
        guard let refresh else { return }
        holdOpen = true
        await refresh.action()
        holdOpen = false
    }

    private func body(_ content: Content) -> some View {
        VStack(alignment: .leading, spacing: theme.space.cardGap) {
            content
        }
        .padding(.horizontal, theme.space.screenPadding)
        .padding(.top, theme.space.base)
        .padding(.bottom, clearance ? theme.space.tabBarClearance : theme.space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    @ViewBuilder
    func ffRefreshable(_ enabled: Bool, action: @escaping () async -> Void) -> some View {
        if enabled {
            refreshable(action: action)
        } else {
            self
        }
    }
}

// NOTE: SwiftUI ScrollView only bounces when content is taller than the screen unless
// `alwaysBounceVertical` is set on the underlying UIScrollView. That is what lets a
// short Fights / Feed / fight screen still pull to refresh.
private struct FFAlwaysBounceVertical: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
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

    final class Coordinator {
        func sync(from view: UIView) {
            var current: UIView? = view
            while let node = current {
                if let scroll = node as? UIScrollView {
                    scroll.alwaysBounceVertical = true
                    scroll.bounces = true
                    return
                }
                current = node.superview
            }
        }
    }
}

enum FFTab: Hashable {
    case fights, newFight, feed, you
}

/// 46×32 glyph pill, 22pt icon, 11pt label. The live tab takes the moss wash.
struct FFTabBar: View {
    @Binding var tab: FFTab
    /// iOS convention: tapping the already-selected tab returns that tab to its root.
    var onReselect: (() -> Void)? = nil
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            item(.fights, "trophy", String(localized: "Fights"))
            item(.newFight, "plus.circle", String(localized: "New"))
            item(.feed, "text.below.photo", String(localized: "Feed"))
            item(.you, "person", String(localized: "You"))
        }
        // The kit uses the classic full-width iPhone geometry: about 49pt of
        // controls plus the device's bottom safe area. Extra top/bottom padding
        // would make the custom bar feel tall.
        .frame(height: 50)
        .padding(.horizontal, 10)
        .background {
            // The kit's fill is 94% opaque. On a mock nothing scrolls under it; in the
            // app it does, so it sits on a blur the way every iOS tab bar does.
            theme.tabBar
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            theme.tabBarLine.frame(height: 1)
        }
    }

    private func item(_ value: FFTab, _ symbol: String, _ title: String) -> some View {
        let on = tab == value
        return Button {
            if tab == value {
                onReselect?()
            } else {
                tab = value
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: on ? "\(symbol).fill" : symbol)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(on ? theme.tabInkOn : theme.tabInkOff)
                    .frame(width: 46, height: 30)
                    .background(
                        on ? theme.tabPillOn : .clear,
                        in: RoundedRectangle(cornerRadius: theme.radius.glyph, style: .continuous)
                    )
                Text(title)
                    .font(.ff(11, on ? 800 : 700))
                    .foregroundStyle(on ? theme.tabInkOn : theme.tabInkOff)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(FFHapticPlainStyle())
    }
}

/// A screen's big title and supporting line. The kit's boxed nav headers are for
/// detail and flow screens; a root tab just states its name.
struct FFScreenTitle: View {
    let title: String
    var subtitle: String?
    var trailing: AnyView?

    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .ffType(.title)
                    .foregroundStyle(theme.text)
                if let subtitle {
                    Text(subtitle)
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
            if let trailing { trailing }
        }
    }
}

/// Hard rule from AGENTS.md: the version label stays at the top of the screen.
struct VersionBanner: View {
    @Environment(\.ffTheme) private var theme
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            Text(AppVersion.label)
                .ffType(.micro)
                .foregroundStyle(theme.textFaint)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .padding(.bottom, 6)
        }
        .buttonStyle(FFHapticPlainStyle())
        .disabled(onTap == nil)
        .accessibilityIdentifier("app-version")
    }
}
