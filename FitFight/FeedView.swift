import AVKit
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
    private var lastFightID: UUID?

    func load(session: SessionStore, fightID: UUID? = nil, more: Bool = false) async {
        lastFightID = fightID
        listLoad += 1
        let load = listLoad
        isLoading = true
        defer {
            if load == listLoad { isLoading = false }
        }
        do {
            let token = try await session.freshAccessToken()
            let result: FitFightFightPostList
            if let fightID {
                result = try await api.fightPosts(fightID: fightID, cursor: more ? nextCursor : nil, accessToken: token)
            } else {
                result = try await api.feed(scope: "all", cursor: more ? nextCursor : nil, accessToken: token)
            }
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
        destinations: [FeedPostDestination],
        taggedUserIDs: [UUID],
        body: String,
        images: [UIImage],
        videoURL: URL? = nil
    ) async -> Bool {
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
            _ = try await api.createFeedPosts(
                body: body,
                mediaIDs: mediaIDs,
                destinations: destinations,
                taggedUserIDs: taggedUserIDs,
                accessToken: token
            )
            error = nil
            await load(session: session, fightID: lastFightID)
            return true
        } catch {
            if Task.isCancelled || error is CancellationError { return false }
            self.error = error.localizedDescription
            return false
        }
    }

    func replace(_ post: FitFightFightPost) {
        if let index = posts.firstIndex(where: { $0.id == post.id }) {
            posts[index] = post
        }
    }

    func delete(session: SessionStore, post: FitFightFightPost) async {
        do {
            let token = try await session.freshAccessToken()
            try await api.deleteFightPost(postID: post.id, accessToken: token)
            posts.removeAll { $0.id == post.id }
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            self.error = error.localizedDescription
        }
    }

    func report(session: SessionStore, post: FitFightFightPost) async {
        do {
            let token = try await session.freshAccessToken()
            try await api.reportFightPost(postID: post.id, reason: "other", accessToken: token)
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

    func react(session: SessionStore, post: FitFightFightPost, emoji: String) async {
        do {
            let token = try await session.freshAccessToken()
            let result = try await api.reactToFightPost(postID: post.id, emoji: emoji, accessToken: token)
            replace(post.updating(reactions: result.reactions))
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
    @State private var composing = false

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
            if feed.posts.isEmpty && feed.isLoading {
                FFLoadingBlock()
            } else if feed.posts.isEmpty && !feed.isLoading {
                FFCard {
                    Text(String(localized: "Nothing here yet. Tap + to post."))
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(feed.posts) { post in
                FightPostCard(post: post) {
                    if let fightID = post.fightId {
                        model.openFightFromFeed(id: fightID.uuidString)
                    }
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
        .sheet(isPresented: $composing) {
            FeedComposeSheet()
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
        Button {
            composing = true
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
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var feed: FeedStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var destinations: Set<FeedPostDestination> = []
    @State private var tagged: Set<UUID> = []
    @State private var people: [FitFightFeedPerson] = []
    @State private var appliedDefault = false

    private var fights: [Fight] {
        postableFights(model.fights)
    }

    private var allFightDestinations: Set<FeedPostDestination> {
        Set(fights.compactMap { fight in
            UUID(uuidString: fight.id).map { FeedPostDestination.fight($0) }
        })
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
                FightPostComposer(
                    destinations: Array(destinations),
                    taggedUserIDs: Array(tagged),
                    tags: AnyView(FeedTagPicker(people: people, tagged: $tagged)),
                    destination: AnyView(FeedDestinationMenu(fights: fights, destinations: $destinations))
                ) {
                    dismiss()
                }
            }
            if let error = feed.error, !error.isEmpty {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
            }
        }
        .onAppear { applyDefaultDestinations() }
        .onChange(of: fights.map(\.id).joined(separator: ",")) { _, _ in
            applyDefaultDestinations()
        }
        .task(id: destinationKey) {
            await loadPeople()
        }
    }

    private var destinationKey: String {
        destinations.map { destination in
            destination.type + (destination.fightId?.uuidString ?? "")
        }.sorted().joined(separator: ",")
    }

    private func applyDefaultDestinations() {
        let all = allFightDestinations
        guard !appliedDefault, !all.isEmpty else { return }
        destinations = all
        appliedDefault = true
    }

    private func loadPeople() async {
        do {
            let token = try await session.freshAccessToken()
            let fightIDs = destinations.compactMap(\.fightId)
            let result = try await FitFightAPI().feedPeople(
                main: false,
                fightIDs: fightIDs,
                accessToken: token
            )
            people = result.people
            tagged = tagged.intersection(Set(people.map(\.userId)))
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            feed.error = error.localizedDescription
        }
    }
}

struct FeedDestinationMenu: View {
    let fights: [Fight]
    @Binding var destinations: Set<FeedPostDestination>
    @Environment(\.ffTheme) private var theme

    private var allFightDestinations: Set<FeedPostDestination> {
        Set(fights.compactMap { fight in
            UUID(uuidString: fight.id).map { FeedPostDestination.fight($0) }
        })
    }

    private var everythingSelected: Bool {
        !allFightDestinations.isEmpty && destinations == allFightDestinations
    }

    private var label: String {
        if everythingSelected {
            return String(localized: "Everything")
        }
        if destinations.count == 1, let id = destinations.first?.fightId {
            return fights.first(where: { $0.id.caseInsensitiveCompare(id.uuidString) == .orderedSame })?.listTitle
                ?? String(localized: "Post to")
        }
        if destinations.isEmpty {
            return String(localized: "Post to")
        }
        return String(localized: "\(destinations.count) fights")
    }

    var body: some View {
        Menu {
            Button {
                destinations = allFightDestinations
            } label: {
                destinationLabel(String(localized: "Everything"), selected: everythingSelected)
            }
            ForEach(fights) { fight in
                if let id = UUID(uuidString: fight.id) {
                    Button {
                        toggle(.fight(id))
                    } label: {
                        destinationLabel(fight.listTitle, selected: destinations.contains(.fight(id)))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .ffType(.label)
                    .foregroundStyle(theme.mossText)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.mossText)
            }
        }
        .menuOrder(.fixed)
        .buttonStyle(FFHapticPlainStyle())
        .accessibilityLabel(String(localized: "Post to"))
        .accessibilityValue(label)
    }

    @ViewBuilder
    private func destinationLabel(_ title: String, selected: Bool) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private func toggle(_ destination: FeedPostDestination) {
        if destinations.contains(destination) {
            destinations.remove(destination)
        } else {
            destinations.insert(destination)
        }
    }
}

struct FeedTagPicker: View {
    let people: [FitFightFeedPerson]
    @Binding var tagged: Set<UUID>
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Tag people"))
                .ffType(.micro)
                .foregroundStyle(theme.textFaint)
            Text(String(localized: "A tag never adds someone to a fight. If they are not in a selected fight, they will not see that copy."))
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if people.isEmpty {
                Text(String(localized: "Nobody from these destinations can be tagged yet."))
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
            } else {
                ForEach(people) { person in
                    Button {
                        if tagged.contains(person.userId) {
                            tagged.remove(person.userId)
                        } else {
                            tagged.insert(person.userId)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            FFAvatar(
                                monogram: String(person.handle.prefix(2)).uppercased(),
                                size: 32,
                                photoURL: person.avatar?.url
                            )
                            Text(person.atHandle)
                                .ffType(.rowTitle)
                                .foregroundStyle(theme.text)
                            Spacer(minLength: 8)
                            Image(systemName: tagged.contains(person.userId) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(tagged.contains(person.userId) ? theme.mossText : theme.textFaint)
                        }
                    }
                    .buttonStyle(FFHapticPlainStyle())
                }
            }
        }
    }
}

struct FightPostsSection: View {
    let fightID: UUID

    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @StateObject private var fightFeed = FeedStore()
    @State private var tagged: Set<UUID> = []
    @State private var people: [FitFightFeedPerson] = []

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.cardGap) {
            FightPostComposer(
                destinations: [.fight(fightID)],
                taggedUserIDs: Array(tagged),
                tags: AnyView(FeedTagPicker(people: people, tagged: $tagged))
            )
            if let error = fightFeed.error, !error.isEmpty {
                Text(error)
                    .ffType(.caption)
                    .foregroundStyle(theme.emberText)
            }
            if fightFeed.posts.isEmpty && !fightFeed.isLoading {
                Text(String(localized: "Be the first to post."))
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            ForEach(fightFeed.posts) { post in
                FightPostCard(post: post, onOpen: nil)
            }
        }
        .environmentObject(fightFeed)
        .task {
            await fightFeed.load(session: session, fightID: fightID)
        }
        .task {
            await loadPeople()
        }
    }

    private func loadPeople() async {
        do {
            let token = try await session.freshAccessToken()
            let result = try await FitFightAPI().feedPeople(
                main: false,
                fightIDs: [fightID],
                accessToken: token
            )
            people = result.people
            tagged = tagged.intersection(Set(people.map(\.userId)))
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            fightFeed.error = error.localizedDescription
        }
    }
}

struct FightPostComposer: View {
    let destinations: [FeedPostDestination]
    var taggedUserIDs: [UUID] = []
    var tags: AnyView? = nil
    var destination: AnyView? = nil
    var onPosted: (() -> Void)? = nil

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var feed: FeedStore
    @Environment(\.ffTheme) private var theme

    @State private var bodyText = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var videoItem: PhotosPickerItem?
    @State private var images: [UIImage] = []
    @State private var videoURL: URL?

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
                if let tags {
                    tags
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
                HStack(alignment: .center, spacing: 10) {
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
                    PhotosPicker(selection: $videoItem, matching: .videos) {
                        Label(String(localized: "Video"), systemImage: "video")
                            .ffType(.label)
                            .foregroundStyle(theme.mossText)
                    }
                    .buttonStyle(FFHapticPlainStyle())
                    .disabled(videoURL != nil || !images.isEmpty)
                    if let destination {
                        destination
                    }
                    Spacer(minLength: 8)
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
        return !feed.isSaving && !destinations.isEmpty && (!note.isEmpty || !images.isEmpty || videoURL != nil)
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
        if await feed.create(
            session: session,
            destinations: destinations,
            taggedUserIDs: taggedUserIDs,
            body: note,
            images: images,
            videoURL: videoURL
        ) {
            bodyText = ""
            images = []
            clearVideo()
            onPosted?()
        }
    }
}

struct FightPostCard: View {
    let post: FitFightFightPost
    var onOpen: (() -> Void)?

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var feed: FeedStore
    @Environment(\.ffTheme) private var theme

    private var destinationTitle: String {
        if post.isMain {
            return String(localized: "Main")
        }
        if !post.fightName.isEmpty {
            return post.fightName
        }
        return String(localized: "Fight")
    }

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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: post.author.atHandle)
                                .ffType(.rowTitle)
                                .foregroundStyle(theme.text)
                            HStack(spacing: 8) {
                                FFPill(destinationTitle, style: .neutral)
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
                if !post.tags.isEmpty {
                    Text(post.tags.map { "@\($0.handle)" }.joined(separator: " "))
                        .ffType(.caption)
                        .foregroundStyle(theme.mossText)
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
                FightPostEngagement(post: post)
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
