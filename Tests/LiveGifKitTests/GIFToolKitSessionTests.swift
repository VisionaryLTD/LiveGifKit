import CoreGraphics
import Foundation
@testable import LiveGifKit
import Testing

@Suite("GIFToolKitSession")
@MainActor
struct GIFToolKitSessionTests {
    @Test("Attribute edits prepare preview but do not encode GIF")
    func previewPreparationOnly() async throws {
        let recorder = SessionRecorderGIFToolKit()
        let extractor = SessionVideoFrameExtractorStub()
        extractor.outputImages = [makeGIFImage(width: 80, height: 60, alpha: 255)]
        let encoder = SessionEncodingStub()

        let session = makeSession(
            recorder: recorder,
            extractor: extractor,
            encoding: encoder
        )
        let sourceURL = try makeTempFileURL(ext: "mov")

        session.attributes = GIFEditorAttributes(source: .videoFile(sourceURL))
        await waitUntil { !session.previewFrameURLs.isEmpty }

        #expect(!session.previewFrameURLs.isEmpty)
        #expect(recorder.generateCallCount() == 0)
        #expect(encoder.callCount() == 0)
        #expect(session.previewPreparationCount == 1)
        #expect(session.finalEncodeCount == 0)
    }

    @Test("Debounce coalesces rapid edits into one preview preparation")
    func debounceCoalescesRapidEdits() async throws {
        let recorder = SessionRecorderGIFToolKit()
        let extractor = SessionVideoFrameExtractorStub()
        extractor.outputImages = [makeGIFImage(width: 80, height: 60, alpha: 255)]
        let encoder = SessionEncodingStub()
        let session = makeSession(
            recorder: recorder,
            extractor: extractor,
            encoding: encoder
        )
        let sourceURL = try makeTempFileURL(ext: "mov")

        var attributes = GIFEditorAttributes(source: .videoFile(sourceURL))
        attributes.watermarkText = "A"
        session.attributes = attributes
        attributes.watermarkText = "AB"
        session.attributes = attributes
        attributes.watermarkText = "ABC"
        session.attributes = attributes

        await waitUntil { !session.previewFrameURLs.isEmpty }
        #expect(extractor.callCount() == 1)
        #expect(session.previewPreparationCount == 1)
    }

    @Test("Cache hit reuses preview frames without re-preparing")
    func cacheHitReusesPreview() async throws {
        let recorder = SessionRecorderGIFToolKit()
        let extractor = SessionVideoFrameExtractorStub()
        extractor.outputImages = [makeGIFImage(width: 80, height: 60, alpha: 255)]
        let encoder = SessionEncodingStub()
        let session = makeSession(
            recorder: recorder,
            extractor: extractor,
            encoding: encoder
        )
        let sourceURL = try makeTempFileURL(ext: "mov")

        var attributes = GIFEditorAttributes(source: .videoFile(sourceURL))
        session.attributes = attributes
        await waitUntil { extractor.callCount() == 1 }

        attributes.watermarkText = "Demo"
        session.attributes = attributes
        await waitUntil { extractor.callCount() == 2 }

        attributes.watermarkText = ""
        session.attributes = attributes
        try? await Task.sleep(for: .milliseconds(180))

        #expect(extractor.callCount() == 2)
        #expect(session.previewPreparationCount == 2)
    }

    @Test("Missing preview frame files force re-prepare")
    func missingPreviewFileReprepares() async throws {
        let recorder = SessionRecorderGIFToolKit()
        let extractor = SessionVideoFrameExtractorStub()
        extractor.outputImages = [makeGIFImage(width: 80, height: 60, alpha: 255)]
        let encoder = SessionEncodingStub()
        let session = makeSession(
            recorder: recorder,
            extractor: extractor,
            encoding: encoder
        )
        let sourceURL = try makeTempFileURL(ext: "mov")

        let attributes = GIFEditorAttributes(source: .videoFile(sourceURL))
        session.attributes = attributes
        await waitUntil { !session.previewFrameURLs.isEmpty }
        let frameURL = try #require(session.previewFrameURLs.first)
        try? FileManager.default.removeItem(at: frameURL)

        session.attributes = attributes
        await waitUntil { extractor.callCount() == 2 }
        #expect(extractor.callCount() == 2)
    }

    @Test("Save waits for in-flight preview and encodes once")
    func saveWaitsForPreviewPreparation() async throws {
        let recorder = SessionRecorderGIFToolKit()
        let extractor = SessionVideoFrameExtractorStub()
        extractor.outputImages = [makeGIFImage(width: 120, height: 80, alpha: 255)]
        let encoder = SessionEncodingStub()
        let session = makeSession(
            recorder: recorder,
            extractor: extractor,
            encoding: encoder
        )
        let sourceURL = try makeTempFileURL(ext: "mov")

        let lock = NSLock()
        var continuation: CheckedContinuation<Void, Never>?
        extractor.onExtract = { _, _, _ in
            await withCheckedContinuation { (resume: CheckedContinuation<Void, Never>) in
                lock.withLock {
                    continuation = resume
                }
            }
            return [makeGIFImage(width: 120, height: 80, alpha: 255)]
        }

        session.attributes = GIFEditorAttributes(source: .videoFile(sourceURL))
        await waitUntil { extractor.callCount() == 1 }

        let saveTask = Task {
            try await session.saveLatestGIF()
        }

        try? await Task.sleep(for: .milliseconds(120))
        #expect(encoder.callCount() == 0)
        #expect(recorder.saveCallCount() == 0)

        lock.withLock {
            continuation?.resume()
            continuation = nil
        }

        _ = try await saveTask.value
        #expect(encoder.callCount() == 1)
        #expect(recorder.saveCallCount() == 1)
        #expect(session.finalEncodeCount == 1)
        #expect(session.generationResult != nil)
    }

    @Test("Save encodes GIF only on button action")
    func saveEncodesOnlyOnSaveAction() async throws {
        let recorder = SessionRecorderGIFToolKit()
        let extractor = SessionVideoFrameExtractorStub()
        extractor.outputImages = [makeGIFImage(width: 100, height: 70, alpha: 255)]
        let encoder = SessionEncodingStub()
        let session = makeSession(
            recorder: recorder,
            extractor: extractor,
            encoding: encoder
        )
        let sourceURL = try makeTempFileURL(ext: "mov")

        session.attributes = GIFEditorAttributes(source: .videoFile(sourceURL))
        await waitUntil { !session.previewFrameURLs.isEmpty }
        #expect(encoder.callCount() == 0)
        #expect(session.finalEncodeCount == 0)

        _ = try await session.saveLatestGIF()
        #expect(encoder.callCount() == 1)
        #expect(session.finalEncodeCount == 1)
    }

    @Test("Source FPS changes do not re-prepare for image source")
    func sourceFPSIgnoredForImageSource() async throws {
        let recorder = SessionRecorderGIFToolKit()
        let extractor = SessionVideoFrameExtractorStub()
        extractor.outputImages = [makeGIFImage(width: 100, height: 70, alpha: 255)]
        let encoder = SessionEncodingStub()
        let session = makeSession(
            recorder: recorder,
            extractor: extractor,
            encoding: encoder
        )
        let imageURL = try makeTempImageFileURL()

        var attributes = GIFEditorAttributes(source: .imageFiles([imageURL]))
        attributes.sourceFPS = 10
        session.attributes = attributes
        await waitUntil { !session.previewFrameURLs.isEmpty }
        let preparationCount = session.previewPreparationCount

        attributes.sourceFPS = 45
        session.attributes = attributes
        try? await Task.sleep(for: .milliseconds(180))

        #expect(session.previewPreparationCount == preparationCount)
        #expect(extractor.callCount() == 0)
    }

    @Test("Proxy methods still forward correctly")
    func proxyMethodsForward() async throws {
        let recorder = SessionRecorderGIFToolKit()
        let extractor = SessionVideoFrameExtractorStub()
        extractor.outputImages = [makeGIFImage(width: 100, height: 70, alpha: 255)]
        let encoder = SessionEncodingStub()
        let session = makeSession(
            recorder: recorder,
            extractor: extractor,
            encoding: encoder
        )
        let sourceURL = try makeTempImageFileURL()

        _ = try await session.fetchRecommendedAssets(.init(days: 7))
        try await session.preheat()
        try await session.cleanup(.requestOnly)

        var events: [GIFBackgroundRemovalEvent] = []
        for try await event in session.removeBackground(.init(inputImageURL: sourceURL)) {
            events.append(event)
        }

        #expect(recorder.fetchCallCount() == 1)
        #expect(recorder.preheatCallCount() == 1)
        #expect(recorder.cleanupScopes().contains {
            if case .requestOnly = $0 {
                return true
            }
            return false
        })
        #expect(recorder.removeBackgroundCallCount() == 1)
        #expect(events.contains {
            if case .processing = $0 { return true }
            return false
        })
    }

    @Test("Memory telemetry remains non-negative")
    func memoryTelemetryNonNegative() async throws {
        let recorder = SessionRecorderGIFToolKit()
        let extractor = SessionVideoFrameExtractorStub()
        extractor.outputImages = [makeGIFImage(width: 100, height: 70, alpha: 255)]
        let encoder = SessionEncodingStub()
        let session = makeSession(
            recorder: recorder,
            extractor: extractor,
            encoding: encoder
        )
        let sourceURL = try makeTempFileURL(ext: "mov")

        session.attributes = GIFEditorAttributes(source: .videoFile(sourceURL))
        await waitUntil { !session.previewFrameURLs.isEmpty }
        #expect(session.memoryTelemetry.residentMB >= 0)
        #expect(session.memoryTelemetry.peakResidentMB >= session.memoryTelemetry.residentMB)
    }
}

// MARK: - Helpers

@MainActor
private func makeSession(
    recorder: SessionRecorderGIFToolKit,
    extractor: SessionVideoFrameExtractorStub,
    encoding: SessionEncodingStub
) -> GIFToolKitSession {
    GIFToolKitSession(
        gifToolKit: recorder,
        videoFrameExtractor: extractor,
        backgroundRemover: SessionBackgroundRemoverStub(),
        encoding: encoding,
        debounceDuration: .milliseconds(40)
    )
}

@MainActor
private func makeTempFileURL(ext: String) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "livegifkit-session-\(UUID().uuidString).\(ext)")
    try Data("demo".utf8).write(to: url, options: .atomic)
    return url
}

@MainActor
private func makeTempImageFileURL() throws -> URL {
    let image = makeGIFImage(width: 80, height: 60, alpha: 255)
    guard let data = image.gifPNGData else {
        throw GifError.invalidImageData
    }
    let url = try makeTempFileURL(ext: "png")
    try data.write(to: url, options: .atomic)
    return url
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(2),
    interval: Duration = .milliseconds(20),
    _ condition: @escaping @MainActor () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if condition() {
            return
        }
        try? await Task.sleep(for: interval)
    }
    Issue.record("Timed out waiting for condition")
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
        pixels[index + 1] = 255
        pixels[index + 2] = 255
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

// MARK: - Test Doubles

private final class SessionRecorderGIFToolKit: GIFToolKit, @unchecked Sendable {
    private let lock = NSLock()
    private var generateRequests: [GIFGenerationURLRequest] = []
    private var cleanupCalls: [GIFCleanupScope] = []
    private var saveCalls = 0
    private var fetchCalls = 0
    private var preheatCalls = 0
    private var removeBackgroundCalls = 0

    func generateGIF(_ request: GIFGenerationURLRequest) -> AsyncThrowingStream<GIFGenerationEvent, Error> {
        lock.withLock {
            generateRequests.append(request)
        }
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: GifError.unimplemented)
        }
    }

    func removeBackground(_ request: GIFBackgroundRemovalURLRequest) -> AsyncThrowingStream<GIFBackgroundRemovalEvent, Error> {
        lock.withLock {
            removeBackgroundCalls += 1
        }
        return AsyncThrowingStream { continuation in
            continuation.yield(.processing)
            continuation.yield(
                .completed(
                    GIFBackgroundRemovalURLResult(
                        imageURL: request.outputImageURL ?? request.inputImageURL,
                        pixelSize: CGSize(width: 8, height: 8)
                    )
                )
            )
            continuation.finish()
        }
    }

    func save(_ request: GIFSaveURLRequest) async throws -> GIFSaveResult {
        lock.withLock {
            saveCalls += 1
        }
        return GIFSaveResult(localIdentifier: "saved")
    }

    func fetchRecommendedAssets(_ request: GIFRecommendationURLRequest) async throws -> [GIFRecommendedAsset] {
        lock.withLock {
            fetchCalls += 1
        }
        return []
    }

    func preheat() async throws {
        lock.withLock {
            preheatCalls += 1
        }
    }

    func cleanup(_ scope: GIFCleanupScope) async throws {
        lock.withLock {
            cleanupCalls.append(scope)
        }
    }

    func generateCallCount() -> Int {
        lock.withLock {
            generateRequests.count
        }
    }

    func cleanupScopes() -> [GIFCleanupScope] {
        lock.withLock {
            cleanupCalls
        }
    }

    func saveCallCount() -> Int {
        lock.withLock {
            saveCalls
        }
    }

    func fetchCallCount() -> Int {
        lock.withLock {
            fetchCalls
        }
    }

    func preheatCallCount() -> Int {
        lock.withLock {
            preheatCalls
        }
    }

    func removeBackgroundCallCount() -> Int {
        lock.withLock {
            removeBackgroundCalls
        }
    }
}

private final class SessionVideoFrameExtractorStub: GIFVideoFrameExtracting, @unchecked Sendable {
    private let lock = NSLock()
    var outputImages: [GIFImage] = []
    var onExtract: ((URL, Double?, CGFloat) async throws -> [GIFImage])?
    private var calls = 0

    func extractFrames(from videoURL: URL, sourceFPS: Double?, maxResolution: CGFloat) async throws -> [GIFImage] {
        lock.withLock {
            calls += 1
        }
        if let onExtract {
            return try await onExtract(videoURL, sourceFPS, maxResolution)
        }
        return outputImages
    }

    func callCount() -> Int {
        lock.withLock {
            calls
        }
    }
}

private struct SessionBackgroundRemoverStub: GIFBackgroundRemoving, @unchecked Sendable {
    func removeBackground(images: [CGImage]) async throws -> [CGImage] {
        images
    }
}

private final class SessionEncodingStub: GIFEncoding, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    func encode(
        cgImages: [CGImage],
        outputURL: URL,
        frameDelay: Double,
        watermarks: [GIFWatermark],
        onProgress: @Sendable (_ completed: Int, _ total: Int) -> Void
    ) throws -> [GIFImage] {
        lock.withLock {
            calls += 1
        }
        let frames = cgImages.map { GIFImage.gifImage(cgImage: $0) }
        try Data([0x47, 0x49, 0x46]).write(to: outputURL, options: .atomic)
        onProgress(cgImages.count, cgImages.count)
        return frames
    }

    func callCount() -> Int {
        lock.withLock {
            calls
        }
    }
}

private extension NSLock {
    func withLock<ResultType>(_ body: () -> ResultType) -> ResultType {
        lock()
        defer { unlock() }
        return body()
    }
}
