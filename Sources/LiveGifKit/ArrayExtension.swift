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
    public func createGif(frameDelay: CGFloat = 0.03) async throws -> Result<GifResult, GifError> {
        let resultingFilename = "Image.gif"
        let resultingFileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(resultingFilename)
        if FileManager.default.fileExists(atPath: resultingFileURL.path) {
            do {
                try FileManager.default.removeItem(at: resultingFileURL)
            } catch {
                print("删除目录错误: \(error)")
            }
        }
        
        guard let destination = CGImageDestinationCreateWithURL(resultingFileURL as CFURL, UTType.gif.identifier as CFString, self.count, nil) else {
            return .failure(.unableToCreateOutput)
        }
        
        let fileProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]
        ]
        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFUnclampedDelayTime: frameDelay],
            kCGImagePropertyOrientation as String: CGImagePropertyOrientation.right.rawValue
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
      
        for image in self {
            CGImageDestinationAddImage(destination, image.cgImage!, frameProperties as CFDictionary)
        }
        let didCreateGIF = CGImageDestinationFinalize(destination)
        guard didCreateGIF else {
            return .failure(.unknown)
        }
        return .success(.init(url: resultingFileURL, frames: self))
    }
}
