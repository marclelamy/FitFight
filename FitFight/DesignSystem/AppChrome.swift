import SwiftUI

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

/// The screen shell: an optional pinned header, then scrolling content on the
/// screen background, with clearance for the tab bar.
struct FFScreen<Content: View>: View {
    var top: AnyView?
    var clearance: Bool = true
    @ViewBuilder var content: () -> Content

    @Environment(\.ffStaticRender) private var staticRender
    @Environment(\.ffTheme) private var theme

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
                ScrollView(.vertical) {
                    body(content())
                        // Root screens are one viewport wide. Child HStacks can wrap or
                        // truncate, but can no longer widen the scroll view and rubber-band.
                        .containerRelativeFrame(.horizontal)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let top { top }
                }
            }
        }
        .background(theme.bg)
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

enum FFTab: Hashable {
    case fights, newFight, you
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
