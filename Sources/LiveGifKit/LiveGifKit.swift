//// The Swift Programming Language
//// https://docs.swift.org/swift-book
//
//import Photos
//import UIKit
//import AVFoundation
//
//public struct LiveGifKit {
//        
//    public static let shared = LiveGifKit()
//    
//    public func createGif(images: [CGImage], frameRate: Float) async -> URL? {
//        if images.count == 0 {
//            print("图片为空")
//            return nil
//        }
//        let url = images.createGIF(frameRate: frameRate)
//        return url
//    }
// 
//    
//    public func getFrameImages(livePhoto: PHLivePhoto, fps: Double, callback: @escaping ((([CGImage]) -> Void))) async {
////        let videoUrl = try? await self.livePhotoConvertToVideo(livePhoto: livePhoto)
////        guard let videoUrl = videoUrl else { return }
//////        self.extractFramesFromVideo(videoUrl: videoUrl, fps: fps, callback: callback)
////        do {
////            let images = try await self.extractFramesFromLivePhoto(videoUrl: videoUrl)
////            callback(images)
////        } catch {
////            
////        }
////       
//      
//    }
//    
//    /// 批量移除背景
//    public func removeBgColor(images: [CGImage]) async -> [CGImage] {
//        let tasks = images.map { image in
//            Task { () -> CGImage? in
//                return await image.removeBackground()
//            }
//        }
//        return await withTaskCancellationHandler {
//            var newImages: [CGImage] = []
//            for task in tasks {
//                if let value = await task.value {
//                    newImages.append(value)
//                }
//            }
//            let rect = await newImages.commonBoundingBox()!
//            newImages = newImages.cropImages(toRect: rect)
//            return newImages
//        } onCancel: {
//            tasks.forEach { task in
//                task.cancel()
//            }
//        }
//    }
//    
// 
//    
//    func extractFramesFromLivePhoto(videoUrl: URL) async throws -> [CGImage] {
//     
//        
//        // Process the video file to extract frames
//        let asset = AVAsset(url: videoUrl)
//        guard let assetReader = try? AVAssetReader(asset: asset) else {
//            return []
//        }
//        
//        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
//            return []
//        }
//        
//        let readerOutputSettings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB)]
//        let assetReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerOutputSettings)
//        
//        assetReader.add(assetReaderOutput)
//        assetReader.startReading()
//        
//        // Get the preferred transform
//        let preferredTransform = try! await videoTrack.load(.preferredTransform)
//        
//        var extractedImages = [CGImage]()
//        
//        while let sampleBuffer = assetReaderOutput.copyNextSampleBuffer() {
//            if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
//                // Convert the image buffer to a UIImage
//                let ciImage = CIImage(cvPixelBuffer: imageBuffer)
//                let context = CIContext()
//                if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
////                    var uiImage = UIImage(cgImage: cgImage, scale: 1, orientation: .down)
//                    
////                    if let resizedWidth {
////                        uiImage = uiImage.resize(width: resizedWidth)
////                    }
////                    
////                    if removingBackground {
////                        uiImage = await uiImage.removeBackground()!
////                    }
//                    
//                    extractedImages.append(cgImage)
//                }
//            }
//        }
//        
//        // Clean up: Remove the temporary video file
//        try? FileManager.default.removeItem(at: videoUrl)
//        
////        let rect = await extractedImages.commonBoundingBox()!
////        extractedImages = extractedImages.cropImages(toRect: rect)
//        
//        return extractedImages
//    }
//    
//    /// 提取视频的帧
//    func extractFramesFromVideo(videoUrl: URL, fps: Double, callback: @escaping ((([CGImage]) -> Void))) {
//        var images: [CGImage] = []
//        DispatchQueue.global(qos: .default).async {
//            
//            let asset = AVURLAsset(url: videoUrl)
//            let generator = AVAssetImageGenerator(asset: asset)
// 
//            generator.appliesPreferredTrackTransform = true
////            generator.maximumSize = CGSize(width: 640, height: 480)
//            let frameCount = Int(asset.duration.seconds * fps)
//
//            var frameForTimes = [CMTime]()
//            for i in 0..<frameCount {
//                frameForTimes.append(CMTime(seconds: (1 / fps) * Double(i), preferredTimescale: .video))
//            }
//     
//            generator.generateCGImagesAsynchronously(forTimePoints: frameForTimes) { requestedTime, image, time2, result, error in
//                if let image = image, error == nil {
//                    images.append(image)
//                 
//                }
//                if (Int(requestedTime.value) == Int(frameForTimes.last?.value ?? 0)) {
//                    try? FileManager.default.removeItem(at: videoUrl)
//                    DispatchQueue.main.async {
//                        callback(images)
//                    }
//                }
//            }
//        }
//    }
//}
//
//extension CMTimeScale {
//    static var video: Int32 = 600 // 推荐
//}
//
//extension AVAssetImageGenerator {
//    func generateCGImagesAsynchronously(forTimePoints timePoints: [CMTime], completionHandler: @escaping AVAssetImageGeneratorCompletionHandler) {
//        let times = timePoints.map { NSValue(time: $0) }
//        print("总数: \(times.count)")
//        generateCGImagesAsynchronously(forTimes: times, completionHandler: completionHandler)
//    }
//}
