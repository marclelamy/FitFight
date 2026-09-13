import Foundation

struct FitFightMedia: Codable, Equatable, Hashable, Identifiable {
    let id: UUID
    let kind: String
    let purpose: String
    let status: String
    let originalFilename: String
    let contentType: String
    let byteSize: Int
    let width: Int
    let height: Int
    let durationMs: Int?
    let sha256: String
    let url: URL?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, kind, purpose, status, url
        case originalFilename = "original_filename"
        case contentType = "content_type"
        case byteSize = "byte_size"
        case width, height, sha256
        case durationMs = "duration_ms"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(String.self, forKey: .kind)
        purpose = try container.decode(String.self, forKey: .purpose)
        status = try container.decode(String.self, forKey: .status)
        originalFilename = try container.decode(String.self, forKey: .originalFilename)
        contentType = try container.decode(String.self, forKey: .contentType)
        byteSize = try container.decode(Int.self, forKey: .byteSize)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs)
        sha256 = try container.decode(String.self, forKey: .sha256)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        if let parsed = try? container.decodeIfPresent(URL.self, forKey: .url) {
            url = parsed
        } else if let raw = try container.decodeIfPresent(String.self, forKey: .url), !raw.isEmpty {
            url = URL(string: raw)
        } else {
            url = nil
        }
    }
}

struct FitFightMediaUpload: Decodable {
    let media: FitFightMedia
    let upload: Upload

    struct Upload: Decodable {
        let url: URL
        let token: String
        let method: String
    }
}

struct FitFightMediaResponse: Decodable {
    let media: FitFightMedia
}

struct FitFightFightPost: Codable, Equatable, Hashable, Identifiable {
    let id: UUID
    let audience: String
    let fightId: UUID?
    let fightName: String
    let body: String
    let createdAt: String
    let author: Author
    let media: [FitFightMedia]
    let tags: [Tag]
    let reactions: [Reaction]
    let commentCount: Int
    let mine: Bool

    struct Tag: Codable, Equatable, Hashable {
        let userId: UUID
        let handle: String
        let displayName: String

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case handle
            case displayName = "display_name"
        }
    }

    struct Reaction: Codable, Equatable, Hashable {
        let emoji: String
        let count: Int
        let mine: Bool
    }

    struct Author: Codable, Equatable, Hashable {
        let userId: UUID
        let handle: String
        let displayName: String
        let avatar: FitFightMedia?

        var atHandle: String { "@\(handle)" }
        var initials: String {
            let parts = displayName.split(separator: " ").filter { !$0.isEmpty }
            if parts.count >= 2 {
                return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
            }
            if let first = parts.first, !first.isEmpty {
                return String(first.prefix(2)).uppercased()
            }
            return String(handle.prefix(2)).uppercased()
        }

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case handle
            case displayName = "display_name"
            case avatar
        }
    }

    var createdDate: Date {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: createdAt) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: createdAt) ?? .distantPast
    }

    var isMain: Bool { audience == "main" }

    func updating(
        reactions: [Reaction]? = nil,
        commentCount: Int? = nil
    ) -> FitFightFightPost {
        FitFightFightPost(
            id: id,
            audience: audience,
            fightId: fightId,
            fightName: fightName,
            body: body,
            createdAt: createdAt,
            author: author,
            media: media,
            tags: tags,
            reactions: reactions ?? self.reactions,
            commentCount: commentCount ?? self.commentCount,
            mine: mine
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, audience, body, author, media, tags, reactions, mine
        case fightId = "fight_id"
        case fightName = "fight_name"
        case createdAt = "created_at"
        case commentCount = "comment_count"
    }
}

struct FitFightFeedPerson: Codable, Equatable, Hashable, Identifiable {
    let userId: UUID
    let handle: String
    let displayName: String
    let avatar: FitFightMedia?

    var id: UUID { userId }
    var atHandle: String { "@\(handle)" }

    enum CodingKeys: String, CodingKey {
        case handle, avatar
        case userId = "user_id"
        case displayName = "display_name"
    }
}

struct FitFightFeedPeople: Decodable {
    let people: [FitFightFeedPerson]
}

struct FitFightFightPostComment: Codable, Equatable, Hashable, Identifiable {
    let id: UUID
    let postId: UUID
    let parentId: UUID?
    let body: String
    let createdAt: String
    let author: FitFightFightPost.Author
    let mine: Bool

    var createdDate: Date {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: createdAt) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: createdAt) ?? .distantPast
    }

    enum CodingKeys: String, CodingKey {
        case id, body, author, mine
        case postId = "post_id"
        case parentId = "parent_id"
        case createdAt = "created_at"
    }
}

struct FitFightFightPostCommentList: Decodable {
    let comments: [FitFightFightPostComment]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case comments
        case nextCursor = "next_cursor"
    }
}

struct FitFightFightPostCommentResponse: Decodable {
    let comment: FitFightFightPostComment
}

struct FitFightFightPostReactionList: Decodable {
    let reactions: [FitFightFightPost.Reaction]
}

struct FitFightFightPostList: Decodable {
    let posts: [FitFightFightPost]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case posts
        case nextCursor = "next_cursor"
    }
}

struct FitFightFightPostResponse: Decodable {
    let post: FitFightFightPost
}

struct FitFightFightPostBatch: Decodable {
    let posts: [FitFightFightPost]
}
