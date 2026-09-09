import SwiftUI
import UIKit

/// Renders every screen to PNG so CI can publish them as artifacts and we can
/// compare the app against docs/design/source/screenshots without a Mac.
/// Only runs when the app is launched with FF_SHOOT=1.
@MainActor
enum ScreenshotExport {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["FF_SHOOT"] == "1"
    }

    static let canvas = CGSize(width: 393, height: 852)
    static let appStoreCanvas = CGSize(width: 440, height: 956)
    static let tallHeight: CGFloat = 1800
    static let designSystemSliceHeight: CGFloat = 2_600
    static let designSystemSlices = 5

    static func exportAll() {
        let themeStore = ThemeStore(transient: .night)

        let model = AppModel()
        let folder = URL.documentsDirectory.appendingPathComponent("shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        for shot in shots(model: model) {
            write(shot.view(themeStore, model), name: shot.name, height: canvas.height, to: folder)
            write(shot.view(themeStore, model), name: shot.name + "-full", height: tallHeight, to: folder)
        }

        for shot in appStoreShots(model: model) {
            write(
                shot.view(themeStore, model),
                name: shot.name,
                size: appStoreCanvas,
                scale: 3,
                jpeg: true,
                to: folder
            )
        }

        let light = ThemeStore(transient: .day)

        write(
            frame(FightsListView(), tab: .fights, themeStore: light, model: model),
            name: "light-fights",
            height: canvas.height,
            to: folder
        )
        write(
            frame(YouView(), tab: .you, themeStore: light, model: model),
            name: "light-you",
            height: canvas.height,
            to: folder
        )

        // The design system page is one long scroll. ImageRenderer returns nil well
        // before the texture limit, so it is exported as a run of slices instead of
        // one tall canvas.
        for store in [themeStore, light] {
            for slice in 0..<designSystemSlices {
                write(
                    designSystem(store, slice: slice),
                    name: "09-design-system-\(store.mode.rawValue)-\(slice + 1)",
                    height: designSystemSliceHeight,
                    to: folder
                )
            }
        }

        let localization = Bundle.main.preferredLocalizations.first ?? "unknown"
        try? Data(localization.utf8).write(to: folder.appendingPathComponent("done.txt"))
    }

    private struct Shot {
        let name: String
        let view: (ThemeStore, AppModel) -> AnyView
    }

    private static func shots(model: AppModel) -> [Shot] {
        let fight = model.fights.first { $0.id == "sweat" }
        let invited = model.fights.first { $0.id == "desk" }
        return [
            Shot(name: "00-welcome") { store, _ in
                let theme = store.theme
                return AnyView(
                    VStack(spacing: 0) {
                        VersionBanner()
                        WelcomeView()
                    }
                    .background(theme.bg)
                    .environmentObject(store)
                    .environmentObject(model)
                    .environmentObject(SessionStore(preview: ()))
                    .environmentObject(HealthKitStepsStore())
                    .environment(\.ffTheme, theme)
                    .environment(\.colorScheme, theme.colorScheme)
                    .environment(\.ffStaticRender, true)
                )
            },
            Shot(name: "01-fights") { store, model in
                frame(FightsListView(), tab: .fights, themeStore: store, model: model)
            },
            Shot(name: "02-fight-detail") { store, model in
                frame(detail(fight), tab: .fights, themeStore: store, model: model)
            },
            Shot(name: "03-fight-invited") { store, model in
                frame(detail(invited), tab: .fights, themeStore: store, model: model)
            },
            Shot(name: "04-new") { store, model in
                frame(NewFightView(opening: .choose), tab: .newFight, themeStore: store, model: model)
            },
            Shot(name: "04-new-join") { store, model in
                frame(NewFightView(opening: .join), tab: .newFight, themeStore: store, model: model)
            },
            Shot(name: "05-you") { store, model in
                frame(YouView(), tab: .you, themeStore: store, model: model)
            },
            Shot(name: "05-feed") { store, model in
                frame(FeedView(), tab: .feed, themeStore: store, model: model)
            },
            Shot(name: "06-requests") { store, model in
                sheet(RequestsScreenshot.board(), themeStore: store, model: model)
            },
            Shot(name: "07-request-detail") { store, model in
                sheet(RequestsScreenshot.detail(), themeStore: store, model: model)
            },
            Shot(name: "08-request-compose") { store, model in
                sheet(RequestsScreenshot.compose(), themeStore: store, model: model)
            },
        ]
    }

    private static func appStoreShots(model: AppModel) -> [Shot] {
        var fight = model.fights.first { $0.id == "sweat" }
        fight?.id = "appstore-sweat"
        fight?.days = []
        let invited = model.fights.first { $0.id == "desk" }
        return [
            Shot(name: "appstore-01-fights") { store, model in
                frame(FightsListView(), tab: .fights, themeStore: store, model: model)
            },
            Shot(name: "appstore-02-fight-detail") { store, model in
                frame(detail(fight), tab: .fights, themeStore: store, model: model)
            },
            Shot(name: "appstore-03-new") { store, model in
                frame(NewFightView(opening: .choose), tab: .newFight, themeStore: store, model: model)
            },
            Shot(name: "appstore-04-invitation") { store, model in
                frame(detail(invited), tab: .fights, themeStore: store, model: model)
            },
            Shot(name: "appstore-05-you") { store, model in
                frame(YouView(), tab: .you, themeStore: store, model: model)
            }
        ]
    }

    /// Lays the whole page out once, then shows one slice of it.
    private static func designSystem(_ store: ThemeStore, slice: Int) -> AnyView {
        let theme = store.theme
        let full = designSystemSliceHeight * CGFloat(designSystemSlices)
        return AnyView(
            DesignSystemView()
                .environmentObject(store)
                .environment(\.ffTheme, theme)
                .environment(\.colorScheme, theme.colorScheme)
                .environment(\.ffStaticRender, true)
                .frame(width: canvas.width, height: full, alignment: .top)
                .offset(y: -CGFloat(slice) * designSystemSliceHeight)
                .frame(width: canvas.width, height: designSystemSliceHeight, alignment: .top)
                .clipped()
                .background(theme.bg)
        )
    }

    @ViewBuilder
    private static func detail(_ fight: Fight?) -> some View {
        if let fight {
            FightDetailView(fight: fight)
        } else {
            Color.clear
        }
    }

    private static func sheet<Content: View>(
        _ content: Content,
        themeStore: ThemeStore,
        model: AppModel
    ) -> AnyView {
        let theme = themeStore.theme
        return AnyView(
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) {
                    content
                }
                .background(theme.bg)
                .environmentObject(themeStore)
                .environmentObject(model)
                .environmentObject(SessionStore(screenshot: ()))
                .environmentObject(HealthKitStepsStore())
                .environment(\.ffTheme, theme)
                .environment(\.colorScheme, theme.colorScheme)
                .environment(\.ffStaticRender, true)
        )
    }

    private static func frame<Content: View>(
        _ content: Content,
        tab: FFTab,
        themeStore: ThemeStore,
        model: AppModel
    ) -> AnyView {
        let theme = themeStore.theme
        let session = SessionStore(screenshot: ())
        return AnyView(
            VStack(spacing: 0) {
                VersionBanner()
                    .fixedSize(horizontal: false, vertical: true)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipped()
                FFTabBar(tab: .constant(tab))
            }
            .background(theme.bg)
            .environmentObject(themeStore)
            .environmentObject(model)
            .environmentObject(session)
            .environmentObject(HealthKitStepsStore())
            .environmentObject(FeedStore())
            .environment(\.ffTheme, theme)
            .environment(\.colorScheme, theme.colorScheme)
            .environment(\.ffStaticRender, true)
        )
    }

    private static func write(
        _ view: AnyView,
        name: String,
        size: CGSize,
        scale: CGFloat = 2,
        jpeg: Bool = false,
        to folder: URL
    ) {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = scale
        guard let image = renderer.uiImage,
              let data = jpeg ? image.jpegData(compressionQuality: 1) : image.pngData() else { return }
        let fileExtension = jpeg ? "jpg" : "png"
        try? data.write(to: folder.appendingPathComponent("\(name).\(fileExtension)"))
    }

    private static func write(
        _ view: AnyView,
        name: String,
        height: CGFloat,
        to folder: URL,
        scale: CGFloat = 2
    ) {
        write(
            view,
            name: name,
            size: CGSize(width: canvas.width, height: height),
            scale: scale,
            to: folder
        )
    }
}
