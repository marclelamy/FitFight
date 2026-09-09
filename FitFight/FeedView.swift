import PhotosUI
import SwiftUI

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

    func create(session: SessionStore, fightID: UUID, body: String, images: [UIImage]) async -> Bool {
        listLoad += 1
        isSaving = true
        defer { isSaving = false }
        do {
            var mediaIDs: [UUID] = []
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

struct FeedView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var feed: FeedStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender

    var body: some View {
        FFScreen {
            FFScreenTitle(
                title: String(localized: "Feed"),
                subtitle: String(localized: "Photos and notes from the fights you’re in.")
            )
            if let error = feed.error, !error.isEmpty {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
            }
            if feed.posts.isEmpty && !feed.isLoading {
                FFCard {
                    Text("Nothing here yet. Open a fight and post a photo or a short note.")
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
        .refreshable {
            await feed.load(session: session)
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
                Text("Be the first to post a photo or a note.")
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

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var feed: FeedStore
    @Environment(\.ffTheme) private var theme

    @State private var bodyText = ""
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []

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
                HStack {
                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: max(0, 4 - images.count),
                        matching: .images
                    ) {
                        Label(String(localized: "Photo"), systemImage: "photo")
                            .ffType(.label)
                            .foregroundStyle(theme.mossText)
                    }
                    .buttonStyle(FFHapticPlainStyle())
                    .disabled(images.count >= 4)
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
        .onChange(of: pickerItems) { _, items in
            Task { await load(items) }
        }
    }

    private var canPost: Bool {
        !feed.isSaving && (!bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty)
    }

    private func load(_ items: [PhotosPickerItem]) async {
        var loaded: [UIImage] = images
        for item in items {
            if loaded.count >= 4 { break }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { continue }
            loaded.append(image)
        }
        images = loaded
        pickerItems = []
    }

    private func submit() async {
        let note = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if await feed.create(session: session, fightID: fightID, body: note, images: images) {
            bodyText = ""
            images = []
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
                if showFight {
                    Text(post.createdDate, style: .relative)
                        .ffType(.micro)
                        .foregroundStyle(theme.textFaint)
                }
            }
        }
    }
}
