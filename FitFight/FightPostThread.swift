import SwiftUI

struct FightPostEngagement: View {
    let post: FitFightFightPost

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var feed: FeedStore
    @Environment(\.ffTheme) private var theme

    @State private var comments: [FitFightFightPostComment] = []
    @State private var nextCursor: String?
    @State private var open = false
    @State private var replyTo: FitFightFightPostComment?
    @State private var draft = ""
    @State private var customEmoji = ""
    @State private var loading = false

    private let quickEmoji = ["🔥", "💪", "😂", "❤️", "👏", "😮"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            reactions
            Button {
                open.toggle()
                if open && comments.isEmpty {
                    Task { await loadComments() }
                }
            } label: {
                Text(
                    post.commentCount == 0
                        ? String(localized: "Comment")
                        : post.commentCount == 1
                            ? String(localized: "1 comment")
                            : String(localized: "\(post.commentCount) comments")
                )
                .ffType(.caption)
                .foregroundStyle(theme.mossText)
            }
            .buttonStyle(FFHapticPlainStyle())
            if open {
                commentThread(parentID: nil, depth: 0)
                if nextCursor != nil {
                    Button(String(localized: "More comments")) {
                        Task { await loadComments(more: true) }
                    }
                    .ffType(.caption)
                    .foregroundStyle(theme.mossText)
                    .buttonStyle(FFHapticPlainStyle())
                }
                if let replyTo {
                    HStack {
                        Text(
                            String(
                                localized: "feed.replying-to \(replyTo.author.handle)",
                                defaultValue: "Replying to @\(replyTo.author.handle)"
                            )
                        )
                            .ffType(.micro)
                            .foregroundStyle(theme.textSecondary)
                        Spacer()
                        Button(String(localized: "Cancel")) { self.replyTo = nil }
                            .ffType(.micro)
                            .foregroundStyle(theme.mossText)
                            .buttonStyle(FFHapticPlainStyle())
                    }
                }
                HStack {
                    TextField(String(localized: "Write a comment…"), text: $draft, axis: .vertical)
                        .ffType(.body)
                        .foregroundStyle(theme.text)
                        .lineLimit(1...4)
                    FFButton(
                        title: loading ? String(localized: "…") : String(localized: "Send"),
                        kind: .ghost,
                        fullWidth: false
                    ) {
                        Task { await sendComment() }
                    }
                    .disabled(loading || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var reactions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(post.reactions, id: \.emoji) { reaction in
                    Button {
                        Task { await feed.react(session: session, post: post, emoji: reaction.emoji) }
                    } label: {
                        Text("\(reaction.emoji) \(reaction.count)")
                            .ffType(.caption)
                            .foregroundStyle(reaction.mine ? theme.mossOn : theme.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(reaction.mine ? theme.mossFill : theme.control, in: Capsule())
                    }
                    .buttonStyle(FFHapticPlainStyle())
                }
                ForEach(quickEmoji.filter { emoji in !post.reactions.contains(where: { $0.emoji == emoji }) }, id: \.self) { emoji in
                    Button {
                        Task { await feed.react(session: session, post: post, emoji: emoji) }
                    } label: {
                        Text(emoji)
                            .ffType(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(theme.control, in: Capsule())
                    }
                    .buttonStyle(FFHapticPlainStyle())
                }
                TextField(String(localized: "☺︎"), text: $customEmoji)
                    .ffType(.caption)
                    .frame(width: 36)
                    .onChange(of: customEmoji) { _, value in
                        let emoji = firstEmoji(in: value)
                        customEmoji = ""
                        if let emoji {
                            Task { await feed.react(session: session, post: post, emoji: emoji) }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func commentThread(parentID: UUID?, depth: Int) -> some View {
        ForEach(comments.filter { $0.parentId == parentID }) { comment in
            VStack(alignment: .leading, spacing: 6) {
                commentRow(comment)
                commentThread(parentID: comment.id, depth: depth + 1)
            }
            .padding(.leading, CGFloat(min(depth, 4)) * 14)
        }
    }

    private func commentRow(_ comment: FitFightFightPostComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                FFAvatar(
                    monogram: comment.author.initials,
                    size: 26,
                    photoURL: comment.author.avatar?.url
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(comment.author.atHandle)
                        .ffType(.caption)
                        .foregroundStyle(theme.text)
                    Text(comment.body)
                        .ffType(.body)
                        .foregroundStyle(theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Text(comment.createdDate, style: .relative)
                            .ffType(.micro)
                            .foregroundStyle(theme.textFaint)
                        Button(String(localized: "Reply")) {
                            replyTo = comment
                        }
                        .ffType(.micro)
                        .foregroundStyle(theme.mossText)
                        .buttonStyle(FFHapticPlainStyle())
                    }
                }
                Spacer(minLength: 0)
                Menu {
                    if comment.mine {
                        Button(String(localized: "Delete"), role: .destructive) {
                            Task { await deleteComment(comment) }
                        }
                    } else {
                        Button(String(localized: "Report")) {
                            Task { await reportComment(comment) }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.textFaint)
                }
                .buttonStyle(FFHapticPlainStyle())
            }
        }
    }

    private func loadComments(more: Bool = false) async {
        loading = true
        defer { loading = false }
        do {
            let token = try await session.freshAccessToken()
            let result = try await FitFightAPI().fightPostComments(
                postID: post.id,
                cursor: more ? nextCursor : nil,
                accessToken: token
            )
            comments = more
                ? comments + result.comments.filter { comment in !comments.contains(where: { $0.id == comment.id }) }
                : result.comments
            nextCursor = result.nextCursor
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            feed.error = error.localizedDescription
        }
    }

    private func sendComment() async {
        let note = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return }
        loading = true
        defer { loading = false }
        do {
            let token = try await session.freshAccessToken()
            let created = try await FitFightAPI().createFightPostComment(
                postID: post.id,
                body: note,
                parentID: replyTo?.id,
                accessToken: token
            )
            comments.append(created.comment)
            draft = ""
            replyTo = nil
            feed.replace(post.updating(commentCount: post.commentCount + 1))
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            feed.error = error.localizedDescription
        }
    }

    private func deleteComment(_ comment: FitFightFightPostComment) async {
        do {
            let token = try await session.freshAccessToken()
            try await FitFightAPI().deleteFightPostComment(postID: post.id, commentID: comment.id, accessToken: token)
            comments.removeAll { $0.id == comment.id || $0.parentId == comment.id }
            feed.replace(post.updating(commentCount: max(0, post.commentCount - 1)))
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            feed.error = error.localizedDescription
        }
    }

    private func reportComment(_ comment: FitFightFightPostComment) async {
        do {
            let token = try await session.freshAccessToken()
            try await FitFightAPI().reportFightPostComment(postID: post.id, commentID: comment.id, accessToken: token)
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            feed.error = error.localizedDescription
        }
    }

    private func firstEmoji(in value: String) -> String? {
        guard let segment = value.precomposedStringWithCanonicalMapping.first else { return nil }
        let candidate = String(segment)
        return candidate.unicodeScalars.contains(where: { $0.properties.isEmoji }) ? candidate : nil
    }
}
