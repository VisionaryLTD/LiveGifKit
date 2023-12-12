//
//  File.swift
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

public extension URL {
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func convertToGIF(maxResolution: CGFloat? = 300, frameDelay: CGFloat = 15.0, updateProgress: @escaping (CGFloat) -> Void) async throws -> Result<GifResult, GifError> {
        let asset = AVURLAsset(url: self)
        
        guard let reader = try? AVAssetReader(asset: asset) else {
            return .failure(.unableToReadFile)
        }
        
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            return .failure(.unableToFindTrack)
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
        
        let framesToRemove = calculateFramesToRemove(desiredFrameRate: frameDelay, nominalFrameRate: nominalFrameRate, nominalTotalFrames: nominalTotalFrames)
        
        let totalFrames = nominalTotalFrames - framesToRemove.count
        
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
        let frameDelays = calculateFrameDelays(desiredFrameRate: frameDelay, nominalFrameRate: nominalFrameRate, totalFrames: totalFrames)
        
        // Since there can be a disjoint mapping between frame delays
        // and the frames in the video/pixel buffer (if we're lowering
        // the
        // frame rate) rather than messing around with a complicated mapping,
        // just have a stack where we pop frame delays off as we use them
        var appliedFrameDelayStack = frameDelays
        var sample: CMSampleBuffer? = readerOutput.copyNextSampleBuffer()
        
        let fileProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0
            ]
        ]
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let resultingFilename = "\(startTime)-Image.gif"
        let resultingFileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(resultingFilename)
        
        if FileManager.default.fileExists(atPath: resultingFileURL.path) {
            do {
                try FileManager.default.removeItem(at: resultingFileURL)
            } catch {
                print("删除目录错误: \(error)")
            }
        }
        
        guard let destination = CGImageDestinationCreateWithURL(resultingFileURL as CFURL, UTType.gif.identifier as CFString, totalFrames, nil) else {
            return .failure(.unableToCreateOutput)
        }
        
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        
        var framesCompleted = 0
 
        var currentFrameIndex = 0
        var cgImages: [CGImage] = []
        while sample != nil {
            currentFrameIndex += 1
            if framesToRemove.contains(currentFrameIndex) {
                sample = readerOutput.copyNextSampleBuffer()
                continue
            }
 
            guard !appliedFrameDelayStack.isEmpty else { break }
            
            let frameDelay = appliedFrameDelayStack.removeFirst()
            
            if let newSample = sample {
                // Create it as an optional and manually nil it out every time it's
                // finished otherwise weird Swift bug where memory will balloon enormously
                // (see https://twitter.com/ChristianSelig/status/1241572433095770114)
                var cgImage: CGImage? = self.cgImageFromSampleBuffer(newSample)
                
                framesCompleted += 1
                if let cgImage {
                    let frameProperties: [String: Any] = [
                        kCGImagePropertyGIFDictionary as String: [
                            kCGImagePropertyGIFDelayTime: frameDelay
                        ]
                    ]
                    if let cgImage = await cgImage.removeBackground() {
                        cgImages.append(cgImage)
                        let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .left)
                        CGImageDestinationAddImage(destination, uiImage.cgImage!, frameProperties as CFDictionary)
                    }
                }
                
                cgImage = nil
                
                let progress = CGFloat(framesCompleted) / CGFloat(totalFrames)
                
                // GIF progress is a little fudged so it works with downloading progress reports
                Task { @MainActor in
                    updateProgress(progress)
                }
            }
            
            sample = readerOutput.copyNextSampleBuffer()
        }
        
        let didCreateGIF = CGImageDestinationFinalize(destination)
        
        guard didCreateGIF else {
            return .failure(.unknown)
        }
        return .success(.init(url: resultingFileURL, frames: cgImages, videoTransform: videoTransform))
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
}

//水印
func addWatermark(to cgImage: CGImage, withText text: String) -> CGImage? {
    // Set the font and text color
    let font = UIFont.boldSystemFont(ofSize: 32)
    let color = UIColor.red.cgColor

    // Create a new image context
    let width = cgImage.width
    let height = cgImage.height
    let bytesPerRow = cgImage.bytesPerRow
    let bitsPerComponent = cgImage.bitsPerComponent
    let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = cgImage.bitmapInfo
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo.rawValue)!

    // Set the image data
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    // Create a text layer and add it to the context
    let attributedString = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    let textHeight = attributedString.boundingRect(with: CGSize(width: width, height: height), options: [.usesLineFragmentOrigin], context: nil).height
    let textPosition = CGPoint(x: 20, y: 20)
    let textLine = CTLineCreateWithAttributedString(attributedString)
    let textBounds = CTLineGetBoundsWithOptions(textLine, CTLineBoundsOptions.useOpticalBounds)

    let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
    let path = CGMutablePath()
    path.addRect(CGRect(x: 0, y: 0, width: 200, height: 50), transform: .identity)
    let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, attributedString.length), path, nil)
    CTFrameDraw(frame, context)

    // Create a new CGImage from the context
    return context.makeImage()
}
