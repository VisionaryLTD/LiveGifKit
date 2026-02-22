import Dependencies
import Foundation

public protocol GIFToolKit: Sendable {
    func generateGIF(_ request: GIFGenerationURLRequest) -> AsyncThrowingStream<GIFGenerationEvent, Error>
    func removeBackground(_ request: GIFBackgroundRemovalURLRequest) -> AsyncThrowingStream<GIFBackgroundRemovalEvent, Error>
    func save(_ request: GIFSaveURLRequest) async throws -> GIFSaveResult
    func fetchRecommendedAssets(_ request: GIFRecommendationURLRequest) async throws -> [GIFRecommendedAsset]
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
    func generateGIF(_ request: GIFGenerationURLRequest) -> AsyncThrowingStream<GIFGenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.preparingFrames(completed: 0, total: nil))
                    let count: Int
                    let pixelSize: CGSize
                    switch request.source {
                    case .imageFiles(let urls, _):
                        count = urls.count
                        pixelSize = GIFImage.gifImage(contentsOf: urls.first ?? URL(fileURLWithPath: "/dev/null"))?.size ?? .zero
                    case .videoFile:
                        count = 1
                        pixelSize = .zero
                    case .livePhotoVideoFile:
                        count = 1
                        pixelSize = .zero
                    }

                    let outputURL = request.outputGIFURL ?? URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "livegifkit-preview.gif")
                    if !FileManager.default.fileExists(atPath: outputURL.path) {
                        try Data().write(to: outputURL)
                    }
                    continuation.yield(.encoding(completed: count, total: count))
                    continuation.yield(
                        .completed(
                            GIFGenerationURLResult(
                                gifURL: outputURL,
                                frameCount: count,
                                pixelSize: pixelSize,
                                duration: 0
                            )
                        )
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func removeBackground(_ request: GIFBackgroundRemovalURLRequest) -> AsyncThrowingStream<GIFBackgroundRemovalEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.processing)
                let outputURL = request.outputImageURL ?? request.inputImageURL
                continuation.yield(.completed(.init(imageURL: outputURL, pixelSize: .zero)))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func save(_ request: GIFSaveURLRequest) async throws -> GIFSaveResult {
        GIFSaveResult(localIdentifier: nil)
    }

    func fetchRecommendedAssets(_ request: GIFRecommendationURLRequest) async throws -> [GIFRecommendedAsset] {
        []
    }

    func preheat() async throws {}

    func cleanup(_ scope: GIFCleanupScope) async throws {}
}

internal struct GIFToolKitUnimplemented: GIFToolKit {
    func generateGIF(_ request: GIFGenerationURLRequest) -> AsyncThrowingStream<GIFGenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: GifError.unimplemented)
        }
    }

    func removeBackground(_ request: GIFBackgroundRemovalURLRequest) -> AsyncThrowingStream<GIFBackgroundRemovalEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: GifError.unimplemented)
        }
    }

    func save(_ request: GIFSaveURLRequest) async throws -> GIFSaveResult {
        throw GifError.unimplemented
    }

    func fetchRecommendedAssets(_ request: GIFRecommendationURLRequest) async throws -> [GIFRecommendedAsset] {
        throw GifError.unimplemented
    }

    func preheat() async throws {
        throw GifError.unimplemented
    }

    func cleanup(_ scope: GIFCleanupScope) async throws {
        throw GifError.unimplemented
    }
}
