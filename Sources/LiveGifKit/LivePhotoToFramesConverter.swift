//
//  LivePhotoToFramesConverter.swift
//  
//
//  Created by Kai Shao on 2023/12/15.
//

import UIKit
import Photos
import GoodUtils

struct StickerAttributes: Hashable {
    var fps: CGFloat = 30
    var removingBackground = true
    var animated = true
//    var frameSelection: [String?] = []
    var unselectedFrameIDs: Set<String> = []
    var resizedWidth: CGFloat = 500
    
//    static func == (lhs: Self, rhs: Self) -> Bool {
//        lhs.fps == rhs.fps &&
//        lhs.removingBackground == rhs.removingBackground &&
//        lhs.animated == rhs.animated &&
//        lhs.resizedWidth == rhs.resizedWidth &&
//        lhs.frameSelection.count == rhs.frameSelection.count
//    }
}

enum LivePhotoToFramesConverterError: Error {
    case tooManyFrames
    
    static let maxFrameCount = 150
}

class LivePhotoToFramesConverter {
    var livePhoto: PHLivePhoto
    
    var attributes: StickerAttributes
    
    private var preferredTransform: CGAffineTransform!
    private var videoURL: URL!
    private var assetReader: AVAssetReader?
    
    let maxCount = 10
    
    init(livePhoto: PHLivePhoto, attributes: StickerAttributes) {
        self.livePhoto = livePhoto
        self.attributes = attributes
    }
    
    struct ImageConverterResult {
        let index: Int
        let image: UIImage
        let rect: CGRect?
    }
}

extension LivePhotoToFramesConverter {
    func convert() async throws -> [UIImage] {
        let startDate = Date()
        print("!! start extract images")
        
        defer {
            print("!! end extract images", Date().timeIntervalSince(startDate))
        }
        
        guard let assetReaderOutput = try await getAssetReaderOutput() else {
            return []
        }
        
        let date = Date()
        
        print("!! before task group")
        
        var (images, rect) = try await withThrowingTaskGroup(of: ImageConverterResult.self) { group in
            var sampleIndex = 0
            
            while let sampleBuffer = assetReaderOutput.copyNextSampleBuffer() {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    break
                }
                
                guard sampleIndex < maxCount else {
                    break
                }
                
                addTask(sampleBuffer, at: sampleIndex, taskGroup: &group)
                
                sampleIndex += 1
            }
            
            var images: [UIImage?] = []
            var commonBox: CGRect!
            
            for try await r in group {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    break
                }
                
                images.setValue(r.image, at: r.index)
                
                if let rect = r.rect {
                    if let existingBox = commonBox {
                        commonBox = existingBox.union(rect)
                    } else {
                        commonBox = rect
                    }
                }
                
                print("!! finish at \(r.index)")
                
                guard let sampleBuffer = assetReaderOutput.copyNextSampleBuffer() else  {
                    continue
                }
                
                addTask(sampleBuffer, at: sampleIndex, taskGroup: &group)
                
                sampleIndex += 1
                
                if sampleIndex > LivePhotoToFramesConverterError.maxFrameCount {
                    throw LivePhotoToFramesConverterError.tooManyFrames
                }
            }
            
            let finalImages = images.compactMap { $0 }
            
            return (finalImages, commonBox)
        }
        
        print("!! after task group", Date().timeIntervalSince(date))
        
        let date1 = Date()
        
        print("!! before crop images")
        if let rect {
            images = await cropImages(images, to: rect)
            
            try Task.checkCancellation()
            
            print("!! after crop images", rect, Date().timeIntervalSince(date1))
        }
        
        try? FileManager.default.removeItem(at: videoURL)
        
        return images
    }
}

private extension LivePhotoToFramesConverter {
    func cropImages(_ images: [UIImage], to rect: CGRect) async -> [UIImage] {
        await withTaskGroup(of: (Int, UIImage).self) { group in
            for (index, image) in images.enumerated() {
                group.addTask {
                    await Task.detached {
                        (index, image.cropImage(toRect: rect)!)
                    }.value
                }
            }
            
            let newImages: [UIImage?] = await group.reduce(into: []) { partialResult, r in
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                
                partialResult.setValue(r.1, at: r.0)
            }
            
            return newImages.map { $0! }
        }
    }
    
    func getAssetReaderOutput() async throws -> AVAssetReaderTrackOutput? {
        // Fetch the resources for the Live Photo (video and photo)
        let resources = PHAssetResource.assetResources(for: livePhoto)
        
        // Find the video component among the Live Photo resources
        guard let videoResource = resources.first(where: { $0.type == .pairedVideo }) else {
            return nil
        }
        
        // Create a URL in the temporary directory to store the video
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString)
        
        try ensureDirectoryExists(at: rootURL)
        
        videoURL = rootURL.appendingPathComponent(videoResource.originalFilename)
        
        do {
            try await PHAssetResourceManager.default().writeData(for: videoResource, toFile: videoURL, options: nil)
        } catch {
            print("Error writing video resource to temporary file: \(error)")
            throw error
        }
        
        // Process the video file to extract frames
        let asset = AVAsset(url: videoURL)
        guard let assetReader = try? AVAssetReader(asset: asset) else {
            return nil
        }
        
        self.assetReader = assetReader
        
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            return nil
        }
        
        let readerOutputSettings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB)]
        let assetReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerOutputSettings)
        
        assetReader.add(assetReaderOutput)
        assetReader.startReading()
        
        preferredTransform = try! await videoTrack.load(.preferredTransform)
        
        return assetReaderOutput
    }
    
    func convertCImageToUIImage(_ ciImage: CIImage) async -> UIImage {
        let cgImage = ciImage.toCGImage()
        var uiImage = UIImage(cgImage: cgImage,
                              scale: 1,
                              orientation: getImageOrientation(transform: preferredTransform))
        
        uiImage = uiImage.resize(width: attributes.resizedWidth)
        
        if attributes.removingBackground {
            uiImage = await uiImage.removeBackground()!
        }
        
        return uiImage
    }
    
    func addTask(_ buffer: CMSampleBuffer, at index: Int, taskGroup group: inout ThrowingTaskGroup<ImageConverterResult, Error>) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(buffer) else {
            return
        }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        
        group.addTask {
            await Task.detached {
                let uiImage = await self.convertCImageToUIImage(ciImage)
                
                let rect = uiImage.nonTransparentBoundingBox()
                
                print("!! nonTrans rect: \(rect!), index: \(index)")
                
                return .init(index: index, image: uiImage, rect: rect)
            }.value
        }
    }
}

private func getImageOrientation(transform: CGAffineTransform) -> UIImage.Orientation {
    if transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0 {
        return .right
    } else if transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0 {
        return .left
    } else if transform.a == 1.0 && transform.b == 0 && transform.c == 0 && transform.d == 1.0 {
        return .up
    } else if transform.a == -1.0 && transform.b == 0 && transform.c == 0 && transform.d == -1.0 {
        return .down
    } else {
        return .up
    }
}

private extension Array where Element == UIImage? {
    mutating func setValue(_ value: Element, at index: Int) {
        while count < index + 1 {
            append(nil)
        }
        
        self[index] = value
    }
}

extension CIImage {
    func toCGImage() -> CGImage {
        let context = CIContext()
        let cgImage = context.createCGImage(self, from: extent)!
        
        return cgImage
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
