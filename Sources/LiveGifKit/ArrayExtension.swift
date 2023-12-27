//
//  File.swift
//
//
//  Created by tangxiaojun on 2023/12/12.
//

import Foundation
import AVFoundation
import Foundation
import UniformTypeIdentifiers
import CoreText
import UIKit

extension Array where Element == CGImage {
    func cropImages(toRect rect: CGRect) -> [CGImage] {
        compactMap { $0.cropImage(toRect: rect) }
    }
}

extension Array where Element == UIImage {
    public func createGif(config: GifToolParameter) async throws -> GifResult {
        if self.isEmpty {
            throw GifError.gifResultNil
        }
        try? LiveGifTool2.createDir(dirURL: config.gifTempDir)
        let gifFileName = "\(Int(Date().timeIntervalSince1970)).gif"
        let gifURL = config.gifTempDir.appending(path: gifFileName)
      
        guard let destination = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, self.count, nil) else {
            throw GifError.unableToCreateOutput
        }
        
        let fileProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]
        ]
        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFUnclampedDelayTime: 1.0/config.gifFPS],
            kCGImagePropertyOrientation as String: LiveGifTool2.getCGImageOrientation(imageOrientation: self.first?.imageOrientation ?? .right).rawValue
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        var cgImages = self.map({ $0.cgImage! })
        if config.removeImageBgColor {
            cgImages = try await LiveGifTool2.removeBgColor(images: cgImages)
            try Task.checkCancellation()
        }
        
        var uiImages: [UIImage] = []
        for cgImage in cgImages {
            autoreleasepool {
                var uiImage = UIImage(cgImage: cgImage)
                if let watermark = config.watermark {
                    uiImage = uiImage.watermark(watermark: watermark)
                }
                uiImages.append(uiImage)
                CGImageDestinationAddImage(destination, uiImage.cgImage!, frameProperties as CFDictionary)
            }
        }
        
        let didCreateGIF = CGImageDestinationFinalize(destination)
        guard didCreateGIF else {
            throw GifError.unknown
        }
        return GifResult.init(url: gifURL, frames: uiImages)
    }
}

 
public extension UIImage {
    func resize(scale: CGFloat = 0.5) -> UIImage {
//        let image = UIImage(named: "myImage")
//        let scaledImage = UIImage(cgImage: image!.cgImage!, scale: 2.0, orientation: .up)
//        let resizedImage = scaledImage.resized(to: CGSize(width: 50, height: 50))
        
//        let size = self.size
//        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
//        return UIGraphicsImageRenderer(size: newSize).image { _ in
//            self.draw(in: CGRect(origin: .zero, size: newSize))
//        }
        let size = self.size
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        self.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage ?? self
    }
     
   
    
    func resize(width: CGFloat = 1, height: CGFloat = 1) -> UIImage {
        let widthRatio  = width  / size.width
        let heightRatio = height / size.height
        let scalingFactor = max(widthRatio, heightRatio)
        
        return resize(scale: scalingFactor)
    }
}
