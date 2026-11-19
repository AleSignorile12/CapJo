import Photos
import UIKit

struct PhotoLibrarySaver {
    static func save(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoSaveError.permissionDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PhotoSaveError.couldNotSave)
                }
            }
        }
    }
}

enum PhotoSaveError: LocalizedError {
    case permissionDenied
    case couldNotSave

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Photo access was not allowed. The photo is still saved in your journal."
        case .couldNotSave: "The photo could not be added to Photos. It is still saved in your journal."
        }
    }
}
