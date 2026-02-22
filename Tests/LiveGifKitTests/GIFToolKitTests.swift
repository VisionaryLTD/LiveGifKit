import CoreGraphics
import Dependencies
import Foundation
@testable import LiveGifKit
import Testing

@Suite("GIFToolKit API")
struct GIFToolKitTests {
    @Test("Default dependency is unimplemented")
    @MainActor
    func defaultDependencyThrows() async {
        @Dependency(\.gifToolKit) var gifToolKit
        await #expect(throws: GIFError.self) {
            _ = try await gifToolKit.fetchRecommendedAssets(.init())
        }
    }

    @Test("withDependencies overrides GIFToolKit")
    @MainActor
    func dependencyOverrideWorks() async throws {
        let outputURL = makeTempURL(ext: "gif")
        try Data([0x47, 0x49, 0x46]).write(to: outputURL)
        let recorder = DependencyRecorderGIFToolKit(
            generationResult: .init(
                gifURL: outputURL,
                frameCount: 2,
                pixelSize: CGSize(width: 80, height: 60),
                duration: 1.2
            )
        )
        let sourceURL = try makeSourceImageFile()

        let result = try await withDependencies {
            $0.gifToolKit = recorder
        } operation: {
            @Dependency(\.gifToolKit) var gifToolKit
            let request = GIFGenerationURLRequest(source: .imageFiles([sourceURL], adjustOrientation: true))
            var completed: GIFGenerationURLResult?
            for try await event in gifToolKit.generateGIF(request) {
                if case .completed(let result) = event {
                    completed = result
                }
            }
            return try #require(completed)
        }

        #expect(result.gifURL == outputURL)
        let capturedRequest = recorder.lastGenerationRequest()
        switch capturedRequest?.source {
        case .imageFiles(let urls, let adjustOrientation):
            #expect(urls == [sourceURL])
            #expect(adjustOrientation == true)
        default:
            Issue.record("Expected imageFiles source")
        }
    }

    @Test("Non-transparent bounds ignore low-alpha matte noise")
    func nonTransparentBoundingBoxIgnoresLowAlphaNoise() {
        let cgImage = makeAlphaMatteImage(
            width: 10,
            height: 8,
            matteAlpha: 2,
            subjectRect: CGRect(x: 3, y: 2, width: 4, height: 4),
            subjectAlpha: 255
        )
        let rect = cgImage.nonTransparentBoundingBox()
        #expect(rect == CGRect(x: 3, y: 2, width: 4, height: 4))
    }

    private func makeSourceImageFile() throws -> URL {
        let image = makeImage(width: 12, height: 8)
        guard let data = image.gifPNGData else {
            throw GifError.invalidImageData
        }
        let url = makeTempURL(ext: "png")
        try data.write(to: url)
        return url
    }

    private func makeTempURL(ext: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "livegifkit-test-\(UUID().uuidString).\(ext)")
    }

    private func makeImage(width: Int, height: Int) -> GIFImage {
        GIFImage.gifImage(cgImage: makeCGImage(width: width, height: height, alpha: 255))
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

    private func makeAlphaMatteImage(
        width: Int,
        height: Int,
        matteAlpha: UInt8,
        subjectRect: CGRect,
        subjectAlpha: UInt8
    ) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                pixels[index] = 150
                pixels[index + 1] = 150
                pixels[index + 2] = 150
                pixels[index + 3] = matteAlpha
            }
        }

        for y in Int(subjectRect.minY)..<Int(subjectRect.maxY) {
            for x in Int(subjectRect.minX)..<Int(subjectRect.maxX) {
                let index = (y * width + x) * 4
                pixels[index] = 255
                pixels[index + 1] = 0
                pixels[index + 2] = 0
                pixels[index + 3] = subjectAlpha
            }
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

private final class DependencyRecorderGIFToolKit: GIFToolKit, @unchecked Sendable {
    private let generationResult: GIFGenerationURLResult
    private let lock = NSLock()
    private var generationRequest: GIFGenerationURLRequest?

    init(generationResult: GIFGenerationURLResult) {
        self.generationResult = generationResult
    }

    func generateGIF(_ request: GIFGenerationURLRequest) -> AsyncThrowingStream<GIFGenerationEvent, Error> {
        lock.lock()
        generationRequest = request
        lock.unlock()

        return AsyncThrowingStream { continuation in
            continuation.yield(.preparingFrames(completed: 1, total: 1))
            continuation.yield(.encoding(completed: 1, total: 1))
            continuation.yield(.completed(generationResult))
            continuation.finish()
        }
    }

    func removeBackground(_ request: GIFBackgroundRemovalURLRequest) -> AsyncThrowingStream<GIFBackgroundRemovalEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.processing)
            continuation.yield(
                .completed(
                    .init(
                        imageURL: request.outputImageURL ?? request.inputImageURL,
                        pixelSize: .zero
                    )
                )
            )
            continuation.finish()
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

    func lastGenerationRequest() -> GIFGenerationURLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return generationRequest
    }
}
