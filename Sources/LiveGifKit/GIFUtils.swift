//
//  GIFUtils.swift
//
//
//  Created by Kai Shao on 2023/11/28.
//

import UIKit
import UniformTypeIdentifiers

extension Array where Element == CGImage {
    func createGIF(frameRate: Float = 0.03) -> URL? {
        let images = self
        let frameProperties = [kCGImagePropertyGIFDictionary : [ kCGImagePropertyGIFUnclampedDelayTime: frameRate]]
        let fileProperties = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]]
 
        
        let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let tempID = UUID().uuidString
        let gifURL = documentsDirectoryURL.appendingPathComponent("\(tempID).gif")
        
        guard let destination = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, images.count, nil) else {
            return nil
        }
        
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
         
        for image in images {
            autoreleasepool {
                CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
            }
        }
        
        if !CGImageDestinationFinalize(destination) {
            return nil
        }
        
        return gifURL
    }
}
 
