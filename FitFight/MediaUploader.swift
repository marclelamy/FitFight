import AVFoundation
import CryptoKit
import CoreTransferable
import UniformTypeIdentifiers
import UIKit

struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: false)
                .appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: received.file, to: dest)
            return Self(url: dest)
        }
    }
}

enum MediaUploader {
    struct PreparedPhoto {
        let data: Data
        let filename: String
        let contentType: String
        let byteSize: Int
        let width: Int
        let height: Int
        let sha256: String
    }

    struct PreparedVideo {
        let data: Data
        let filename: String
        let contentType: String
        let byteSize: Int
        let width: Int
        let height: Int
        let durationMs: Int
        let sha256: String
    }

    enum UploadError: LocalizedError {
        case invalidImage
        case invalidVideo
        case tooLarge
        case tooLong

        var errorDescription: String? {
            switch self {
            case .invalidImage: return String(localized: "That photo could not be read.")
            case .invalidVideo: return String(localized: "That video could not be read.")
            case .tooLarge: return String(localized: "Choose a smaller photo or video.")
            case .tooLong: return String(localized: "Choose a video under 3 minutes.")
            }
        }
    }

    static func prepare(_ image: UIImage, filename: String = "photo.jpg") throws -> PreparedPhoto {
        let maxDimension: CGFloat = 2048
        let longest = max(image.size.width, image.size.height)
        let scale = longest > 0 ? min(1, maxDimension / longest) : 1
        let size = CGSize(
            width: max(1, floor(image.size.width * scale)),
            height: max(1, floor(image.size.height * scale))
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = rendered.jpegData(compressionQuality: 0.82) else {
            throw UploadError.invalidImage
        }
        if data.count > 8_388_608 {
            throw UploadError.tooLarge
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return PreparedPhoto(
            data: data,
            filename: filename,
            contentType: "image/jpeg",
            byteSize: data.count,
            width: Int(rendered.size.width * rendered.scale),
            height: Int(rendered.size.height * rendered.scale),
            sha256: digest
        )
    }

    static func prepareVideo(url: URL) async throws -> PreparedVideo {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = values.fileSize ?? 0
        if fileSize < 1 || fileSize > 52_428_800 {
            throw UploadError.tooLarge
        }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else {
            throw UploadError.invalidVideo
        }
        let durationMs = Int((seconds * 1000).rounded())
        if durationMs > 180_000 {
            throw UploadError.tooLong
        }
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw UploadError.invalidVideo
        }
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let rendered = natural.applying(transform)
        let width = max(1, Int(abs(rendered.width).rounded()))
        let height = max(1, Int(abs(rendered.height).rounded()))
        if width > 8192 || height > 8192 {
            throw UploadError.tooLarge
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        if data.count > 52_428_800 {
            throw UploadError.tooLarge
        }
        let ext = url.pathExtension.lowercased()
        let isQuickTime = ext == "mov"
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return PreparedVideo(
            data: data,
            filename: isQuickTime ? "video.mov" : "video.mp4",
            contentType: isQuickTime ? "video/quicktime" : "video/mp4",
            byteSize: data.count,
            width: width,
            height: height,
            durationMs: durationMs,
            sha256: digest
        )
    }

    static func upload(
        _ image: UIImage,
        purpose: String,
        session: SessionStore,
        api: FitFightAPI = FitFightAPI()
    ) async throws -> FitFightMedia {
        let prepared = try prepare(image)
        return try await put(
            data: prepared.data,
            purpose: purpose,
            kind: "photo",
            filename: prepared.filename,
            contentType: prepared.contentType,
            byteSize: prepared.byteSize,
            width: prepared.width,
            height: prepared.height,
            durationMs: nil,
            sha256: prepared.sha256,
            session: session,
            api: api
        )
    }

    static func uploadVideo(
        _ url: URL,
        purpose: String,
        session: SessionStore,
        api: FitFightAPI = FitFightAPI()
    ) async throws -> FitFightMedia {
        let prepared = try await prepareVideo(url: url)
        return try await put(
            data: prepared.data,
            purpose: purpose,
            kind: "video",
            filename: prepared.filename,
            contentType: prepared.contentType,
            byteSize: prepared.byteSize,
            width: prepared.width,
            height: prepared.height,
            durationMs: prepared.durationMs,
            sha256: prepared.sha256,
            session: session,
            api: api
        )
    }

    private static func put(
        data: Data,
        purpose: String,
        kind: String,
        filename: String,
        contentType: String,
        byteSize: Int,
        width: Int,
        height: Int,
        durationMs: Int?,
        sha256: String,
        session: SessionStore,
        api: FitFightAPI
    ) async throws -> FitFightMedia {
        let token = try await session.freshAccessToken()
        let issued = try await api.createMediaUpload(
            purpose: purpose,
            kind: kind,
            filename: filename,
            contentType: contentType,
            byteSize: byteSize,
            width: width,
            height: height,
            durationMs: durationMs,
            sha256: sha256,
            accessToken: token
        )
        var request = URLRequest(url: issued.upload.url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(issued.upload.token)", forHTTPHeaderField: "Authorization")
        request.setValue("false", forHTTPHeaderField: "x-upsert")
        let (_, response) = try await URLSession.shared.upload(for: request, from: data)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            throw FitFightAPIError.http(status: status, code: "storage_error", message: nil)
        }
        let committed = try await api.commitMedia(id: issued.media.id, accessToken: try await session.freshAccessToken())
        return committed.media
    }
}
