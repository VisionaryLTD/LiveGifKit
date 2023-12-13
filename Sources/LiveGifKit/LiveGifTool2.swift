//
//  File.swift
//  
//
//  Created by tangxiaojun on 2023/12/12.
//

import Foundation
import CoreGraphics
import Photos
import PhotosUI
import _PhotosUI_SwiftUI

struct LiveGifTool2 {
    /// 转成视频
    static func livePhotoConvertToVideo(livePhoto: PHLivePhoto) async throws -> URL? {
        let resources = PHAssetResource.assetResources(for: livePhoto)
        guard let videoResource = resources.first(where: { $0.type == .pairedVideo }) else {
            return nil
        }
        
        let videoDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString)
        
        try? self.ensureDirectoryExists(at: videoDir)
        
        let videoURL = videoDir.appendingPathComponent(videoResource.originalFilename)
        do {
            try await PHAssetResourceManager.default().writeData(for: videoResource, toFile: videoURL, options: nil)
        } catch {
            print("Error writing video resource to temporary file: \(error)")
            throw error
        }
        
        return videoURL
    }
    
    static func ensureDirectoryExists(at url: URL) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            if !isDirectory.boolValue {
                throw NSError(domain: "The path exists but is not a directory", code: -1, userInfo: nil)
            }
        } else {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    static func getCGImageOrientation(transform: CGAffineTransform) -> CGImagePropertyOrientation {
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
    
    static func getUIImageOrientation(transform: CGAffineTransform) -> UIImage.Orientation {
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
}
