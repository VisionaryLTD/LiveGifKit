import Dependencies
@testable import LiveGifKit
import Testing
import CoreGraphics
import Foundation

@Suite("GIFToolKit API")
struct GIFToolKitTests {
    @Test("Default test dependency is unimplemented")
    @MainActor
    func defaultDependencyThrows() async throws {
        @Dependency(\.gifToolKit) var gifToolKit
        await #expect(throws: GIFError.self) {
            _ = try await gifToolKit.fetchRecommendedImages(.init())
        }
    }

    @Test("LiveGifTool compatibility wrapper forwards generation request")
    @available(*, deprecated)
    func liveGifToolForwardsGeneration() async throws {
        let recorder = RecordingGIFToolKit()
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "compat-wrapper.gif")
        recorder.setGenerationResult(.init(fileURL: outputURL, frames: [makeImage()]))

        let legacyResult = try await withDependencies {
            $0.gifToolKit = recorder
        } operation: {
            let tool = LiveGifTool()
            let parameter = GifToolParameter(
                data: .images(frames: [makeImage()], adjustOrientation: true),
                gifFPS: 22,
                imageDecorates: [],
                maxResolution: 321,
                removeBg: true,
                isReturnOriginFrames: true
            )
            return try await tool.createGif(parameter: parameter)
        }

        #expect(legacyResult.url == outputURL)
        #expect(legacyResult.frames.count == 1)

        let captured = recorder.generationRequest()
        #expect(captured?.options.outputFPS == 22)
        #expect(captured?.options.maxResolution == 321)
        #expect(captured?.options.removeBackground == true)
        #expect(captured?.options.includeOriginalFrames == true)
    }

    @Test("LiveGifTool compatibility wrapper forwards save request")
    @available(*, deprecated)
    func liveGifToolForwardsSave() async throws {
        let recorder = RecordingGIFToolKit()
        let saveURL = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "save-me.gif")

        _ = try await withDependencies {
            $0.gifToolKit = recorder
        } operation: {
            let tool = LiveGifTool()
            try await tool.save(method: .url(saveURL))
        }

        let captured = recorder.saveRequest()
        switch captured?.payload {
        case .fileURL(let url):
            #expect(url == saveURL)
        default:
            Issue.record("Expected .fileURL payload")
        }
    }

    @Test("LiveGifTool compatibility wrapper forwards background removal")
    @available(*, deprecated)
    @MainActor
    func liveGifToolForwardsBackgroundRemoval() async throws {
        let recorder = RecordingGIFToolKit()
        recorder.setBackgroundRemovalResult(makeImage())

        let outputData = try await withDependencies {
            $0.gifToolKit = recorder
        } operation: {
            let tool = LiveGifTool()
            return try await tool.removeBackground(uiImage: makeImage())
        }

        #expect(outputData != nil)
        #expect(recorder.removeBackgroundCalls() == 1)
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

    private func makeImage() -> GIFImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let width = 2
        let height = 2
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = 255
            pixels[index + 1] = 0
            pixels[index + 2] = 0
            pixels[index + 3] = 255
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let cgImage = CGImage(
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
        return GIFImage.gifImage(cgImage: cgImage)
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

        let minX = Int(subjectRect.minX)
        let maxX = Int(subjectRect.maxX)
        let minY = Int(subjectRect.minY)
        let maxY = Int(subjectRect.maxY)
        for y in minY..<maxY {
            for x in minX..<maxX {
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

final class RecordingGIFToolKit: GIFToolKit, @unchecked Sendable {
    private var lastGenerationRequest: GIFGenerationRequest?
    private var lastSaveRequest: GIFSaveRequest?
    private var removeBackgroundCallCount = 0
    private var generationResult = GIFGenerationResult(
        fileURL: URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "result.gif"),
        frames: []
    )
    private var backgroundRemovalResult: GIFImage?

    func setGenerationResult(_ result: GIFGenerationResult) {
        generationResult = result
    }

    func setBackgroundRemovalResult(_ image: GIFImage) {
        backgroundRemovalResult = image
    }

    func generateGIF(_ request: GIFGenerationRequest) async throws -> GIFGenerationResult {
        lastGenerationRequest = request
        return generationResult
    }

    @MainActor
    func removeBackground(from image: GIFImage) async throws -> GIFImage {
        removeBackgroundCallCount += 1
        return backgroundRemovalResult ?? image
    }

    func save(_ request: GIFSaveRequest) async throws -> GIFSaveResult {
        lastSaveRequest = request
        return GIFSaveResult(localIdentifier: "saved")
    }

    @MainActor
    func fetchRecommendedImages(_ request: GIFRecommendationRequest) async throws -> [GIFImage] {
        []
    }

    func preheat() async throws {}

    func cleanup(_ scope: GIFCleanupScope) async throws {}

    func generationRequest() -> GIFGenerationRequest? {
        return lastGenerationRequest
    }

    func saveRequest() -> GIFSaveRequest? {
        return lastSaveRequest
    }

    func removeBackgroundCalls() -> Int {
        return removeBackgroundCallCount
    }
}
