import Foundation

/// 生成的GIF
@available(*, deprecated, message: "Use GIFGenerationResult.")
public struct GifResult {
    public let url: URL
    public let frames: [GIFImage]
    public var originFrames: [GIFImage] = []
    public var data: Data? {
        return try? Data(contentsOf: url)
    }
    
#if DEBUG
    public var totalTime: Double = 0
#endif
}
