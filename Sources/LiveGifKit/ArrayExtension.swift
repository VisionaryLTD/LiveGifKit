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

extension Array where Element == CGImage {
    public func createGif(frameDelay: CGFloat = 15.0) async throws -> Result<GifResult, GifError> {
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
            kCGImagePropertyGIFDictionary as String: [ kCGImagePropertyGIFLoopCount as String: 0]
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        for cgImage in self {
            let frameProperties: [String: Any] = [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFDelayTime: frameDelay
                ]
            ]
            CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
        }
        let didCreateGIF = CGImageDestinationFinalize(destination)
        guard didCreateGIF else {
            return .failure(.unknown)
        }
        return .success(.init(url: resultingFileURL, frames: self, videoTransform: nil))
    }
}
