// The Swift Programming Language
// https://docs.swift.org/swift-book

import Photos
import UIKit
import AVFoundation

public struct LiveGifKit {
        
    public static let shared = LiveGifKit()
    
    public func createGif(images: [CGImage], frameRate: Float) async -> URL? {
        if images.count == 0 {
            print("图片为空")
            return nil
        }
        let url = images.createGIF(frameRate: frameRate)
        return url
    }
    
    public func getFrameImages(livePhoto: PHLivePhoto, fps: Double, callback: @escaping ((([CGImage]) -> Void))) async {
        let videoUrl = try? await self.livePhotoConvertToVideo(livePhoto: livePhoto)
        guard let videoUrl = videoUrl else { return }
        self.extractFramesFromVideo(videoUrl: videoUrl, fps: fps, callback: callback)
      
    }
    
    /// 批量移除背景
    public func removeBgColor(images: [CGImage]) async -> [CGImage] {
        let tasks = images.map { image in
            Task { () -> CGImage? in
                return await image.removeBackground()
            }
        }
        return await withTaskCancellationHandler {
            var newImages: [CGImage] = []
            for task in tasks {
                if let value = await task.value {
                    newImages.append(value)
                }
            }
            let rect = await newImages.commonBoundingBox()!
            newImages = newImages.cropImages(toRect: rect)
            return newImages
        } onCancel: {
            tasks.forEach { task in
                task.cancel()
            }
        }
    }
    
    /// 转成视频
    func livePhotoConvertToVideo(livePhoto: PHLivePhoto) async throws -> URL? {
        let resources = PHAssetResource.assetResources(for: livePhoto)
        guard let videoResource = resources.first(where: { $0.type == .pairedVideo }) else {
            return nil
        }
        
        let videoDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString)
        
        try? self.ensureDirectoryExists(at: videoDir)
        
        let videoURL = videoDir.appendingPathComponent(videoResource.originalFilename)
        do {
            try await PHAssetResourceManager.default().writeData(for: videoResource, toFile: videoURL, options: nil)
        } catch {
            print("Error writing video resource to temporary file: \(error)")
            throw error
        }
        
        return videoURL
    }
    
    /// 提取视频的帧
    func extractFramesFromVideo(videoUrl: URL, fps: Double, callback: @escaping ((([CGImage]) -> Void))) {
        var images: [CGImage] = []
        DispatchQueue.global(qos: .default).async {
            
            let asset = AVURLAsset(url: videoUrl)
            let generator = AVAssetImageGenerator(asset: asset)
 
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 480)
            let frameCount = Int(asset.duration.seconds * fps)

            var frameForTimes = [CMTime]()
            for i in 0..<frameCount {
                frameForTimes.append(CMTime(seconds: (1 / fps) * Double(i), preferredTimescale: .video))
            }
     
            generator.generateCGImagesAsynchronously(forTimePoints: frameForTimes) { requestedTime, image, time2, result, error in
                if let image = image, error == nil {
                    images.append(image)
                 
                }
                if (Int(requestedTime.value) == Int(frameForTimes.last?.value ?? 0)) {
                    try? FileManager.default.removeItem(at: videoUrl)
                    DispatchQueue.main.async {
                        callback(images)
                    }
                }
            }
        }
    }
   
    
    
    func ensureDirectoryExists(at url: URL) throws {
        let fileManager = FileManager.default

        // Check if the directory already exists
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            if !isDirectory.boolValue {
                // The path exists but it's not a directory - handle this situation as needed
                throw NSError(domain: "The path exists but is not a directory", code: -1, userInfo: nil)
            }
            // Directory already exists, no further action needed
        } else {
            // The directory does not exist, create it
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }

}
extension CMTimeScale {
    static var video: Int32 = 600 // 推荐
}
extension AVAssetImageGenerator {
    func generateCGImagesAsynchronously(forTimePoints timePoints: [CMTime], completionHandler: @escaping AVAssetImageGeneratorCompletionHandler) {
        let times = timePoints.map { NSValue(time: $0) }
        print("总数: \(times.count)")
        generateCGImagesAsynchronously(forTimes: times, completionHandler: completionHandler)
    }
}
