import AVKit
import PhotosUI
import SwiftUI

enum FeedComposeKind: String, Identifiable {
    case photo
    case video
    case text

    var id: String { rawValue }
}

@MainActor
final class FeedStore: ObservableObject {
    @Published var posts: [FitFightFightPost] = []
    @Published var nextCursor: String?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var error: String?

    private let api = FitFightAPI()
    private var listLoad = 0

    func load(session: SessionStore, fightID: UUID? = nil, more: Bool = false) async {
        listLoad += 1
        let load = listLoad
        isLoading = true
        defer {
            if load == listLoad { isLoading = false }
        }
        do {
            let token = try await session.freshAccessToken()
            let result = fightID == nil
                ? try await api.feed(cursor: more ? nextCursor : nil, accessToken: token)
                : try await api.fightPosts(fightID: fightID!, cursor: more ? nextCursor : nil, accessToken: token)
            guard load == listLoad else { return }
            posts = more ? posts + result.posts.filter { post in !posts.contains(where: { $0.id == post.id }) } : result.posts
            nextCursor = result.nextCursor
            error = nil
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            guard load == listLoad else { return }
            self.error = error.localizedDescription
        }
    }

    func create(
        session: SessionStore,
        fightID: UUID,
        body: String,
        images: [UIImage],
        videoURL: URL? = nil
    ) async -> Bool {
        listLoad += 1
        isSaving = true
        defer { isSaving = false }
        do {
            var mediaIDs: [UUID] = []
            if let videoURL {
                mediaIDs.append(try await MediaUploader.uploadVideo(videoURL, purpose: "fight_post", session: session, api: api).id)
            }
            for image in images {
                mediaIDs.append(try await MediaUploader.upload(image, purpose: "fight_post", session: session, api: api).id)
            }
            let token = try await session.freshAccessToken()
            let created = try await api.createFightPost(
                fightID: fightID,
                body: body,
                mediaIDs: mediaIDs,
                accessToken: token
            )
            posts.insert(created.post, at: 0)
            error = nil
            return true
        } catch {
            if Task.isCancelled || error is CancellationError { return false }
            self.error = error.localizedDescription
            return false
        }
    }

    func delete(session: SessionStore, post: FitFightFightPost) async {
        do {
            let token = try await session.freshAccessToken()
            try await api.deleteFightPost(fightID: post.fightId, postID: post.id, accessToken: token)
            posts.removeAll { $0.id == post.id }
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            self.error = error.localizedDescription
        }
    }

    func report(session: SessionStore, post: FitFightFightPost) async {
        do {
            let token = try await session.freshAccessToken()
            try await api.reportFightPost(fightID: post.fightId, postID: post.id, reason: "other", accessToken: token)
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            self.error = error.localizedDescription
        }
    }

    func hide(session: SessionStore, authorID: UUID) async {
        do {
            let token = try await session.freshAccessToken()
            try await api.blockFeedAuthor(userID: authorID, accessToken: token)
            posts.removeAll { $0.author.userId == authorID }
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            self.error = error.localizedDescription
        }
    }
}

private func postableFights(_ fights: [Fight]) -> [Fight] {
    var seen = Set<String>()
    return fights
        .filter { fight in
            UUID(uuidString: fight.id) != nil
                && fight.status != .invited
                && !fight.pendingJoin
        }
        .sorted { lhs, rhs in
            if lhs.status != rhs.status {
                return lhs.status == .live && rhs.status != .live
            }
            return lhs.listTitle.localizedCaseInsensitiveCompare(rhs.listTitle) == .orderedAscending
        }
        .filter { fight in
            seen.insert(fight.seriesId ?? fight.id).inserted
        }
}

struct FeedView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @EnvironmentObject private var feed: FeedStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender
    @State private var composeKind: FeedComposeKind?

    var body: some View {
        FFScreen(refresh: feedRefresh) {
            FFScreenTitle(
                title: String(localized: "Feed"),
                subtitle: String(localized: "Photos, videos, and notes from the fights you’re in."),
                trailing: AnyView(composeButton)
            )
            if let error = feed.error, !error.isEmpty {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
            }
            if feed.posts.isEmpty && !feed.isLoading {
                FFCard {
                    Text(String(localized: "Nothing here yet. Tap + to post a photo, video, or note."))
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(feed.posts) { post in
                FightPostCard(post: post, showFight: true) {
                    model.openFightFromFeed(id: post.fightId.uuidString)
                }
            }
            if feed.nextCursor != nil {
                FFButton(title: String(localized: "More"), kind: .ghost, fullWidth: true) {
                    Task { await feed.load(session: session, more: true) }
                }
                .disabled(feed.isLoading)
            }
        }
        .task {
            guard !staticRender else { return }
            await feed.load(session: session)
        }
        .sheet(item: $composeKind) { kind in
            FeedComposeSheet(kind: kind)
                .environmentObject(model)
                .environmentObject(session)
                .environmentObject(feed)
                .fitFightTheme(theme)
                .presentationBackground(theme.bg)
        }
    }

    private var feedRefresh: FFRefreshConfig {
        FFRefreshConfig(
            isRefreshing: model.isRefreshingFights,
            message: model.refreshStatusText,
            action: {
                await model.refreshFights(session: session, steps: steps, trigger: .manual)
                await feed.load(session: session)
            }
        )
    }

    private var composeButton: some View {
        Menu {
            Button {
                composeKind = .photo
            } label: {
                Label(String(localized: "Photo"), systemImage: "photo")
            }
            Button {
                composeKind = .video
            } label: {
                Label(String(localized: "Video"), systemImage: "video")
            }
            Button {
                composeKind = .text
            } label: {
                Label(String(localized: "Text"), systemImage: "text.alignleft")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(theme.mossOn)
                .frame(width: 36, height: 36)
                .background(theme.mossFill, in: Circle())
        }
        .buttonStyle(FFHapticPlainStyle())
        .accessibilityLabel(String(localized: "New post"))
    }
}

struct FeedComposeSheet: View {
    let kind: FeedComposeKind

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var feed: FeedStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var fightID: UUID?

    private var fights: [Fight] {
        postableFights(model.fights)
    }

    private var selected: Fight? {
        fights.first { fight in
            guard let fightID else { return false }
            return fight.id.caseInsensitiveCompare(fightID.uuidString) == .orderedSame
        }
    }

    var body: some View {
        FFScreen(top: AnyView(VersionBanner()), clearance: false) {
            HStack {
                Text(String(localized: "New post"))
                    .ffType(.title)
                    .foregroundStyle(theme.text)
                Spacer()
                Button(String(localized: "Close")) { dismiss() }
                    .ffType(.label)
                    .foregroundStyle(theme.mossText)
            }
            if fights.isEmpty {
                FFCard {
                    Text(String(localized: "Join a fight first, then post from here."))
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                fightPicker
                if let fightID {
                    FightPostComposer(fightID: fightID, kind: kind) {
                        dismiss()
                    }
                }
            }
            if let error = feed.error, !error.isEmpty {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
            }
        }
        .onAppear {
            if fightID == nil {
                fightID = fights.first.flatMap { UUID(uuidString: $0.id) }
            }
        }
    }

    private var fightPicker: some View {
        FFCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Post to"))
                    .ffType(.micro)
                    .foregroundStyle(theme.textFaint)
                Menu {
                    ForEach(fights) { fight in
                        Button(fight.listTitle) {
                            fightID = UUID(uuidString: fight.id)
                        }
                    }
                } label: {
                    HStack {
                        Text(verbatim: selected?.listTitle ?? String(localized: "Choose a fight"))
                            .ffType(.rowTitle)
                            .foregroundStyle(theme.text)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(theme.textFaint)
                    }
                }
                .buttonStyle(FFHapticPlainStyle())
            }
        }
    }
}

struct FightPostsSection: View {
    let fightID: UUID

    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @StateObject private var fightFeed = FeedStore()

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.cardGap) {
            FightPostComposer(fightID: fightID)
            if let error = fightFeed.error, !error.isEmpty {
                Text(error)
                    .ffType(.caption)
                    .foregroundStyle(theme.emberText)
            }
            if fightFeed.posts.isEmpty && !fightFeed.isLoading {
                Text(String(localized: "Be the first to post a photo, video, or note."))
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            ForEach(fightFeed.posts) { post in
                FightPostCard(post: post, showFight: false, onOpen: nil)
            }
        }
        .environmentObject(fightFeed)
        .task {
            await fightFeed.load(session: session, fightID: fightID)
        }
    }
}

struct FightPostComposer: View {
    let fightID: UUID
    var kind: FeedComposeKind?
    var onPosted: (() -> Void)? = nil

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var feed: FeedStore
    @Environment(\.ffTheme) private var theme

    @State private var bodyText = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var videoItem: PhotosPickerItem?
    @State private var images: [UIImage] = []
    @State private var videoURL: URL?

    private var allowsPhotos: Bool { kind == nil || kind == .photo }
    private var allowsVideo: Bool { kind == nil || kind == .video }

    var body: some View {
        FFCard {
            VStack(alignment: .leading, spacing: 12) {
                TextField(String(localized: "Add a note or some proof…"), text: $bodyText, axis: .vertical)
                    .ffType(.body)
                    .foregroundStyle(theme.text)
                    .lineLimit(3...6)
                    .onChange(of: bodyText) { _, value in
                        if value.count > 500 {
                            bodyText = String(value.prefix(500))
                        }
                    }
                if !images.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
                                    .onTapGesture {
                                        images.remove(at: index)
                                    }
                            }
                        }
                    }
                }
                if videoURL != nil {
                    HStack(spacing: 8) {
                        Image(systemName: "video.fill")
                            .foregroundStyle(theme.mossText)
                        Text(String(localized: "Video"))
                            .ffType(.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                    .onTapGesture {
                        clearVideo()
                    }
                }
                HStack {
                    if allowsPhotos {
                        PhotosPicker(
                            selection: $photoItems,
                            maxSelectionCount: max(0, 4 - images.count),
                            matching: .images
                        ) {
                            Label(String(localized: "Photo"), systemImage: "photo")
                                .ffType(.label)
                                .foregroundStyle(theme.mossText)
                        }
                        .buttonStyle(FFHapticPlainStyle())
                        .disabled(images.count >= 4 || videoURL != nil)
                    }
                    if allowsVideo {
                        PhotosPicker(selection: $videoItem, matching: .videos) {
                            Label(String(localized: "Video"), systemImage: "video")
                                .ffType(.label)
                                .foregroundStyle(theme.mossText)
                        }
                        .buttonStyle(FFHapticPlainStyle())
                        .disabled(videoURL != nil || !images.isEmpty)
                    }
                    Spacer()
                    FFButton(
                        title: feed.isSaving ? String(localized: "Posting…") : String(localized: "Post"),
                        kind: .primary,
                        fullWidth: false
                    ) {
                        Task { await submit() }
                    }
                    .disabled(!canPost)
                }
            }
        }
        .onChange(of: photoItems) { _, items in
            Task { await loadPhotos(items) }
        }
        .onChange(of: videoItem) { _, item in
            Task { await loadVideo(item) }
        }
    }

    private var canPost: Bool {
        let note = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !feed.isSaving && (!note.isEmpty || !images.isEmpty || videoURL != nil)
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        clearVideo()
        var loaded: [UIImage] = images
        for item in items {
            if loaded.count >= 4 { break }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { continue }
            loaded.append(image)
        }
        images = loaded
        photoItems = []
    }

    private func loadVideo(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        images = []
        photoItems = []
        guard let picked = try? await item.loadTransferable(type: PickedVideo.self) else {
            feed.error = String(localized: "That video could not be read.")
            videoItem = nil
            return
        }
        videoURL = picked.url
        videoItem = nil
    }

    private func clearVideo() {
        if let videoURL, videoURL.path.hasPrefix(FileManager.default.temporaryDirectory.path) {
            try? FileManager.default.removeItem(at: videoURL)
        }
        videoURL = nil
        videoItem = nil
    }

    private func submit() async {
        let note = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if await feed.create(session: session, fightID: fightID, body: note, images: images, videoURL: videoURL) {
            bodyText = ""
            images = []
            clearVideo()
            onPosted?()
        }
    }
}

struct FightPostCard: View {
    let post: FitFightFightPost
    var showFight: Bool
    var onOpen: (() -> Void)?

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var feed: FeedStore
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    FFAvatar(
                        monogram: post.author.initials,
                        size: 38,
                        photoURL: post.author.avatar?.url
                    )
                    Button {
                        onOpen?()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: post.author.atHandle)
                                .ffType(.rowTitle)
                                .foregroundStyle(theme.text)
                            if showFight {
                                Text(verbatim: post.fightName)
                                    .ffType(.micro)
                                    .foregroundStyle(theme.mossText)
                            } else {
                                Text(post.createdDate, style: .relative)
                                    .ffType(.micro)
                                    .foregroundStyle(theme.textFaint)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(FFHapticPlainStyle())
                    .disabled(onOpen == nil)
                    Spacer(minLength: 0)
                    Menu {
                        if post.mine {
                            Button(String(localized: "Delete"), role: .destructive) {
                                Task { await feed.delete(session: session, post: post) }
                            }
                        } else {
                            Button(String(localized: "Report")) {
                                Task { await feed.report(session: session, post: post) }
                            }
                            Button(String(localized: "Hide this person"), role: .destructive) {
                                Task { await feed.hide(session: session, authorID: post.author.userId) }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(theme.textFaint)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(FFHapticPlainStyle())
                }
                if !post.body.isEmpty {
                    Text(post.body)
                        .ffType(.body)
                        .foregroundStyle(theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(post.media) { media in
                    if let url = media.url {
                        if media.kind == "video" {
                            FightPostVideo(url: url)
                        } else {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 220)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
                                default:
                                    RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous)
                                        .fill(theme.control)
                                        .frame(height: 220)
                                }
                            }
                        }
                    }
                }
                if showFight {
                    Text(post.createdDate, style: .relative)
                        .ffType(.micro)
                        .foregroundStyle(theme.textFaint)
                }
            }
        }
    }
}

private struct FightPostVideo: View {
    let url: URL
    @Environment(\.ffTheme) private var theme
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
            .onAppear {
                if player == nil {
                    player = AVPlayer(url: url)
                }
            }
            .onDisappear {
                player?.pause()
            }
    }
}
