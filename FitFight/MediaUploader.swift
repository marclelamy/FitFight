import CryptoKit
import UIKit

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

    enum UploadError: LocalizedError {
        case invalidImage
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .invalidImage: return String(localized: "That photo could not be read.")
            case .tooLarge: return String(localized: "Choose a smaller photo.")
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
        let rendered = UIGraphicsImageRenderer(size: size).image { _ in
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
            width: Int(size.width),
            height: Int(size.height),
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
        let token = try await session.freshAccessToken()
        let issued = try await api.createMediaUpload(
            purpose: purpose,
            filename: prepared.filename,
            contentType: prepared.contentType,
            byteSize: prepared.byteSize,
            width: prepared.width,
            height: prepared.height,
            sha256: prepared.sha256,
            accessToken: token
        )
        var request = URLRequest(url: issued.upload.url)
        request.httpMethod = "PUT"
        request.setValue(prepared.contentType, forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.upload(for: request, from: prepared.data)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            throw FitFightAPIError.http(status: status, code: "storage_error", message: nil)
        }
        let committed = try await api.commitMedia(id: issued.media.id, accessToken: try await session.freshAccessToken())
        return committed.media
    }
}
