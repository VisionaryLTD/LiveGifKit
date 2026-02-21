import Dependencies
import Foundation

public protocol GIFToolKit: Sendable {
    func generateGIF(_ request: GIFGenerationRequest) async throws -> GIFGenerationResult
    func removeBackground(from image: GIFImage) async throws -> GIFImage
    func save(_ request: GIFSaveRequest) async throws -> GIFSaveResult
    func fetchRecommendedImages(_ request: GIFRecommendationRequest) async throws -> [GIFImage]
    func preheat() async throws
    func cleanup(_ scope: GIFCleanupScope) async throws
}

private enum GIFToolKitKey: DependencyKey {
    static let liveValue: any GIFToolKit = GIFToolKitImpl()
    static let previewValue: any GIFToolKit = GIFToolKitPreview()
    static let testValue: any GIFToolKit = GIFToolKitUnimplemented()
}

public extension DependencyValues {
    var gifToolKit: any GIFToolKit {
        get { self[GIFToolKitKey.self] }
        set { self[GIFToolKitKey.self] = newValue }
    }
}

internal struct GIFToolKitPreview: GIFToolKit {
    func generateGIF(_ request: GIFGenerationRequest) async throws -> GIFGenerationResult {
        switch request.source {
        case .images(let images, _):
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "livegifkit-preview.gif")
            if !FileManager.default.fileExists(atPath: tempURL.path) {
                try Data().write(to: tempURL)
            }
            return GIFGenerationResult(fileURL: tempURL, frames: images)
        default:
            throw GifError.unsupportedSource
        }
    }

    func removeBackground(from image: GIFImage) async throws -> GIFImage {
        image
    }

    func save(_ request: GIFSaveRequest) async throws -> GIFSaveResult {
        GIFSaveResult(localIdentifier: nil)
    }

    func fetchRecommendedImages(_ request: GIFRecommendationRequest) async throws -> [GIFImage] {
        []
    }

    func preheat() async throws {}

    func cleanup(_ scope: GIFCleanupScope) async throws {}
}

internal struct GIFToolKitUnimplemented: GIFToolKit {
    func generateGIF(_ request: GIFGenerationRequest) async throws -> GIFGenerationResult {
        throw GifError.unimplemented
    }

    func removeBackground(from image: GIFImage) async throws -> GIFImage {
        throw GifError.unimplemented
    }

    func save(_ request: GIFSaveRequest) async throws -> GIFSaveResult {
        throw GifError.unimplemented
    }

    func fetchRecommendedImages(_ request: GIFRecommendationRequest) async throws -> [GIFImage] {
        throw GifError.unimplemented
    }

    func preheat() async throws {
        throw GifError.unimplemented
    }

    func cleanup(_ scope: GIFCleanupScope) async throws {
        throw GifError.unimplemented
    }
}

