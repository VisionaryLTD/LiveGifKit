import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers
import Vision
#if canImport(PhotosUI)
import PhotosUI
#endif

internal protocol GIFEncoding: Sendable {
    func encode(
        cgImages: [CGImage],
        outputURL: URL,
        frameDelay: Double,
        watermarks: [GIFWatermark]
    ) throws -> [GIFImage]
}

internal protocol GIFVideoFrameExtracting: Sendable {
    func extractFrames(
        from videoURL: URL,
        sourceFPS: Double?,
        maxResolution: CGFloat
    ) async throws -> [GIFImage]
}

internal protocol GIFBackgroundRemoving: Sendable {
    func removeBackground(images: [CGImage]) async throws -> [CGImage]
}

internal protocol GIFPhotoLibraryPersisting: Sendable {
    func save(_ request: GIFSaveRequest) async throws -> GIFSaveResult
}

internal protocol GIFTemporaryStorage: Sendable {
    func makeRequestDirectory() throws -> URL
    func cleanup(directory: URL) throws
    func cleanupAll() throws
}

internal protocol GIFRecommendationProviding: Sendable {
    @MainActor
    func fetch(_ request: GIFRecommendationRequest) async throws -> [GIFImage]
}

internal actor GIFRequestDirectoryStore {
    private var directories: [URL] = []

    func track(_ directory: URL) {
        directories.append(directory)
    }

    func popLatest() -> URL? {
        directories.popLast()
    }
}

internal struct GIFToolKitImpl: GIFToolKit {
    private let encoding: any GIFEncoding
    private let videoFrameExtractor: any GIFVideoFrameExtracting
    private let backgroundRemover: any GIFBackgroundRemoving
    private let photoLibrary: any GIFPhotoLibraryPersisting
    private let storage: any GIFTemporaryStorage
    private let recommendationProvider: any GIFRecommendationProviding
    private let requestDirectoryStore = GIFRequestDirectoryStore()

    internal init(
        encoding: any GIFEncoding = GIFEncodingLive(),
        videoFrameExtractor: any GIFVideoFrameExtracting = GIFVideoFrameExtractorLive(),
        backgroundRemover: any GIFBackgroundRemoving = GIFBackgroundRemoverLive(),
        photoLibrary: any GIFPhotoLibraryPersisting = GIFPhotoLibraryLive(),
        storage: any GIFTemporaryStorage = GIFTemporaryStorageLive(),
        recommendationProvider: any GIFRecommendationProviding = GIFRecommendationProviderLive()
    ) {
        self.encoding = encoding
        self.videoFrameExtractor = videoFrameExtractor
        self.backgroundRemover = backgroundRemover
        self.photoLibrary = photoLibrary
        self.storage = storage
        self.recommendationProvider = recommendationProvider
    }

    func generateGIF(_ request: GIFGenerationRequest) async throws -> GIFGenerationResult {
        let start = CFAbsoluteTimeGetCurrent()
        let directory = try storage.makeRequestDirectory()
        await requestDirectoryStore.track(directory)
        let outputURL = directory.appending(path: "\(Int(Date().timeIntervalSince1970)).gif")

        let sourceImages = try await sourceImages(from: request, directory: directory)
        let originalFrames = request.options.includeOriginalFrames ? sourceImages : []
        guard !sourceImages.isEmpty else {
            throw GifError.gifResultNil
        }

        var cgImages = sourceImages.compactMap(\.gifCGImage)
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
            watermarks: request.options.watermarks
        )

        let result = GIFGenerationResult(fileURL: outputURL, frames: frames, originalFrames: originalFrames)
        #if DEBUG
        _ = CFAbsoluteTimeGetCurrent() - start
        #endif
        return result
    }

    @MainActor
    func removeBackground(from image: GIFImage) async throws -> GIFImage {
        guard let cgImage = image.gifCGImage else {
            throw GifError.invalidImageData
        }
        guard let processed = try await ImageBackgroundRemovalProcessor(inputImage: cgImage).process() else {
            throw GifError.unableToRemoveBackground
        }
        return GIFImage.gifImage(cgImage: processed)
    }

    func save(_ request: GIFSaveRequest) async throws -> GIFSaveResult {
        try await photoLibrary.save(request)
    }

    @MainActor
    func fetchRecommendedImages(_ request: GIFRecommendationRequest) async throws -> [GIFImage] {
        try await recommendationProvider.fetch(request)
    }

    func preheat() async throws {
        guard let image = GIFImage.gifExampleImage() else {
            return
        }
        let request = GIFGenerationRequest(
            source: .images([image]),
            options: GIFGenerationOptions(removeBackground: true)
        )
        _ = try await generateGIF(request)
        try await cleanup(.requestOnly)
    }

    func cleanup(_ scope: GIFCleanupScope) async throws {
        switch scope {
        case .requestOnly:
            if let directory = await requestDirectoryStore.popLatest() {
                try storage.cleanup(directory: directory)
            }
        case .allTemporaryGIFFiles:
            try storage.cleanupAll()
        }
    }

    private func sourceImages(from request: GIFGenerationRequest, directory: URL) async throws -> [GIFImage] {
        switch request.source {
        case .images(let images, let adjustOrientation):
            var normalized = images
            if adjustOrientation {
                normalized = normalized.map { $0.adjustOrientation() }
            }
            return normalized.map { $0.resize(width: request.options.maxResolution) }
        case .video(let videoURL, let sourceFPS):
            return try await videoFrameExtractor.extractFrames(
                from: videoURL,
                sourceFPS: sourceFPS,
                maxResolution: request.options.maxResolution
            )
        #if canImport(PhotosUI)
        case .livePhoto(let livePhoto, let sourceFPS):
            let videoURL = try await Self.extractVideoURL(from: livePhoto, tempDirectory: directory)
            return try await videoFrameExtractor.extractFrames(
                from: videoURL,
                sourceFPS: sourceFPS,
                maxResolution: request.options.maxResolution
            )
        #endif
        }
    }
}

internal struct GIFEncodingLive: GIFEncoding {
    func encode(
        cgImages: [CGImage],
        outputURL: URL,
        frameDelay: Double,
        watermarks: [GIFWatermark]
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

        for cgImage in cgImages {
            var frame = GIFImage.gifImage(cgImage: cgImage)
            frame = frame.decorate(watermarks: watermarks)
            guard let finalCGImage = frame.gifCGImage else {
                continue
            }
            outputFrames.append(frame)
            CGImageDestinationAddImage(destination, finalCGImage, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw GifError.unknown
        }
        return outputFrames
    }
}

extension GIFToolKitImpl {
    #if canImport(PhotosUI)
    static func extractVideoURL(from livePhoto: PHLivePhoto, tempDirectory: URL) async throws -> URL {
        let resources = PHAssetResource.assetResources(for: livePhoto)
        guard let videoResource = resources.first(where: { $0.type == .pairedVideo }) else {
            throw GifError.unableToFindvideoUrl
        }

        let videoURL = tempDirectory.appendingPathComponent(videoResource.originalFilename)
        try await PHAssetResourceManager.default().writeData(
            for: videoResource,
            toFile: videoURL,
            options: nil
        )
        return videoURL
    }
    #endif
}

internal struct GIFVideoFrameExtractorLive: GIFVideoFrameExtracting {
    func extractFrames(
        from videoURL: URL,
        sourceFPS: Double?,
        maxResolution: CGFloat
    ) async throws -> [GIFImage] {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let seconds = duration.seconds
        guard seconds > 0 else {
            throw GifError.unableToReadFile
        }
        let videoTrack = try await asset.loadTracks(withMediaType: .video).first
        let nominalFPS = try await Double(videoTrack?.load(.nominalFrameRate) ?? 0)
        let extractionFPS = max(1, sourceFPS ?? nominalFPS)

        let frameCount = min(Int(seconds * extractionFPS), 150)
        if frameCount == 0 {
            throw GifError.gifResultNil
        }
        if frameCount >= 150 {
            throw GifError.tooManyFrames
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = .zero
        generator.requestedTimeToleranceBefore = .zero

        var times: [NSValue] = []
        times.reserveCapacity(frameCount)
        let step = 1.0 / extractionFPS
        for index in 0..<frameCount {
            let value = CMTime(seconds: Double(index) * step, preferredTimescale: 600)
            times.append(NSValue(time: value))
        }

        var images: [GIFImage] = []
        images.reserveCapacity(frameCount)
        for time in times {
            try Task.checkCancellation()
            let cgImage = try generator.copyCGImage(at: time.timeValue, actualTime: nil)
            let resized = GIFImage.gifImage(cgImage: cgImage).resize(width: maxResolution)
            images.append(resized)
        }
        return images
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
    func save(_ request: GIFSaveRequest) async throws -> GIFSaveResult {
        try await AlbumTool.save(request: request)
    }
}

internal struct GIFTemporaryStorageLive: GIFTemporaryStorage {
    private var baseDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "GIF")
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
    @MainActor
    func fetch(_ request: GIFRecommendationRequest) async throws -> [GIFImage] {
        FetchPhoto.fetch(days: request.days, targetSize: request.thumbnailSize)
    }
}
