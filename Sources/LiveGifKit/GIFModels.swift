import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct GIFGenerationURLRequest: Sendable {
    public var source: GIFGenerationURLSource
    public var options: GIFGenerationOptions
    public var outputGIFURL: URL?

    public init(
        source: GIFGenerationURLSource,
        options: GIFGenerationOptions = GIFGenerationOptions(),
        outputGIFURL: URL? = nil
    ) {
        self.source = source
        self.options = options
        self.outputGIFURL = outputGIFURL
    }
}

public enum GIFGenerationURLSource: Sendable {
    case imageFiles([URL], adjustOrientation: Bool = false)
    case videoFile(URL, sourceFPS: Double? = nil)
    case livePhotoVideoFile(URL, sourceFPS: Double = 30)
}

public struct GIFGenerationOptions: @unchecked Sendable {
    public var outputFPS: Double
    public var maxResolution: CGFloat
    public var removeBackground: Bool
    public var watermarks: [GIFWatermark]

    public init(
        outputFPS: Double = 30,
        maxResolution: CGFloat = 500,
        removeBackground: Bool = false,
        watermarks: [GIFWatermark] = []
    ) {
        self.outputFPS = outputFPS
        self.maxResolution = maxResolution
        self.removeBackground = removeBackground
        self.watermarks = watermarks
    }
}

public struct GIFGenerationURLResult: Sendable {
    public let gifURL: URL
    public let frameCount: Int
    public let pixelSize: CGSize
    public let duration: TimeInterval

    public init(gifURL: URL, frameCount: Int, pixelSize: CGSize, duration: TimeInterval) {
        self.gifURL = gifURL
        self.frameCount = frameCount
        self.pixelSize = pixelSize
        self.duration = duration
    }

    public var data: Data? {
        try? Data(contentsOf: gifURL)
    }
}

public enum GIFGenerationEvent: Sendable {
    case preparingFrames(completed: Int, total: Int?)
    case encoding(completed: Int, total: Int?)
    case completed(GIFGenerationURLResult)
}

public struct GIFBackgroundRemovalURLRequest: Sendable {
    public var inputImageURL: URL
    public var outputImageURL: URL?

    public init(inputImageURL: URL, outputImageURL: URL? = nil) {
        self.inputImageURL = inputImageURL
        self.outputImageURL = outputImageURL
    }
}

public struct GIFBackgroundRemovalURLResult: Sendable {
    public let imageURL: URL
    public let pixelSize: CGSize

    public init(imageURL: URL, pixelSize: CGSize) {
        self.imageURL = imageURL
        self.pixelSize = pixelSize
    }
}

public enum GIFBackgroundRemovalEvent: Sendable {
    case processing
    case completed(GIFBackgroundRemovalURLResult)
}

public struct GIFWatermark: @unchecked Sendable {
    public enum Content: @unchecked Sendable {
        case text(
            String,
            font: PlatformFont = .boldSystemFont(ofSize: 62),
            textColor: PlatformColor = .red,
            backgroundColor: PlatformColor = .clear
        )
        case attributedText(NSAttributedString)
        case imageFile(URL, width: CGFloat = 60)

        @MainActor
        public static func image(_ image: GIFImage, width: CGFloat = 60) throws -> Self {
            try makeImageFile(image, width: width)
        }

        static func makeImageFile(_ image: GIFImage, width: CGFloat) throws -> Self {
            guard let data = image.gifPNGData else {
                throw GifError.invalidImageData
            }
            let directory = GIFTemporaryPaths.watermarkDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appending(path: "\(UUID().uuidString).png")
            try data.write(to: fileURL, options: .atomic)
            return .imageFile(fileURL, width: width)
        }
    }

    public var content: Content
    public var position: GIFWatermarkPosition
    public var offset: CGPoint
    public var origin: CGPoint?

    public init(
        content: Content,
        position: GIFWatermarkPosition = .center,
        offset: CGPoint = CGPoint(x: 8, y: 8),
        origin: CGPoint? = nil
    ) {
        self.content = content
        self.position = position
        self.offset = offset
        self.origin = origin
    }
}

public enum GIFWatermarkPosition: String, CaseIterable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case center
}

public struct GIFSaveURLRequest: Sendable {
    public var payload: GIFSaveURLPayload
    public var destination: GIFSaveDestination

    public init(
        payload: GIFSaveURLPayload,
        destination: GIFSaveDestination = .photoLibrary(albumName: "LifeStickers")
    ) {
        self.payload = payload
        self.destination = destination
    }
}

public enum GIFSaveURLPayload: Sendable {
    case fileURL(URL)
}

public enum GIFSaveDestination: Sendable {
    case photoLibrary(albumName: String)
}

public struct GIFSaveResult: Sendable {
    public let localIdentifier: String?

    public init(localIdentifier: String?) {
        self.localIdentifier = localIdentifier
    }
}

public struct GIFRecommendationURLRequest: Sendable {
    public var days: Int
    public var thumbnailSize: CGSize
    public var outputDirectoryURL: URL?

    public init(
        days: Int = 30,
        thumbnailSize: CGSize = CGSize(width: 50, height: 50),
        outputDirectoryURL: URL? = nil
    ) {
        self.days = days
        self.thumbnailSize = thumbnailSize
        self.outputDirectoryURL = outputDirectoryURL
    }
}

public struct GIFRecommendedAsset: Sendable {
    public var assetLocalIdentifier: String?
    public var thumbnailURL: URL

    public init(assetLocalIdentifier: String?, thumbnailURL: URL) {
        self.assetLocalIdentifier = assetLocalIdentifier
        self.thumbnailURL = thumbnailURL
    }
}

public enum GIFCleanupScope: Sendable {
    case requestOnly
    case allTemporaryGIFFiles
}
