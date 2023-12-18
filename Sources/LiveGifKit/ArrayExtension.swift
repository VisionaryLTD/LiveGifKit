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

extension Array where Element == UIImage {
    public func createGif(gifFPS: CGFloat, gifDirURL: URL, watermark: WatermarkConfig?) async throws -> GifResult {
        try? LiveGifTool2.createDir(dirURL: gifDirURL)
        let gifFileName = "\(Int(Date().timeIntervalSince1970)).gif"
        let gifURL = gifDirURL.appending(path: gifFileName)
      
        guard let destination = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, self.count, nil) else {
            throw GifError.unableToCreateOutput
        }
        
        let fileProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]
        ]
        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFUnclampedDelayTime: 1.0/gifFPS],
            kCGImagePropertyOrientation as String: LiveGifTool2.getCGImageOrientation(imageOrientation: self.first?.imageOrientation ?? .right).rawValue
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
      
        for var image in self {
            if let watermark = watermark {
                image = image.watermark(watermark: watermark)
            }
            CGImageDestinationAddImage(destination, image.cgImage!, frameProperties as CFDictionary)
        }
        let didCreateGIF = CGImageDestinationFinalize(destination)
        guard didCreateGIF else {
            throw GifError.unknown
        }
        return GifResult.init(url: gifURL, frames: self)
    }
}
