//
//  File.swift
//
//
//  Created by 汤小军 on 2023/12/31.
//

import Foundation
import UIKit
import UniformTypeIdentifiers

struct ImageGifHander {
    static public func createGif(uiImages: [UIImage], config: GifToolParameter) async throws -> GifResult {
        try Task.checkCancellation()
        if uiImages.isEmpty {
            throw GifError.gifResultNil
        }
        try LiveGifTool.createDir(dirURL: config.gifTempDir)
        let gifFileName = "\(Int(Date().timeIntervalSince1970)).gif"
        let gifURL = config.gifTempDir.appending(path: gifFileName)
      
        guard let destination = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, uiImages.count, nil) else {
            throw GifError.unableToCreateOutput
        }
        
        /// 从相册选取的需要调整方向
        var newUIImages = uiImages
        switch config.data {
            case .images(_, let adjustOrientation):
                if adjustOrientation {
                    newUIImages = newUIImages.map({ $0.adjustOrientation().resize(width: config.maxResolution)})
                    print("调整了图片的方向")
                }
            default:
                break
        }
        
        let fileProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]
        ]
        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFUnclampedDelayTime: 1.0/config.gifFPS],
            kCGImagePropertyOrientation as String: LiveGifTool.getCGImageOrientation(imageOrientation: newUIImages.first?.imageOrientation ?? .up).rawValue
        ]
        
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        var cgImages = newUIImages.map({ $0.cgImage! })
        if config.removeBg {
            try Task.checkCancellation()
            cgImages = try await LiveGifTool.removeBg(images: cgImages)
        }
        
        var uiImages: [UIImage] = []
        for cgImage in cgImages {
            try Task.checkCancellation()
            autoreleasepool {
                var uiImage = UIImage(cgImage: cgImage)
                for decorator in config.imageDecorates {
                    uiImage = uiImage.decorate(config: decorator)
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
