import CoreGraphics
import Foundation
@testable import LiveGifKit
import Testing

@Suite("GIFToolKitImpl")
struct GIFToolKitImplTests {
    @Test("Generate GIF from image files emits events")
    func generateFromImagesPipeline() async throws {
        let storage = TemporaryStorageStub()
        let encoding = EncodingStub()
        let extractor = VideoFrameExtractorStub()
        let backgroundRemover = BackgroundRemoverStub()
        let photoLibrary = PhotoLibraryStub()
        let recommendations = RecommendationProviderStub()

        let inputImage = makeGIFImage(width: 40, height: 20, alpha: 255)
        let sourceURL = try writeImageToTempFile(inputImage, ext: "png")
        let processed = makeCGImage(width: 20, height: 10, alpha: 255)
        backgroundRemover.outputImages = [processed]
        encoding.outputFrames = [GIFImage.gifImage(cgImage: processed)]

        let toolKit = makeToolKit(
            storage: storage,
            encoding: encoding,
            extractor: extractor,
            backgroundRemover: backgroundRemover,
            photoLibrary: photoLibrary,
            recommendations: recommendations
        )

        let request = GIFGenerationURLRequest(
            source: .imageFiles([sourceURL], adjustOrientation: true),
            options: GIFGenerationOptions(
                outputFPS: 20,
                maxResolution: 250,
                removeBackground: true,
                watermarks: [GIFWatermark(content: .text("Demo"), position: .bottomRight)]
            )
        )
        let events = try await collectEvents(from: toolKit.generateGIF(request))
        let result = try #require(completedResult(in: events))

        #expect(containsPreparingEvent(events))
        #expect(containsEncodingEvent(events))
        #expect(result.frameCount == 1)
        #expect(result.gifURL.deletingLastPathComponent().standardizedFileURL.path == storage.directory.standardizedFileURL.path)
        #expect(backgroundRemover.calls == 1)

        let snapshot = encoding.snapshot()
        #expect(snapshot.capturedCGImages.count == 1)
        #expect(snapshot.capturedFrameDelay == 0.05)
        #expect(snapshot.capturedWatermarks.count == 1)
    }

    @Test("Generate GIF from video forwards extractor options")
    func generateFromVideoForwardsOptions() async throws {
        let storage = TemporaryStorageStub()
        let encoding = EncodingStub()
        let extractor = VideoFrameExtractorStub()
        let backgroundRemover = BackgroundRemoverStub()
        let photoLibrary = PhotoLibraryStub()
        let recommendations = RecommendationProviderStub()
        let extracted = makeGIFImage(width: 30, height: 20, alpha: 255)
        extractor.outputImages = [extracted]
        encoding.outputFrames = [extracted]

        let toolKit = makeToolKit(
            storage: storage,
            encoding: encoding,
            extractor: extractor,
            backgroundRemover: backgroundRemover,
            photoLibrary: photoLibrary,
            recommendations: recommendations
        )
        let videoURL = URL(fileURLWithPath: "/tmp/sample.mov")
        let request = GIFGenerationURLRequest(
            source: .videoFile(videoURL, sourceFPS: 12),
            options: GIFGenerationOptions(outputFPS: 24, maxResolution: 333)
        )

        _ = try await collectEvents(from: toolKit.generateGIF(request))
        #expect(extractor.lastVideoURL == videoURL)
        #expect(extractor.lastSourceFPS == 12)
        #expect(extractor.lastMaxResolution == 333)
        #expect(backgroundRemover.calls == 0)
    }

    @Test("Remove background stream succeeds and writes output file")
    func removeBackgroundSucceeds() async throws {
        let storage = TemporaryStorageStub()
        let encoding = EncodingStub()
        let extractor = VideoFrameExtractorStub()
        let backgroundRemover = BackgroundRemoverStub()
        let photoLibrary = PhotoLibraryStub()
        let recommendations = RecommendationProviderStub()
        let sourceURL = try writeImageToTempFile(makeGIFImage(width: 30, height: 30, alpha: 255), ext: "png")
        let processed = makeCGImage(width: 10, height: 10, alpha: 255)
        backgroundRemover.outputImages = [processed]

        let toolKit = makeToolKit(
            storage: storage,
            encoding: encoding,
            extractor: extractor,
            backgroundRemover: backgroundRemover,
            photoLibrary: photoLibrary,
            recommendations: recommendations
        )

        let events = try await collectBackgroundEvents(
            from: toolKit.removeBackground(.init(inputImageURL: sourceURL))
        )
        let result = try #require(completedBackgroundResult(in: events))

        #expect(containsBackgroundProcessingEvent(events))
        #expect(FileManager.default.fileExists(atPath: result.imageURL.path))
        #expect(result.pixelSize.width == 10)
        #expect(result.pixelSize.height == 10)
    }

    @Test("Remove background fails for empty remover output")
    func removeBackgroundFailsForEmptyOutput() async throws {
        let storage = TemporaryStorageStub()
        let encoding = EncodingStub()
        let extractor = VideoFrameExtractorStub()
        let backgroundRemover = BackgroundRemoverStub()
        let photoLibrary = PhotoLibraryStub()
        let recommendations = RecommendationProviderStub()
        let sourceURL = try writeImageToTempFile(makeGIFImage(width: 18, height: 18, alpha: 255), ext: "png")
        backgroundRemover.outputImages = []
        backgroundRemover.alwaysUseOutputImages = true

        let toolKit = makeToolKit(
            storage: storage,
            encoding: encoding,
            extractor: extractor,
            backgroundRemover: backgroundRemover,
            photoLibrary: photoLibrary,
            recommendations: recommendations
        )

        await #expect(throws: GifError.self) {
            _ = try await collectBackgroundEvents(
                from: toolKit.removeBackground(.init(inputImageURL: sourceURL))
            )
        }
    }

    @Test("GIFWatermark image bridge exports URL")
    @MainActor
    func watermarkImageBridgeExportsURL() throws {
        let image = makeGIFImage(width: 40, height: 40, alpha: 255)
        let content = try GIFWatermark.Content.image(image, width: 48)
        switch content {
        case .imageFile(let url, let width):
            #expect(width == 48)
            #expect(FileManager.default.fileExists(atPath: url.path))
            try? FileManager.default.removeItem(at: url)
        default:
            Issue.record("Expected imageFile watermark content")
        }
    }

    @Test("Cleanup request removes managed watermark temporary files")
    @MainActor
    func requestCleanupRemovesManagedWatermarkFiles() async throws {
        let storage = TemporaryStorageStub()
        let encoding = EncodingStub()
        let extractor = VideoFrameExtractorStub()
        let backgroundRemover = BackgroundRemoverStub()
        let photoLibrary = PhotoLibraryStub()
        let recommendations = RecommendationProviderStub()
        let sourceImage = makeGIFImage(width: 30, height: 30, alpha: 255)
        let sourceURL = try writeImageToTempFile(sourceImage, ext: "png")
        let watermarkImage = makeGIFImage(width: 16, height: 16, alpha: 255)
        let content = try GIFWatermark.Content.image(watermarkImage, width: 12)

        guard case .imageFile(let watermarkURL, _) = content else {
            Issue.record("Expected managed watermark URL")
            return
        }

        encoding.outputFrames = [sourceImage]

        let toolKit = makeToolKit(
            storage: storage,
            encoding: encoding,
            extractor: extractor,
            backgroundRemover: backgroundRemover,
            photoLibrary: photoLibrary,
            recommendations: recommendations
        )
        let request = GIFGenerationURLRequest(
            source: .imageFiles([sourceURL]),
            options: GIFGenerationOptions(
                outputFPS: 20,
                watermarks: [GIFWatermark(content: content)]
            )
        )
        _ = try await collectEvents(from: toolKit.generateGIF(request))
        #expect(FileManager.default.fileExists(atPath: watermarkURL.path))

        try await toolKit.cleanup(.requestOnly)
        #expect(!FileManager.default.fileExists(atPath: watermarkURL.path))
    }

    @Test("Save and recommendation requests are forwarded")
    func saveAndRecommendationsForwarding() async throws {
        let storage = TemporaryStorageStub()
        let encoding = EncodingStub()
        let extractor = VideoFrameExtractorStub()
        let backgroundRemover = BackgroundRemoverStub()
        let photoLibrary = PhotoLibraryStub()
        let recommendations = RecommendationProviderStub()

        photoLibrary.output = GIFSaveResult(localIdentifier: "saved-id")
        recommendations.outputAssets = [
            GIFRecommendedAsset(
                assetLocalIdentifier: "asset-1",
                thumbnailURL: URL(fileURLWithPath: "/tmp/thumb.png")
            ),
        ]

        let toolKit = makeToolKit(
            storage: storage,
            encoding: encoding,
            extractor: extractor,
            backgroundRemover: backgroundRemover,
            photoLibrary: photoLibrary,
            recommendations: recommendations
        )
        let saveRequest = GIFSaveURLRequest(payload: .fileURL(URL(fileURLWithPath: "/tmp/out.gif")))
        let recommendationRequest = GIFRecommendationURLRequest(days: 14, thumbnailSize: CGSize(width: 90, height: 70))

        let saveResult = try await toolKit.save(saveRequest)
        let assets = try await toolKit.fetchRecommendedAssets(recommendationRequest)

        #expect(saveResult.localIdentifier == "saved-id")
        #expect(photoLibrary.lastRequest?.payload != nil)
        #expect(recommendations.lastRequest?.days == 14)
        #expect(assets.count == 1)
    }

    @Test("Generate GIF cancels while extracting video frames")
    func generateCancellationDuringExtraction() async throws {
        let storage = TemporaryStorageStub()
        let encoding = EncodingStub()
        let extractor = VideoFrameExtractorStub()
        let backgroundRemover = BackgroundRemoverStub()
        let photoLibrary = PhotoLibraryStub()
        let recommendations = RecommendationProviderStub()

        extractor.onExtract = { _, _, _ in
            try await Task.sleep(for: .seconds(2))
            try Task.checkCancellation()
            return []
        }

        let toolKit = makeToolKit(
            storage: storage,
            encoding: encoding,
            extractor: extractor,
            backgroundRemover: backgroundRemover,
            photoLibrary: photoLibrary,
            recommendations: recommendations
        )

        let task = Task { () -> ([GIFGenerationEvent], Error?) in
            do {
                let events = try await collectEvents(
                    from: toolKit.generateGIF(
                        .init(source: .videoFile(URL(fileURLWithPath: "/tmp/cancel.mov")))
                    )
                )
                return (events, nil)
            } catch {
                return ([], error)
            }
        }

        await extractor.waitUntilStarted()
        task.cancel()
        let result = await task.value
        if let error = result.1 {
            #expect(error is CancellationError)
        }
        #expect(!containsCompletedEvent(result.0))
    }

    @Test("Generate GIF cancels during background removal")
    func generateCancellationDuringBackgroundRemoval() async throws {
        let storage = TemporaryStorageStub()
        let encoding = EncodingStub()
        let extractor = VideoFrameExtractorStub()
        let backgroundRemover = BackgroundRemoverStub()
        let photoLibrary = PhotoLibraryStub()
        let recommendations = RecommendationProviderStub()

        let sourceImage = makeGIFImage(width: 60, height: 60, alpha: 255)
        let sourceURL = try writeImageToTempFile(sourceImage, ext: "png")
        backgroundRemover.onRemove = { images in
            try await Task.sleep(for: .seconds(2))
            try Task.checkCancellation()
            return images
        }

        let toolKit = makeToolKit(
            storage: storage,
            encoding: encoding,
            extractor: extractor,
            backgroundRemover: backgroundRemover,
            photoLibrary: photoLibrary,
            recommendations: recommendations
        )
        let request = GIFGenerationURLRequest(
            source: .imageFiles([sourceURL]),
            options: GIFGenerationOptions(removeBackground: true)
        )

        let task = Task { () -> ([GIFGenerationEvent], Error?) in
            do {
                let events = try await collectEvents(from: toolKit.generateGIF(request))
                return (events, nil)
            } catch {
                return ([], error)
            }
        }

        await backgroundRemover.waitUntilStarted()
        task.cancel()
        let result = await task.value
        if let error = result.1 {
            #expect(error is CancellationError)
        }
        #expect(!containsCompletedEvent(result.0))
        #expect(encoding.snapshot().capturedCGImages.isEmpty)
    }

    @Test("Cleanup removes request and all temporary files")
    func cleanupScopes() async throws {
        let storage = TemporaryStorageStub()
        let encoding = EncodingStub()
        let extractor = VideoFrameExtractorStub()
        let backgroundRemover = BackgroundRemoverStub()
        let photoLibrary = PhotoLibraryStub()
        let recommendations = RecommendationProviderStub()
        let sourceImage = makeGIFImage(width: 12, height: 12, alpha: 255)
        let sourceURL = try writeImageToTempFile(sourceImage, ext: "png")
        encoding.outputFrames = [sourceImage]

        let toolKit = makeToolKit(
            storage: storage,
            encoding: encoding,
            extractor: extractor,
            backgroundRemover: backgroundRemover,
            photoLibrary: photoLibrary,
            recommendations: recommendations
        )

        _ = try await collectEvents(from: toolKit.generateGIF(.init(source: .imageFiles([sourceURL]))))
        try await toolKit.cleanup(.requestOnly)
        try await toolKit.cleanup(.allTemporaryGIFFiles)

        #expect(storage.cleanedDirectories.count == 1)
        #expect(storage.cleanedDirectories.first == storage.directory)
        #expect(storage.cleanupAllCalls == 1)
    }

    private func makeToolKit(
        storage: TemporaryStorageStub,
        encoding: EncodingStub,
        extractor: VideoFrameExtractorStub,
        backgroundRemover: BackgroundRemoverStub,
        photoLibrary: PhotoLibraryStub,
        recommendations: RecommendationProviderStub
    ) -> GIFToolKitImpl {
        GIFToolKitImpl(
            encoding: encoding,
            videoFrameExtractor: extractor,
            backgroundRemover: backgroundRemover,
            photoLibrary: photoLibrary,
            storage: storage,
            recommendationProvider: recommendations,
            frameStorageMemoryBudgetBytes: 1_024
        )
    }

    private func collectEvents(
        from stream: AsyncThrowingStream<GIFGenerationEvent, Error>
    ) async throws -> [GIFGenerationEvent] {
        var events: [GIFGenerationEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    private func collectBackgroundEvents(
        from stream: AsyncThrowingStream<GIFBackgroundRemovalEvent, Error>
    ) async throws -> [GIFBackgroundRemovalEvent] {
        var events: [GIFBackgroundRemovalEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    private func completedResult(in events: [GIFGenerationEvent]) -> GIFGenerationURLResult? {
        for event in events {
            if case .completed(let result) = event {
                return result
            }
        }
        return nil
    }

    private func completedBackgroundResult(in events: [GIFBackgroundRemovalEvent]) -> GIFBackgroundRemovalURLResult? {
        for event in events {
            if case .completed(let result) = event {
                return result
            }
        }
        return nil
    }

    private func containsPreparingEvent(_ events: [GIFGenerationEvent]) -> Bool {
        events.contains {
            if case .preparingFrames = $0 {
                return true
            }
            return false
        }
    }

    private func containsEncodingEvent(_ events: [GIFGenerationEvent]) -> Bool {
        events.contains {
            if case .encoding = $0 {
                return true
            }
            return false
        }
    }

    private func containsCompletedEvent(_ events: [GIFGenerationEvent]) -> Bool {
        events.contains {
            if case .completed = $0 {
                return true
            }
            return false
        }
    }

    private func containsBackgroundProcessingEvent(_ events: [GIFBackgroundRemovalEvent]) -> Bool {
        events.contains {
            if case .processing = $0 {
                return true
            }
            return false
        }
    }

    private func writeImageToTempFile(_ image: GIFImage, ext: String) throws -> URL {
        guard let data = image.gifPNGData else {
            throw GifError.invalidImageData
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "livegifkit-source-\(UUID().uuidString).\(ext)")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func makeGIFImage(width: Int, height: Int, alpha: UInt8) -> GIFImage {
        GIFImage.gifImage(cgImage: makeCGImage(width: width, height: height, alpha: alpha))
    }

    private func makeCGImage(width: Int, height: Int, alpha: UInt8) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = 255
            pixels[index + 1] = 0
            pixels[index + 2] = 0
            pixels[index + 3] = alpha
        }

        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bytesPerPixel * bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}

private final class EncodingStub: GIFEncoding, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var capturedCGImages: [CGImage] = []
    private(set) var capturedOutputURL: URL?
    private(set) var capturedFrameDelay: Double = 0
    private(set) var capturedWatermarks: [GIFWatermark] = []
    var outputFrames: [GIFImage] = []

    func encode(
        cgImages: [CGImage],
        outputURL: URL,
        frameDelay: Double,
        watermarks: [GIFWatermark],
        onProgress: @Sendable (_ completed: Int, _ total: Int) -> Void
    ) throws -> [GIFImage] {
        lock.lock()
        capturedCGImages = cgImages
        capturedOutputURL = outputURL
        capturedFrameDelay = frameDelay
        capturedWatermarks = watermarks
        let frames = outputFrames.isEmpty ? cgImages.map { GIFImage.gifImage(cgImage: $0) } : outputFrames
        lock.unlock()

        onProgress(cgImages.count, cgImages.count)
        return frames
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            capturedCGImages: capturedCGImages,
            capturedOutputURL: capturedOutputURL,
            capturedFrameDelay: capturedFrameDelay,
            capturedWatermarks: capturedWatermarks
        )
    }

    struct Snapshot {
        let capturedCGImages: [CGImage]
        let capturedOutputURL: URL?
        let capturedFrameDelay: Double
        let capturedWatermarks: [GIFWatermark]
    }
}

private final class VideoFrameExtractorStub: GIFVideoFrameExtracting, @unchecked Sendable {
    var outputImages: [GIFImage] = []
    var lastVideoURL: URL?
    var lastSourceFPS: Double?
    var lastMaxResolution: CGFloat?
    var onExtract: ((URL, Double?, CGFloat) async throws -> [GIFImage])?
    private var didStart = false
    private var startContinuations: [CheckedContinuation<Void, Never>] = []

    func extractFrames(from videoURL: URL, sourceFPS: Double?, maxResolution: CGFloat) async throws -> [GIFImage] {
        lastVideoURL = videoURL
        lastSourceFPS = sourceFPS
        lastMaxResolution = maxResolution
        didStart = true
        let continuations = startContinuations
        startContinuations.removeAll()
        continuations.forEach { $0.resume() }
        if let onExtract {
            return try await onExtract(videoURL, sourceFPS, maxResolution)
        }
        return outputImages
    }

    func waitUntilStarted() async {
        if didStart {
            return
        }
        await withCheckedContinuation { continuation in
            if didStart {
                continuation.resume()
            } else {
                startContinuations.append(continuation)
            }
        }
    }
}

private final class BackgroundRemoverStub: GIFBackgroundRemoving, @unchecked Sendable {
    var outputImages: [CGImage] = []
    var onRemove: (([CGImage]) async throws -> [CGImage])?
    var alwaysUseOutputImages = false
    private(set) var calls = 0
    private var didStart = false
    private var startContinuations: [CheckedContinuation<Void, Never>] = []

    func removeBackground(images: [CGImage]) async throws -> [CGImage] {
        calls += 1
        didStart = true
        let continuations = startContinuations
        startContinuations.removeAll()
        continuations.forEach { $0.resume() }
        if let onRemove {
            return try await onRemove(images)
        }
        if alwaysUseOutputImages {
            return outputImages
        }
        return outputImages.isEmpty ? images : outputImages
    }

    func waitUntilStarted() async {
        if didStart {
            return
        }
        await withCheckedContinuation { continuation in
            if didStart {
                continuation.resume()
            } else {
                startContinuations.append(continuation)
            }
        }
    }
}

private final class PhotoLibraryStub: GIFPhotoLibraryPersisting, @unchecked Sendable {
    var output = GIFSaveResult(localIdentifier: nil)
    var errorToThrow: Error?
    private(set) var lastRequest: GIFSaveURLRequest?

    func save(_ request: GIFSaveURLRequest) async throws -> GIFSaveResult {
        lastRequest = request
        if let errorToThrow {
            throw errorToThrow
        }
        return output
    }
}

private final class TemporaryStorageStub: GIFTemporaryStorage, @unchecked Sendable {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "GIF-Test-\(UUID().uuidString)")
    private(set) var cleanedDirectories: [URL] = []
    private(set) var cleanupAllCalls = 0

    func makeRequestDirectory() throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func cleanup(directory: URL) throws {
        cleanedDirectories.append(directory)
    }

    func cleanupAll() throws {
        cleanupAllCalls += 1
    }
}

private final class RecommendationProviderStub: GIFRecommendationProviding, @unchecked Sendable {
    var outputAssets: [GIFRecommendedAsset] = []
    private(set) var lastRequest: GIFRecommendationURLRequest?

    func fetch(_ request: GIFRecommendationURLRequest) async throws -> [GIFRecommendedAsset] {
        lastRequest = request
        return outputAssets
    }
}
