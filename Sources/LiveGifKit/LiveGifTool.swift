import Dependencies
import Foundation

@available(*, deprecated, message: "Use @Dependency(\\.gifToolKit) var gifToolKit instead.")
public final class LiveGifTool {
    @Dependency(\.gifToolKit) private var gifToolKit

    public init() {}

    @available(*, deprecated, message: "Use gifToolKit.generateGIF(_:)")
    public func createGif(parameter: GifToolParameter) async throws -> GifResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        let request = try parameter.toGIFGenerationRequest()
        let result = try await gifToolKit.generateGIF(request)
        var legacyResult = GifResult(
            url: result.fileURL,
            frames: result.frames,
            originFrames: result.originalFrames
        )
        #if DEBUG
        legacyResult.totalTime = CFAbsoluteTimeGetCurrent() - startTime
        #endif
        return legacyResult
    }

    @available(*, deprecated, message: "Use gifToolKit.save(_:)")
    public func save(method: Method) async throws {
        let request: GIFSaveRequest
        switch method {
        case .url(let url):
            request = GIFSaveRequest(payload: .fileURL(url))
        case .image(let image):
            request = GIFSaveRequest(payload: .image(image))
        }
        _ = try await gifToolKit.save(request)
    }

    @available(*, deprecated, message: "Use gifToolKit.removeBackground(from:)")
    @MainActor
    public func removeBackground(uiImage: GIFImage) async throws -> Data? {
        let image = try await gifToolKit.removeBackground(from: uiImage)
        return image.gifPNGData
    }

    @available(*, deprecated, message: "Use gifToolKit.preheat()")
    public func preheating() async throws {
        try await gifToolKit.preheat()
    }

    @available(*, deprecated, message: "Use gifToolKit.cleanup(_:)")
    public static func cleanupAllTmp() throws {
        let gifDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "GIF")
        if FileManager.default.fileExists(atPath: gifDirectory.path) {
            try FileManager.default.removeItem(at: gifDirectory)
        }
    }

    @available(*, deprecated, message: "Use gifToolKit.cleanup(_:)")
    public func cleanup() throws {
        try Self.cleanupAllTmp()
    }
}

@available(*, deprecated, message: "Use GIFGenerationRequest directly.")
extension GifToolParameter {
    fileprivate func toGIFGenerationRequest() throws -> GIFGenerationRequest {
        let options = GIFGenerationOptions(
            outputFPS: gifFPS,
            maxResolution: maxResolution,
            removeBackground: removeBg,
            includeOriginalFrames: isReturnOriginFrames,
            watermarks: imageDecorates.map { GIFWatermark(config: $0) }
        )

        let source: GIFGenerationSource
        switch data {
        #if canImport(PhotosUI)
        case .livePhoto(let livePhoto, let livePhotoFPS):
            source = .livePhoto(livePhoto, sourceFPS: livePhotoFPS)
        #endif
        case .images(let frames, let adjustOrientation):
            source = .images(frames, adjustOrientation: adjustOrientation)
        case .video(let url, let sourceFPS):
            source = .video(url, sourceFPS: sourceFPS.map(Double.init))
        }

        return GIFGenerationRequest(source: source, options: options)
    }
}
