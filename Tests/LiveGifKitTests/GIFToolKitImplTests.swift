@testable import LiveGifKit
import CoreGraphics
import Foundation
import Testing

@Suite("GIFToolKitImpl")
struct GIFToolKitImplTests {
    @Test("Generate GIF from images applies shared pipeline")
    func generateFromImagesPipeline() async throws {
        let storage = TemporaryStorageStub()
        let encoding = EncodingStub()
        let extractor = VideoFrameExtractorStub()
        let backgroundRemover = BackgroundRemoverStub()
        let photoLibrary = PhotoLibraryStub()
        let recommendations = RecommendationProviderStub()

        let sourceImage = makeGIFImage(width: 40, height: 20, alpha: 255)
        let processedImage = makeCGImage(width: 20, height: 10, alpha: 255)
        await backgroundRemover.setOutputImages([processedImage])
        encoding.outputFrames = [GIFImage.gifImage(cgImage: processedImage)]

        let toolKit = GIFToolKitImpl(
            encoding: encoding,
            videoFrameExtractor: extractor,
            backgroundRemover: backgroundRemover,
            photoLibrary: photoLibrary,
            storage: storage,
            recommendationProvider: recommendations
        )
        let request = GIFGenerationRequest(
            source: .images([sourceImage], adjustOrientation: true),
            options: GIFGenerationOptions(
                outputFPS: 20,
                maxResolution: 250,
                removeBackground: true,
                includeOriginalFrames: true,
                watermarks: [GIFWatermark(content: .text("Demo"), position: .bottomRight)]
            )
        )

        let result = try await toolKit.generateGIF(request)
        let snapshot = encoding.snapshot()
        let removerSnapshot = await backgroundRemover.snapshot()

        #expect(snapshot.capturedCGImages.count == 1)
        #expect(snapshot.capturedFrameDelay == 0.05)
        #expect(snapshot.capturedWatermarks.count == 1)
        #expect(removerSnapshot.calls == 1)
        #expect(result.frames.count == 1)
        #expect(result.originalFrames.count == 1)
        #expect(result.fileURL.deletingLastPathComponent().path == storage.directory.path)
    }

    @Test("Generate GIF from video forwards extractor options")
    func generateFromVideoForwardsOptions() async throws {
        let storage = TemporaryStorageStub()
        let encoding = EncodingStub()
        let extractor = VideoFrameExtractorStub()
        let backgroundRemover = BackgroundRemoverStub()
        let photoLibrary = PhotoLibraryStub()
        let recommendations = RecommendationProviderStub()
        let extractedImage = makeGIFImage(width: 30, height: 20, alpha: 255)
        await extractor.setOutputImages([extractedImage])
        encoding.outputFrames = [extractedImage]

        let toolKit = GIFToolKitImpl(
            encoding: encoding,
            videoFrameExtractor: extractor,
            backgroundRemover: backgroundRemover,
            photoLibrary: photoLibrary,
            storage: storage,
            recommendationProvider: recommendations
        )
        let videoURL = URL(fileURLWithPath: "/tmp/sample.mov")
        let request = GIFGenerationRequest(
            source: .video(videoURL, sourceFPS: 12),
            options: GIFGenerationOptions(outputFPS: 24, maxResolution: 333)
        )

        _ = try await toolKit.generateGIF(request)
        let extractorSnapshot = await extractor.snapshot()
        let removerSnapshot = await backgroundRemover.snapshot()

        #expect(extractorSnapshot.lastVideoURL == videoURL)
        #expect(extractorSnapshot.lastSourceFPS == 12)
        #expect(extractorSnapshot.lastMaxResolution == 333)
        #expect(removerSnapshot.calls == 0)
    }

    @Test("Cleanup removes latest request directory and all temporary files")
    func cleanupScopes() async throws {
        let storage = TemporaryStorageStub()
        let encoding = EncodingStub()
        let extractor = VideoFrameExtractorStub()
        let backgroundRemover = BackgroundRemoverStub()
        let photoLibrary = PhotoLibraryStub()
        let recommendations = RecommendationProviderStub()
        let sourceImage = makeGIFImage(width: 12, height: 12, alpha: 255)
        encoding.outputFrames = [sourceImage]

        let toolKit = GIFToolKitImpl(
            encoding: encoding,
            videoFrameExtractor: extractor,
            backgroundRemover: backgroundRemover,
            photoLibrary: photoLibrary,
            storage: storage,
            recommendationProvider: recommendations
        )

        _ = try await toolKit.generateGIF(.init(source: .images([sourceImage])))
        try await toolKit.cleanup(.requestOnly)
        try await toolKit.cleanup(.allTemporaryGIFFiles)

        #expect(storage.cleanedDirectories.count == 1)
        #expect(storage.cleanedDirectories.first == storage.directory)
        #expect(storage.cleanupAllCalls == 1)
    }

    @Test("Save and recommendations forward requests")
    func saveAndRecommendationsForwarding() async throws {
        let storage = TemporaryStorageStub()
        let encoding = EncodingStub()
        let extractor = VideoFrameExtractorStub()
        let backgroundRemover = BackgroundRemoverStub()
        let photoLibrary = PhotoLibraryStub()
        let recommendations = RecommendationProviderStub()
        await recommendations.setOutputImages([makeGIFImage(width: 8, height: 8, alpha: 255)])
        await photoLibrary.setOutput(GIFSaveResult(localIdentifier: "saved-id"))

        let toolKit = GIFToolKitImpl(
            encoding: encoding,
            videoFrameExtractor: extractor,
            backgroundRemover: backgroundRemover,
            photoLibrary: photoLibrary,
            storage: storage,
            recommendationProvider: recommendations
        )

        let saveRequest = GIFSaveRequest(payload: .fileURL(URL(fileURLWithPath: "/tmp/out.gif")))
        let saveResult = try await toolKit.save(saveRequest)
        let recommendationRequest = GIFRecommendationRequest(days: 14, thumbnailSize: CGSize(width: 90, height: 70))
        let images = try await toolKit.fetchRecommendedImages(recommendationRequest)

        #expect(saveResult.localIdentifier == "saved-id")
        let lastSaveRequest = await photoLibrary.lastRequest
        switch lastSaveRequest?.destination {
        case .photoLibrary(let albumName):
            #expect(albumName == "LifeStickers")
        default:
            Issue.record("Expected photo library destination")
        }
        #expect(images.count == 1)
        #expect(await recommendations.lastRequest?.days == 14)
        #expect(await recommendations.lastRequest?.thumbnailSize == CGSize(width: 90, height: 70))
    }

    @Test("Save propagates denied authorization error")
    func saveDeniedErrorPropagation() async throws {
        let storage = TemporaryStorageStub()
        let encoding = EncodingStub()
        let extractor = VideoFrameExtractorStub()
        let backgroundRemover = BackgroundRemoverStub()
        let photoLibrary = PhotoLibraryStub()
        let recommendations = RecommendationProviderStub()
        await photoLibrary.setError(.denied)

        let toolKit = GIFToolKitImpl(
            encoding: encoding,
            videoFrameExtractor: extractor,
            backgroundRemover: backgroundRemover,
            photoLibrary: photoLibrary,
            storage: storage,
            recommendationProvider: recommendations
        )

        do {
            _ = try await toolKit.save(.init(payload: .fileURL(URL(fileURLWithPath: "/tmp/denied.gif"))))
            Issue.record("Expected denied authorization error")
        } catch AlbumToolError.denied {
        } catch {
            Issue.record("Expected AlbumToolError.denied, got \(error)")
        }
    }

    @Test("Save propagates save failure error")
    func saveFailureErrorPropagation() async throws {
        let storage = TemporaryStorageStub()
        let encoding = EncodingStub()
        let extractor = VideoFrameExtractorStub()
        let backgroundRemover = BackgroundRemoverStub()
        let photoLibrary = PhotoLibraryStub()
        let recommendations = RecommendationProviderStub()
        await photoLibrary.setError(.saveFail)

        let toolKit = GIFToolKitImpl(
            encoding: encoding,
            videoFrameExtractor: extractor,
            backgroundRemover: backgroundRemover,
            photoLibrary: photoLibrary,
            storage: storage,
            recommendationProvider: recommendations
        )

        do {
            _ = try await toolKit.save(.init(payload: .fileURL(URL(fileURLWithPath: "/tmp/savefail.gif"))))
            Issue.record("Expected save failure error")
        } catch AlbumToolError.saveFail {
        } catch {
            Issue.record("Expected AlbumToolError.saveFail, got \(error)")
        }
    }

    @Test("Generate GIF cancels while extracting video frames")
    func generateCancellationDuringExtraction() async throws {
        let storage = TemporaryStorageStub()
        let encoding = EncodingStub()
        let extractor = VideoFrameExtractorStub()
        let backgroundRemover = BackgroundRemoverStub()
        let photoLibrary = PhotoLibraryStub()
        let recommendations = RecommendationProviderStub()

        await extractor.setOnExtract { _, _, _ in
            try await Task.sleep(for: .seconds(2))
            try Task.checkCancellation()
            return []
        }

        let toolKit = GIFToolKitImpl(
            encoding: encoding,
            videoFrameExtractor: extractor,
            backgroundRemover: backgroundRemover,
            photoLibrary: photoLibrary,
            storage: storage,
            recommendationProvider: recommendations
        )

        let task = Task {
            try await toolKit.generateGIF(.init(source: .video(URL(fileURLWithPath: "/tmp/cancel.mov"))))
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
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

        await backgroundRemover.setOnRemove { images in
            try await Task.sleep(for: .seconds(2))
            try Task.checkCancellation()
            return images
        }

        let toolKit = GIFToolKitImpl(
            encoding: encoding,
            videoFrameExtractor: extractor,
            backgroundRemover: backgroundRemover,
            photoLibrary: photoLibrary,
            storage: storage,
            recommendationProvider: recommendations
        )
        let request = GIFGenerationRequest(
            source: .images([sourceImage]),
            options: GIFGenerationOptions(removeBackground: true)
        )
        let task = Task {
            try await toolKit.generateGIF(request)
        }

        await backgroundRemover.waitUntilStarted()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        let snapshot = encoding.snapshot()
        #expect(snapshot.capturedCGImages.isEmpty)
    }

    @Test("Watermark position round-trips through compatibility model", arguments: GIFWatermarkPosition.allCases)
    func watermarkPositionRoundTrip(position: GIFWatermarkPosition) {
        let watermark = GIFWatermark(
            content: .text("RoundTrip"),
            position: position,
            offset: CGPoint(x: 3, y: 4),
            origin: CGPoint(x: 11, y: 12)
        )
        let config = ImageDecorateConfig(watermark: watermark)
        let roundTrip = GIFWatermark(config: config)

        #expect(roundTrip.position == position)
        #expect(roundTrip.offset == CGPoint(x: 3, y: 4))
        #expect(roundTrip.origin == CGPoint(x: 11, y: 12))
        switch roundTrip.content {
        case .text(let text, _, _, _):
            #expect(text == "RoundTrip")
        default:
            Issue.record("Expected text watermark after round trip")
        }
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
        watermarks: [GIFWatermark]
    ) throws -> [GIFImage] {
        lock.lock()
        capturedCGImages = cgImages
        capturedOutputURL = outputURL
        capturedFrameDelay = frameDelay
        capturedWatermarks = watermarks
        let frames = outputFrames
        lock.unlock()
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

private actor VideoFrameExtractorStub: GIFVideoFrameExtracting {
    var outputImages: [GIFImage] = []
    var lastVideoURL: URL?
    var lastSourceFPS: Double?
    var lastMaxResolution: CGFloat?
    var onExtract: ((URL, Double?, CGFloat) async throws -> [GIFImage])?

    func extractFrames(
        from videoURL: URL,
        sourceFPS: Double?,
        maxResolution: CGFloat
    ) async throws -> [GIFImage] {
        lastVideoURL = videoURL
        lastSourceFPS = sourceFPS
        lastMaxResolution = maxResolution
        if let onExtract {
            return try await onExtract(videoURL, sourceFPS, maxResolution)
        }
        return outputImages
    }

    func snapshot() -> Snapshot {
        Snapshot(
            lastVideoURL: lastVideoURL,
            lastSourceFPS: lastSourceFPS,
            lastMaxResolution: lastMaxResolution
        )
    }

    func setOutputImages(_ images: [GIFImage]) {
        outputImages = images
    }

    func setOnExtract(_ handler: @escaping (URL, Double?, CGFloat) async throws -> [GIFImage]) {
        onExtract = handler
    }

    struct Snapshot {
        let lastVideoURL: URL?
        let lastSourceFPS: Double?
        let lastMaxResolution: CGFloat?
    }
}

private actor BackgroundRemoverStub: GIFBackgroundRemoving {
    var outputImages: [CGImage] = []
    var onRemove: (([CGImage]) async throws -> [CGImage])?
    private(set) var calls = 0
    private var didStart = false
    private var startContinuations: [CheckedContinuation<Void, Never>] = []

    func removeBackground(images: [CGImage]) async throws -> [CGImage] {
        calls += 1
        didStart = true
        if !startContinuations.isEmpty {
            let continuations = startContinuations
            startContinuations.removeAll()
            continuations.forEach { $0.resume() }
        }
        if let onRemove {
            return try await onRemove(images)
        }
        return outputImages.isEmpty ? images : outputImages
    }

    func snapshot() -> Snapshot {
        Snapshot(calls: calls)
    }

    func setOutputImages(_ images: [CGImage]) {
        outputImages = images
    }

    func setOnRemove(_ handler: @escaping ([CGImage]) async throws -> [CGImage]) {
        onRemove = handler
    }

    func waitUntilStarted() async {
        if didStart {
            return
        }
        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    struct Snapshot {
        let calls: Int
    }
}

private actor PhotoLibraryStub: GIFPhotoLibraryPersisting {
    var output = GIFSaveResult(localIdentifier: nil)
    var errorToThrow: AlbumToolError?
    private(set) var lastRequest: GIFSaveRequest?

    func save(_ request: GIFSaveRequest) async throws -> GIFSaveResult {
        lastRequest = request
        if let errorToThrow {
            throw errorToThrow
        }
        return output
    }

    func setOutput(_ output: GIFSaveResult) {
        self.output = output
    }

    func setError(_ error: AlbumToolError?) {
        errorToThrow = error
    }
}

private final class TemporaryStorageStub: GIFTemporaryStorage, @unchecked Sendable {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "GIF-Test-\(UUID().uuidString)")
    private(set) var cleanedDirectories: [URL] = []
    private(set) var cleanupAllCalls = 0

    func makeRequestDirectory() throws -> URL {
        directory
    }

    func cleanup(directory: URL) throws {
        cleanedDirectories.append(directory)
    }

    func cleanupAll() throws {
        cleanupAllCalls += 1
    }
}

private actor RecommendationProviderStub: GIFRecommendationProviding {
    var outputImages: [GIFImage] = []
    private(set) var lastRequest: GIFRecommendationRequest?

    func fetch(_ request: GIFRecommendationRequest) async throws -> [GIFImage] {
        lastRequest = request
        return outputImages
    }

    func setOutputImages(_ images: [GIFImage]) {
        outputImages = images
    }
}
