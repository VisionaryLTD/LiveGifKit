//
//  URLExtension.swift
//
//
//  Created by tangxiaojun on 2023/12/11.
//
import UIKit
import Foundation
import AVFoundation
import Foundation
import UniformTypeIdentifiers
import CoreText

extension URL {
    /// 创建GIF
    func convertToGIF(maxResolution: CGFloat? = 300, livePhotoFPS: CGFloat, gifFPS: CGFloat, gifDirURL: URL, watermark: WatermarkConfig?) async throws -> GifResult {
         
        let asset = AVURLAsset(url: self)
//        print("视频方向； \(getVideoPreviewImageOrientation(for: self))")
        guard let reader = try? AVAssetReader(asset: asset) else {
            throw GifError.unableToReadFile
        }
        
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            throw GifError.unableToFindTrack
        }
        
        var videoSize = try await videoTrack.load(.naturalSize).applying(videoTrack.load(.preferredTransform))
        let videoTransform = try await videoTrack.load(.preferredTransform)
        let videoWidth = abs(videoSize.width * videoTransform.a) + abs(videoSize.height * videoTransform.c)
        let videoHeight = abs(videoSize.width * videoTransform.b) + abs(videoSize.height * videoTransform.d)
        let videoFrame = CGRect(x: 0, y: 0, width: videoWidth, height: videoHeight)
        let aspectRatio = videoFrame.width / videoFrame.height
        videoSize = videoFrame.size
        let resultingSize: CGSize
        
        if let maxResolution {
            if videoSize.width > videoSize.height {
                let cappedWidth = round(min(maxResolution, videoSize.width))
                resultingSize = CGSize(width: cappedWidth, height: round(cappedWidth / aspectRatio))
            } else {
                let cappedHeight = round(min(maxResolution, videoSize.height))
                resultingSize = CGSize(width: round(cappedHeight * aspectRatio), height: cappedHeight)
            }
        } else {
            resultingSize = CGSize(width: videoSize.width, height: videoSize.height)
        }
        print("视频大小: \(resultingSize)")
        let duration: CGFloat = try await CGFloat(asset.load(.duration).seconds)
        let nominalFrameRate = try await CGFloat(videoTrack.load(.nominalFrameRate))
        let nominalTotalFrames = Int(round(duration * nominalFrameRate))
        
        // In order to convert from, say 30 FPS to 20, we'd need to remove 1/3 of the frames, this applies that math and decides which frames to remove/not process
        
        let framesToRemove = calculateFramesToRemove(desiredFrameRate: livePhotoFPS, nominalFrameRate: nominalFrameRate, nominalTotalFrames: nominalTotalFrames)
        
        let totalFrames = nominalTotalFrames - framesToRemove.count
        print("移除的帧个数； \(framesToRemove.count)  总帧的个数: \(totalFrames)")
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: resultingSize.width,
            kCVPixelBufferHeightKey as String: resultingSize.height
        ]
        
        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        
        reader.add(readerOutput)
        reader.startReading()
        
        // An array where each index corresponds to the delay for that frame in seconds.
        // Note that since it's regarding frames, the first frame would be the 0th index in the array.
        let frameDelays = calculateFrameDelays(desiredFrameRate: livePhotoFPS, nominalFrameRate: nominalFrameRate, totalFrames: totalFrames)
        
        // Since there can be a disjoint mapping between frame delays
        // and the frames in the video/pixel buffer (if we're lowering
        // the
        // frame rate) rather than messing around with a complicated mapping,
        // just have a stack where we pop frame delays off as we use them
        var appliedFrameDelayStack = frameDelays
         
        try? LiveGifTool2.createDir(dirURL: gifDirURL)
        let gifUrl = gifDirURL.appending(component: "\(Int(Date().timeIntervalSince1970)).gif")
        guard let destination = CGImageDestinationCreateWithURL(gifUrl as CFURL, UTType.gif.identifier as CFString, totalFrames, nil) else {
            throw GifError.unableToCreateOutput
        }
        let orientation: UIImage.Orientation = LiveGifTool2.getUIImageOrientation(transform: videoTransform)
        print("图片方向； \(orientation)")
        var framesCompleted = 0
        var currentFrameIndex = 0
        var uiImages: [UIImage] = []
        var sample: CMSampleBuffer? = readerOutput.copyNextSampleBuffer()
        let startTime = CFAbsoluteTimeGetCurrent()
        var cgImages: [CGImage] = []
        while sample != nil {
            currentFrameIndex += 1
            if framesToRemove.contains(currentFrameIndex) {
                sample = readerOutput.copyNextSampleBuffer()
                continue
            }
 
            guard !appliedFrameDelayStack.isEmpty else { break }
            let frameDelay = appliedFrameDelayStack.removeFirst()
            autoreleasepool {
                if let newSample = sample {
                    var cgImage: CGImage? = self.cgImageFromSampleBuffer(newSample)
                    
                    if var cgImage = cgImage  {
//                        cgImage = cgImage.resizeCGImage(cgImage, targetSize: resultingSize)
                        var ui = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
//                        ui = ui.resize(targetSize: resultingSize)
                        ui = ui.resize(width: maxResolution ?? 300)
                        cgImages.append(cgImage)
                    }
                    cgImage = nil
                }
                sample = readerOutput.copyNextSampleBuffer()
            }
        }
        let endTime = CFAbsoluteTimeGetCurrent()
        print("获取帧耗时: \(endTime - startTime)")
        let fileProperties: [String: Any] = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        
        /// 开始遍历
        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFUnclampedDelayTime: 1.0/gifFPS],
        ]
        
        let newCGImages = try await self.removeBgColor(images: cgImages)
        try Task.checkCancellation()
        let endTime2 = CFAbsoluteTimeGetCurrent()
        print("去背景耗时: \(endTime2 - endTime)")
        for cgImage in newCGImages {
            var uiImage = UIImage(cgImage: cgImage)
            if let watermark = watermark {
                uiImage = uiImage.watermark(watermark: watermark)
            }
            uiImages.append(uiImage)
            CGImageDestinationAddImage(destination, uiImage.cgImage!, frameProperties as CFDictionary)
        }
        try Task.checkCancellation()
        let endTime3 = CFAbsoluteTimeGetCurrent()
        print("合成GIF耗时: \(endTime3 - endTime2)")
        let didCreateGIF = CGImageDestinationFinalize(destination)
        guard didCreateGIF else {
            throw GifError.unknown
        }
        return GifResult.init(url: gifUrl, frames: uiImages)
    }

    private func cgImageFromSampleBuffer(_ buffer: CMSampleBuffer) -> CGImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        let base = CVPixelBufferGetBaseAddress(pixelBuffer)
        let bytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytes, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else {
            return nil
        }
        let image = context.makeImage()
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        return image
    }
    
    private func calculateFramesToRemove(desiredFrameRate: CGFloat, nominalFrameRate: CGFloat, nominalTotalFrames: Int) -> [Int] {
        // Ensure the actual/nominal frame rate isn't already lower than the desired, in which case don't even worry about it
        // Add a buffer of 2 so if it's close it won't freak out and cause a bunch of unnecessary conversion due to being so close
        if desiredFrameRate < nominalFrameRate - 2 {
            let percentageOfFramesToRemove = 1.0 - (desiredFrameRate / nominalFrameRate)
            let totalFramesToRemove = Int(round(CGFloat(nominalTotalFrames) * percentageOfFramesToRemove))
            
            // We should remove a frame every `frameRemovalInterval` frames…
            // Since we can't remove e.g.: the 3.7th frame, round that up to 4, and we'd remove the 4th frame, then the 7.4th -> 7th, etc.
            let frameRemovalInterval = CGFloat(nominalTotalFrames) / CGFloat(totalFramesToRemove)
            
            var framesToRemove: [Int] = []
            var sum: CGFloat = 0.0
            
            while sum <= CGFloat(nominalTotalFrames) {
                sum += frameRemovalInterval
                let roundedFrameToRemove = Int(round(sum))
                framesToRemove.append(roundedFrameToRemove)
            }
            
            return framesToRemove
        } else {
            return []
        }
    }
    
    func calculateFrameDelays(desiredFrameRate: CGFloat, nominalFrameRate: CGFloat, totalFrames: Int) -> [CGFloat] {
        // The GIF spec per W3 only allows hundredths of a second, which negatively
        // impacts our precision, so implement variable length delays to adjust for
        // more precision (https://www.w3.org/Graphics/GIF/spec-gif89a.txt).
        //
        // In other words, if we'd like a 0.033 frame delay, the GIF spec would treat
        // it as 0.03, causing our GIF to be shorter/sped up, in order to get around
        // this make 70% of the frames 0.03, and 30% 0.04.
        //
        // In this section, determine the ratio of frames ceil'd to the next hundredth, versus the amount floor'd to the current hundredth.
        let desiredFrameDelay: CGFloat = 1.0 / min(desiredFrameRate, nominalFrameRate)
        let flooredHundredth: CGFloat = floor(desiredFrameDelay * 100.0) / 100.0 // AKA "slow frame delay"
        let remainder = desiredFrameDelay - flooredHundredth
        let nextHundredth = flooredHundredth + 0.01 // AKA "fast frame delay"
        let percentageOfNextHundredth = remainder / 0.01
        let percentageOfCurrentHundredth = 1.0 - percentageOfNextHundredth
        
        let totalSlowFrames = Int(round(CGFloat(totalFrames) * percentageOfCurrentHundredth))
        
        // Now determine how they should be distributed, we obviously don't just
        // want all the longer ones at the end (would make first portion feel fast,
        // second part feel slow), so evenly distribute them along the GIF timeline.
        //
        // Determine the spacing in relation to slow frames, so for instance if it's 1.7, the round(1.7) = 2nd frame would be slow, then the round(1.7 * 2) = 3rd frame would be slow, etc.
        let spacingInterval = CGFloat(totalFrames) / CGFloat(totalSlowFrames)
        
        // Initialize it to start with all the fast frame delays, and then we'll identify which ones will be slow and modify them in the loop to follow
        var frameDelays: [CGFloat] = [CGFloat](repeating: nextHundredth, count: totalFrames)
        var sum: CGFloat = 0.0
        
        while sum <= CGFloat(totalFrames) {
            sum += spacingInterval
            let slowFrame = Int(round(sum))
            
            // Confusingly (for us), frames are indexed from 1, while the array in Swift is indexed from 0
            if slowFrame - 1 < totalFrames {
                frameDelays[slowFrame - 1] = flooredHundredth
            }
        }
        
        return frameDelays
    }
    
    /// 批量移除背景
    public func removeBgColor(images: [CGImage]) async throws -> [CGImage] {
        let tasks = images.map { image in
            Task { () -> CGImage? in
                return await image.removeBackground()
            }
        }
        return try await withTaskCancellationHandler {
            var newImages: [CGImage] = []
            for try task in tasks {
                if let value = await task.value {
                    try Task.checkCancellation()
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
}

 
    

extension UIImage {
   /**
    *  重设图片大小
    */
   func reSizeImage(reSize:CGSize)->UIImage {
       //UIGraphicsBeginImageContext(reSize);
       UIGraphicsBeginImageContextWithOptions(reSize,false, UIScreen.main.scale);
       self.draw(in: CGRectMake(0, 0, reSize.width, reSize.height));
       let reSizeImage :UIImage? = UIGraphicsGetImageFromCurrentImageContext();
       UIGraphicsEndImageContext();
       guard let reSizeImage = reSizeImage else { return self }
       return reSizeImage;
       
   }
    
   /**
    *  等比率缩放
    */
   func scaleImage(scaleSize:CGFloat)->UIImage {
       let reSize = CGSizeMake(self.size.width * scaleSize, self.size.height * scaleSize)
       return reSizeImage(reSize: reSize)
   }
}

extension CGImage {
    func resizeCGImage(_ image: CGImage, targetSize: CGSize) -> CGImage {
        let width = Int(targetSize.width)
        let height = Int(targetSize.height)
        let bitsPerComponent = image.bitsPerComponent
        let bytesPerRow = 0
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = image.bitmapInfo.rawValue
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow,
                                space: colorSpace, bitmapInfo: bitmapInfo)
        
        let rect = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        context?.draw(image, in: rect)
        let resizedImage = context?.makeImage()
        return resizedImage ?? self
    }
}
public extension UIImage {
//    func resize(scale: CGFloat = 0.5) -> UIImage {
//        let size = self.size
//        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
//        let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
//        
//        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
//        self.draw(in: rect)
//        let newImage = UIGraphicsGetImageFromCurrentImageContext()
//        UIGraphicsEndImageContext()
//        
//        return newImage ?? self
//    }
    
    func resize(targetSize: CGSize) -> UIImage {
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        let scalingFactor = max(widthRatio, heightRatio)
        
        return resize(scale: scalingFactor)
    }
    
//    func resize(width: CGFloat = 1, height: CGFloat = 1) -> UIImage {
//        let widthRatio  = width  / size.width
//        let heightRatio = height / size.height
//        let scalingFactor = max(widthRatio, heightRatio)
//        
//        return resize(scale: scalingFactor)
//    }
}
 
