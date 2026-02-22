import LiveGifKit
import SwiftUI

struct GIFFrameLoopPreview: View {
    let frameURLs: [URL]
    let fps: Double
    var fallbackImageURL: URL?

    @State private var currentFrameIndex = 0

    var body: some View {
        Group {
            if let image = displayImage {
                image
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
        .task(id: taskID) {
            await runFrameLoop()
        }
    }

    private var displayImage: Image? {
        if let frameURL = currentFrameURL, let frame = platformImage(at: frameURL) {
            #if canImport(UIKit)
            return Image(uiImage: frame)
            #else
            return Image(nsImage: frame)
            #endif
        }

        guard let fallbackImageURL, let fallback = platformImage(at: fallbackImageURL) else {
            return nil
        }
        #if canImport(UIKit)
        return Image(uiImage: fallback)
        #else
        return Image(nsImage: fallback)
        #endif
    }

    private var currentFrameURL: URL? {
        guard !frameURLs.isEmpty else {
            return nil
        }
        let safeIndex = min(max(currentFrameIndex, 0), frameURLs.count - 1)
        return frameURLs[safeIndex]
    }

    private var taskID: TaskID {
        TaskID(
            firstPath: frameURLs.first?.path,
            lastPath: frameURLs.last?.path,
            count: frameURLs.count,
            fps: Int((fps * 1000).rounded())
        )
    }

    private func runFrameLoop() async {
        guard !frameURLs.isEmpty else {
            currentFrameIndex = 0
            return
        }

        if currentFrameIndex >= frameURLs.count {
            currentFrameIndex = 0
        }

        guard frameURLs.count > 1 else {
            return
        }

        let delay = max(1.0 / max(fps, 1), 0.01)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else {
                return
            }
            currentFrameIndex = (currentFrameIndex + 1) % frameURLs.count
        }
    }

    private func platformImage(at url: URL) -> GIFImage? {
        let cacheKey = url.standardizedFileURL.path as NSString
        if let cached = Self.imageCache.object(forKey: cacheKey) {
            return cached
        }

        let image: GIFImage?
        #if canImport(UIKit)
        image = GIFImage(contentsOfFile: url.path)
        #else
        image = GIFImage(contentsOf: url)
        #endif

        if let image {
            Self.imageCache.setObject(image, forKey: cacheKey, cost: imageCacheCost(image))
        }
        return image
    }

    private func imageCacheCost(_ image: GIFImage) -> Int {
        Int(image.size.width * image.size.height * 4)
    }

    private static let imageCache: NSCache<NSString, GIFImage> = {
        let cache = NSCache<NSString, GIFImage>()
        cache.countLimit = 24
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    private struct TaskID: Hashable {
        let firstPath: String?
        let lastPath: String?
        let count: Int
        let fps: Int
    }
}
