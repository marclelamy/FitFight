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
    let fightId: UUID
    let fightName: String
    let body: String
    let createdAt: String
    let author: Author
    let media: [FitFightMedia]
    let mine: Bool

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

    enum CodingKeys: String, CodingKey {
        case id, body, author, media, mine
        case fightId = "fight_id"
        case fightName = "fight_name"
        case createdAt = "created_at"
    }
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
