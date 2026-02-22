import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers
import Vision

internal protocol GIFEncoding: Sendable {
    func encode(
        cgImages: [CGImage],
        outputURL: URL,
        frameDelay: Double,
        watermarks: [GIFWatermark],
        onProgress: @Sendable (_ completed: Int, _ total: Int) -> Void
    ) throws -> [GIFImage]
}

internal protocol GIFVideoFrameExtracting: Sendable {
    func extractFrames(
        from videoURL: URL,
        policy: GIFFrameExtractionPolicy
    ) async throws -> GIFVideoExtractionOutput
}

internal protocol GIFBackgroundRemoving: Sendable {
    func removeBackground(images: [CGImage]) async throws -> [CGImage]
}

internal protocol GIFPhotoLibraryPersisting: Sendable {
    func save(_ request: GIFSaveURLRequest) async throws -> GIFSaveResult
}

internal protocol GIFTemporaryStorage: Sendable {
    func makeRequestDirectory() throws -> URL
    func cleanup(directory: URL) throws
    func cleanupAll() throws
}

internal protocol GIFRecommendationProviding: Sendable {
    func fetch(_ request: GIFRecommendationURLRequest) async throws -> [GIFRecommendedAsset]
}

internal struct GIFFrameExtractionPolicy: Sendable {
    let sourceFPS: Double?
    let maxResolution: CGFloat
    let maxFrameCount: Int
    let decodeMemoryBudgetBytes: Int

    init(
        sourceFPS: Double?,
        maxResolution: CGFloat,
        maxFrameCount: Int = 150,
        decodeMemoryBudgetBytes: Int = 64 * 1024 * 1024
    ) {
        self.sourceFPS = sourceFPS
        self.maxResolution = maxResolution
        self.maxFrameCount = max(1, maxFrameCount)
        self.decodeMemoryBudgetBytes = max(1, decodeMemoryBudgetBytes)
    }
}

internal struct GIFVideoExtractionOutput: Sendable {
    let frames: [GIFImage]
    let effectiveSourceFPS: Double
    let effectiveMaxResolution: CGFloat
    let estimatedDecodeBytes: Int

    init(
        frames: [GIFImage],
        effectiveSourceFPS: Double,
        effectiveMaxResolution: CGFloat,
        estimatedDecodeBytes: Int
    ) {
        self.frames = frames
        self.effectiveSourceFPS = effectiveSourceFPS
        self.effectiveMaxResolution = effectiveMaxResolution
        self.estimatedDecodeBytes = estimatedDecodeBytes
    }
}

internal actor GIFRequestDirectoryStore {
    struct RequestResources: Sendable {
        let directory: URL
        let managedWatermarkFiles: [URL]
    }

    private var resources: [RequestResources] = []

    func track(directory: URL, managedWatermarkFiles: [URL]) {
        resources.append(
            RequestResources(
                directory: directory,
                managedWatermarkFiles: managedWatermarkFiles
            )
        )
    }

    func popLatest() -> RequestResources? {
        resources.popLast()
    }
}

private enum GIFFrameHandle: Sendable {
    case memory(Data)
    case file(URL)

    func cgImage() throws -> CGImage {
        let data: Data
        switch self {
        case .memory(let inMemoryData):
            data = inMemoryData
        case .file(let url):
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        }
        guard
            let image = GIFImage(data: data),
            let cgImage = image.gifCGImage
        else {
            throw GifError.invalidImageData
        }
        return cgImage
    }
}

internal struct GIFToolKitImpl: GIFToolKit {
    private static let defaultFrameStorageMemoryBudgetBytes = 64 * 1024 * 1024

    private let encoding: any GIFEncoding
    private let videoFrameExtractor: any GIFVideoFrameExtracting
    private let backgroundRemover: any GIFBackgroundRemoving
    private let photoLibrary: any GIFPhotoLibraryPersisting
    private let storage: any GIFTemporaryStorage
    private let recommendationProvider: any GIFRecommendationProviding
    private let frameStorageMemoryBudgetBytes: Int
    private let requestDirectoryStore = GIFRequestDirectoryStore()

    internal init(
        encoding: any GIFEncoding = GIFEncodingLive(),
        videoFrameExtractor: any GIFVideoFrameExtracting = GIFVideoFrameExtractorLive(),
        backgroundRemover: any GIFBackgroundRemoving = GIFBackgroundRemoverLive(),
        photoLibrary: any GIFPhotoLibraryPersisting = GIFPhotoLibraryLive(),
        storage: any GIFTemporaryStorage = GIFTemporaryStorageLive(),
        recommendationProvider: any GIFRecommendationProviding = GIFRecommendationProviderLive(),
        frameStorageMemoryBudgetBytes: Int = GIFToolKitImpl.defaultFrameStorageMemoryBudgetBytes
    ) {
        self.encoding = encoding
        self.videoFrameExtractor = videoFrameExtractor
        self.backgroundRemover = backgroundRemover
        self.photoLibrary = photoLibrary
        self.storage = storage
        self.recommendationProvider = recommendationProvider
        self.frameStorageMemoryBudgetBytes = frameStorageMemoryBudgetBytes
    }

    func generateGIF(_ request: GIFGenerationURLRequest) -> AsyncThrowingStream<GIFGenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await generateGIFResult(request) { event in
                        continuation.yield(event)
                    }
                    continuation.yield(.completed(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func removeBackground(_ request: GIFBackgroundRemovalURLRequest) -> AsyncThrowingStream<GIFBackgroundRemovalEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.processing)
                    let directory = try storage.makeRequestDirectory()
                    await requestDirectoryStore.track(directory: directory, managedWatermarkFiles: [])

                    let outputURL = try makeBackgroundRemovalOutputURL(request: request, directory: directory)
                    guard
                        let image = GIFImage.gifImage(contentsOf: request.inputImageURL),
                        let cgImage = image.gifCGImage
                    else {
                        throw GifError.invalidImageData
                    }

                    let processedImages = try await backgroundRemover.removeBackground(images: [cgImage])
                    guard let processed = processedImages.first else {
                        throw GifError.gifResultNil
                    }
                    let outputImage = GIFImage.gifImage(cgImage: processed)
                    guard let data = outputImage.gifPNGData else {
                        throw GifError.invalidImageData
                    }
                    try data.write(to: outputURL, options: .atomic)

                    continuation.yield(
                        .completed(
                            GIFBackgroundRemovalURLResult(
                                imageURL: outputURL,
                                pixelSize: CGSize(width: processed.width, height: processed.height)
                            )
                        )
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func save(_ request: GIFSaveURLRequest) async throws -> GIFSaveResult {
        try await photoLibrary.save(request)
    }

    func fetchRecommendedAssets(_ request: GIFRecommendationURLRequest) async throws -> [GIFRecommendedAsset] {
        try await recommendationProvider.fetch(request)
    }

    func preheat() async throws {
        guard
            let image = GIFImage.gifExampleImage(),
            let data = image.gifPNGData
        else {
            return
        }

        let preheatDirectory = GIFTemporaryPaths.baseDirectory.appending(path: "Preheat")
        try FileManager.default.createDirectory(at: preheatDirectory, withIntermediateDirectories: true)
        let inputURL = preheatDirectory.appending(path: "\(UUID().uuidString).png")
        try data.write(to: inputURL, options: .atomic)
        defer {
            try? FileManager.default.removeItem(at: inputURL)
        }

        let request = GIFGenerationURLRequest(
            source: .imageFiles([inputURL]),
            options: GIFGenerationOptions(removeBackground: true)
        )

        let stream = generateGIF(request)
        for try await _ in stream {}
        try await cleanup(.requestOnly)
    }

    func cleanup(_ scope: GIFCleanupScope) async throws {
        switch scope {
        case .requestOnly:
            if let resources = await requestDirectoryStore.popLatest() {
                try storage.cleanup(directory: resources.directory)
                for url in resources.managedWatermarkFiles {
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        continue
                    }
                    try FileManager.default.removeItem(at: url)
                }
            }
        case .allTemporaryGIFFiles:
            try storage.cleanupAll()
        }
    }

    private func generateGIFResult(
        _ request: GIFGenerationURLRequest,
        onEvent: @Sendable (GIFGenerationEvent) -> Void
    ) async throws -> GIFGenerationURLResult {
        let start = CFAbsoluteTimeGetCurrent()
        let directory = try storage.makeRequestDirectory()
        let managedWatermarkFiles = managedWatermarkFiles(from: request.options.watermarks)
        await requestDirectoryStore.track(directory: directory, managedWatermarkFiles: managedWatermarkFiles)

        let outputURL = try makeOutputURL(from: request, directory: directory)

        let sourceImages = try await sourceImages(from: request, directory: directory)
        guard !sourceImages.isEmpty else {
            throw GifError.gifResultNil
        }
        onEvent(.preparingFrames(completed: sourceImages.count, total: sourceImages.count))

        let frameHandles = try makeFrameHandlesIfNeeded(from: sourceImages, directory: directory)
        var cgImages: [CGImage]
        if let frameHandles {
            cgImages = try frameHandles.map { try $0.cgImage() }
        } else {
            cgImages = sourceImages.compactMap(\.gifCGImage)
        }
        guard !cgImages.isEmpty else {
            throw GifError.invalidImageData
        }

        if request.options.removeBackground {
            cgImages = try await backgroundRemover.removeBackground(images: cgImages)
        }

        let delay = 1.0 / max(request.options.outputFPS, 1)
        let frames = try encoding.encode(
            cgImages: cgImages,
            outputURL: outputURL,
            frameDelay: delay,
            watermarks: request.options.watermarks,
            onProgress: { completed, total in
                onEvent(.encoding(completed: completed, total: total))
            }
        )

        let duration = CFAbsoluteTimeGetCurrent() - start
        let pixelSize: CGSize
        if let first = frames.first {
            pixelSize = first.size
        } else {
            pixelSize = .zero
        }
        return GIFGenerationURLResult(
            gifURL: outputURL,
            frameCount: frames.count,
            pixelSize: pixelSize,
            duration: duration
        )
    }

    private func makeOutputURL(from request: GIFGenerationURLRequest, directory: URL) throws -> URL {
        if let outputGIFURL = request.outputGIFURL {
            let parent = outputGIFURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            return outputGIFURL
        }
        return directory.appending(path: "\(Int(Date().timeIntervalSince1970)).gif")
    }

    private func makeBackgroundRemovalOutputURL(
        request: GIFBackgroundRemovalURLRequest,
        directory: URL
    ) throws -> URL {
        if let outputImageURL = request.outputImageURL {
            let parent = outputImageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            return outputImageURL
        }
        return directory.appending(path: "background-\(UUID().uuidString).png")
    }

    private func makeFrameHandlesIfNeeded(
        from images: [GIFImage],
        directory: URL
    ) throws -> [GIFFrameHandle]? {
        guard estimatedFrameBytes(for: images) > frameStorageMemoryBudgetBytes else {
            return nil
        }

        var handles: [GIFFrameHandle] = []
        handles.reserveCapacity(images.count)

        var inMemoryBytes = 0
        for (index, image) in images.enumerated() {
            guard let pngData = image.gifPNGData else {
                throw GifError.invalidImageData
            }
            if inMemoryBytes + pngData.count <= frameStorageMemoryBudgetBytes {
                handles.append(.memory(pngData))
                inMemoryBytes += pngData.count
            } else {
                let url = directory.appending(path: "frame-\(index).png")
                try pngData.write(to: url, options: .atomic)
                handles.append(.file(url))
            }
        }
        return handles
    }

    private func estimatedFrameBytes(for images: [GIFImage]) -> Int {
        images.reduce(into: 0) { total, image in
            guard let cgImage = image.gifCGImage else {
                return
            }
            total += cgImage.bytesPerRow * cgImage.height
        }
    }

    private func managedWatermarkFiles(from watermarks: [GIFWatermark]) -> [URL] {
        watermarks.compactMap { watermark in
            switch watermark.content {
            case .imageFile(let url, _):
                return GIFTemporaryPaths.isManagedWatermarkFile(url) ? url : nil
            default:
                return nil
            }
        }
    }

    private func sourceImages(from request: GIFGenerationURLRequest, directory: URL) async throws -> [GIFImage] {
        switch request.source {
        case .imageFiles(let urls, let adjustOrientation):
            var images: [GIFImage] = []
            images.reserveCapacity(urls.count)
            for url in urls {
                guard let image = GIFImage.gifImage(contentsOf: url) else {
                    throw GifError.unableToReadFile
                }
                let oriented = adjustOrientation ? image.adjustOrientation() : image
                images.append(oriented.resize(width: request.options.maxResolution))
            }
            return images
        case .videoFile(let videoURL, let sourceFPS):
            let output = try await videoFrameExtractor.extractFrames(
                from: videoURL,
                policy: GIFFrameExtractionPolicy(
                    sourceFPS: sourceFPS,
                    maxResolution: request.options.maxResolution,
                    maxFrameCount: 150,
                    decodeMemoryBudgetBytes: frameStorageMemoryBudgetBytes
                )
            )
            return output.frames
        case .livePhotoVideoFile(let videoURL, let sourceFPS):
            let output = try await videoFrameExtractor.extractFrames(
                from: videoURL,
                policy: GIFFrameExtractionPolicy(
                    sourceFPS: sourceFPS,
                    maxResolution: request.options.maxResolution,
                    maxFrameCount: 150,
                    decodeMemoryBudgetBytes: frameStorageMemoryBudgetBytes
                )
            )
            return output.frames
        }
    }
}

internal struct GIFEncodingLive: GIFEncoding {
    func encode(
        cgImages: [CGImage],
        outputURL: URL,
        frameDelay: Double,
        watermarks: [GIFWatermark],
        onProgress: @Sendable (_ completed: Int, _ total: Int) -> Void
    ) throws -> [GIFImage] {
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            cgImages.count,
            nil
        ) else {
            throw GifError.unableToCreateOutput
        }

        let fileProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0,
            ],
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)

        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFUnclampedDelayTime as String: frameDelay,
            ],
        ]

        var outputFrames: [GIFImage] = []
        outputFrames.reserveCapacity(cgImages.count)

        for (index, cgImage) in cgImages.enumerated() {
            var frame = GIFImage.gifImage(cgImage: cgImage)
            frame = frame.decorate(watermarks: watermarks)
            guard let finalCGImage = frame.gifCGImage else {
                continue
            }
            outputFrames.append(frame)
            CGImageDestinationAddImage(destination, finalCGImage, frameProperties as CFDictionary)
            onProgress(index + 1, cgImages.count)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw GifError.unknown
        }
        return outputFrames
    }
}

internal struct GIFVideoFrameExtractorLive: GIFVideoFrameExtracting {
    func extractFrames(
        from videoURL: URL,
        policy: GIFFrameExtractionPolicy
    ) async throws -> GIFVideoExtractionOutput {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let seconds = duration.seconds
        guard seconds > 0 else {
            throw GifError.unableToReadFile
        }
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw GifError.unableToReadFile
        }

        let nominalFPS = max(1, try await Double(videoTrack.load(.nominalFrameRate)))
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let transformedSize = naturalSize.applying(preferredTransform)
        let sourceWidth = max(abs(transformedSize.width), 1)
        let sourceHeight = max(abs(transformedSize.height), 1)
        let sourceLongEdge = max(sourceWidth, sourceHeight)

        var effectiveSourceFPS = max(1, policy.sourceFPS ?? nominalFPS)
        let maxFrameCount = max(1, policy.maxFrameCount)
        effectiveSourceFPS = min(effectiveSourceFPS, Double(maxFrameCount) / seconds)
        effectiveSourceFPS = max(1, effectiveSourceFPS)

        let maxLongEdge = max(1, min(policy.maxResolution, sourceLongEdge))
        var effectiveLongEdge = maxLongEdge
        let decodeBudgetBytes = max(1, policy.decodeMemoryBudgetBytes)

        for _ in 0..<12 {
            let frameCount = clampedFrameCount(
                durationSeconds: seconds,
                sourceFPS: effectiveSourceFPS,
                maxFrameCount: maxFrameCount
            )
            let estimatedBytes = estimatedDecodeBytes(
                frameCount: frameCount,
                sourceSize: CGSize(width: sourceWidth, height: sourceHeight),
                effectiveLongEdge: effectiveLongEdge
            )
            if estimatedBytes <= decodeBudgetBytes {
                break
            }

            if effectiveSourceFPS > 6 {
                effectiveSourceFPS = max(6, effectiveSourceFPS * 0.85)
            } else if effectiveLongEdge > 120 {
                effectiveLongEdge = max(120, effectiveLongEdge * 0.9)
            } else {
                break
            }
        }

        let frameCount = clampedFrameCount(
            durationSeconds: seconds,
            sourceFPS: effectiveSourceFPS,
            maxFrameCount: maxFrameCount
        )
        guard frameCount > 0 else {
            throw GifError.gifResultNil
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = .zero
        generator.requestedTimeToleranceBefore = .zero

        var times: [NSValue] = []
        times.reserveCapacity(frameCount)
        let step = seconds / Double(frameCount)
        for index in 0..<frameCount {
            let secondsValue = min(Double(index) * step, max(seconds - 0.001, 0))
            let value = CMTime(seconds: secondsValue, preferredTimescale: 600)
            times.append(NSValue(time: value))
        }

        var images: [GIFImage] = []
        images.reserveCapacity(frameCount)
        for time in times {
            try Task.checkCancellation()
            let cgImage = try generator.copyCGImage(at: time.timeValue, actualTime: nil)
            let resized = GIFImage.gifImage(cgImage: cgImage).resize(width: effectiveLongEdge)
            images.append(resized)
        }
        let estimatedBytes = estimatedDecodeBytes(
            frameCount: frameCount,
            sourceSize: CGSize(width: sourceWidth, height: sourceHeight),
            effectiveLongEdge: effectiveLongEdge
        )
        return GIFVideoExtractionOutput(
            frames: images,
            effectiveSourceFPS: effectiveSourceFPS,
            effectiveMaxResolution: effectiveLongEdge,
            estimatedDecodeBytes: estimatedBytes
        )
    }

    private func clampedFrameCount(
        durationSeconds: Double,
        sourceFPS: Double,
        maxFrameCount: Int
    ) -> Int {
        let calculated = Int((durationSeconds * sourceFPS).rounded(.down))
        return max(1, min(maxFrameCount, calculated))
    }

    private func estimatedDecodeBytes(
        frameCount: Int,
        sourceSize: CGSize,
        effectiveLongEdge: CGFloat
    ) -> Int {
        let sourceLongEdge = max(sourceSize.width, sourceSize.height)
        guard sourceLongEdge > 0 else {
            return 0
        }
        let scale = min(1, effectiveLongEdge / sourceLongEdge)
        let width = max(1, sourceSize.width * scale)
        let height = max(1, sourceSize.height * scale)
        let bytes = Double(frameCount) * Double(width * height * 4)
        return Int(bytes.rounded(.up))
    }
}

internal struct GIFBackgroundRemoverLive: GIFBackgroundRemoving {
    func removeBackground(images: [CGImage]) async throws -> [CGImage] {
        let tasks = images.map { image in
            Task { () throws -> (CGImage, CGRect?) in
                try Task.checkCancellation()
                let processor = ImageBackgroundRemovalProcessor(inputImage: image)
                guard let output = try await processor.process() else {
                    return (image, nil)
                }
                return (output, output.nonTransparentBoundingBox())
            }
        }

        return try await withTaskCancellationHandler {
            var newImages: [CGImage] = []
            var finalRect: CGRect?
            for task in tasks {
                try Task.checkCancellation()
                let (cgImage, rect) = try await task.value
                newImages.append(cgImage)
                if let rect {
                    if let existing = finalRect {
                        finalRect = existing.union(rect)
                    } else {
                        finalRect = rect
                    }
                }
            }
            guard let finalRect else {
                return newImages
            }
            return newImages.cropImages(toRect: finalRect)
        } onCancel: {
            tasks.forEach { $0.cancel() }
        }
    }
}

internal struct GIFPhotoLibraryLive: GIFPhotoLibraryPersisting {
    func save(_ request: GIFSaveURLRequest) async throws -> GIFSaveResult {
        try await AlbumTool.save(request: request)
    }
}

internal struct GIFTemporaryStorageLive: GIFTemporaryStorage {
    private var baseDirectory: URL {
        GIFTemporaryPaths.baseDirectory
    }

    func makeRequestDirectory() throws -> URL {
        try createDirectoryIfNeeded(baseDirectory)
        let requestDirectory = baseDirectory.appending(path: UUID().uuidString)
        try createDirectoryIfNeeded(requestDirectory)
        return requestDirectory
    }

    func cleanup(directory: URL) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return
        }
        try FileManager.default.removeItem(at: directory)
    }

    func cleanupAll() throws {
        guard FileManager.default.fileExists(atPath: baseDirectory.path) else {
            return
        }
        try FileManager.default.removeItem(at: baseDirectory)
    }

    private func createDirectoryIfNeeded(_ directory: URL) throws {
        guard !FileManager.default.fileExists(atPath: directory.path) else {
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

internal struct GIFRecommendationProviderLive: GIFRecommendationProviding {
    func fetch(_ request: GIFRecommendationURLRequest) async throws -> [GIFRecommendedAsset] {
        try FetchPhoto.fetchAssets(
            days: request.days,
            targetSize: request.thumbnailSize,
            outputDirectoryURL: request.outputDirectoryURL
        )
    }
}
