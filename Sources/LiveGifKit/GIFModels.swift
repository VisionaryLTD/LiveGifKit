import CoreGraphics
import Foundation
import Photos
#if canImport(PhotosUI)
import PhotosUI
#endif

public struct GIFGenerationRequest: @unchecked Sendable {
    public var source: GIFGenerationSource
    public var options: GIFGenerationOptions

    public init(
        source: GIFGenerationSource,
        options: GIFGenerationOptions = GIFGenerationOptions()
    ) {
        self.source = source
        self.options = options
    }
}

public enum GIFGenerationSource: @unchecked Sendable {
    #if canImport(PhotosUI)
    case livePhoto(PHLivePhoto, sourceFPS: Double = 30)
    #endif
    case images([GIFImage], adjustOrientation: Bool = false)
    case video(URL, sourceFPS: Double? = nil)
}

public struct GIFGenerationOptions: @unchecked Sendable {
    public var outputFPS: Double
    public var maxResolution: CGFloat
    public var removeBackground: Bool
    public var includeOriginalFrames: Bool
    public var watermarks: [GIFWatermark]

    public init(
        outputFPS: Double = 30,
        maxResolution: CGFloat = 500,
        removeBackground: Bool = false,
        includeOriginalFrames: Bool = false,
        watermarks: [GIFWatermark] = []
    ) {
        self.outputFPS = outputFPS
        self.maxResolution = maxResolution
        self.removeBackground = removeBackground
        self.includeOriginalFrames = includeOriginalFrames
        self.watermarks = watermarks
    }
}

public struct GIFGenerationResult: @unchecked Sendable {
    public let fileURL: URL
    public let frames: [GIFImage]
    public let originalFrames: [GIFImage]

    public init(fileURL: URL, frames: [GIFImage], originalFrames: [GIFImage] = []) {
        self.fileURL = fileURL
        self.frames = frames
        self.originalFrames = originalFrames
    }

    public var data: Data? {
        try? Data(contentsOf: fileURL)
    }
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

public struct GIFSaveRequest: @unchecked Sendable {
    public var payload: GIFSavePayload
    public var destination: GIFSaveDestination

    public init(
        payload: GIFSavePayload,
        destination: GIFSaveDestination = .photoLibrary(albumName: "LifeStickers")
    ) {
        self.payload = payload
        self.destination = destination
    }
}

public enum GIFSavePayload: @unchecked Sendable {
    case fileURL(URL)
    case image(GIFImage)
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

public struct GIFRecommendationRequest: Sendable {
    public var days: Int
    public var thumbnailSize: CGSize

    public init(days: Int = 30, thumbnailSize: CGSize = CGSize(width: 50, height: 50)) {
        self.days = days
        self.thumbnailSize = thumbnailSize
    }
}

public enum GIFCleanupScope: Sendable {
    case requestOnly
    case allTemporaryGIFFiles
}
