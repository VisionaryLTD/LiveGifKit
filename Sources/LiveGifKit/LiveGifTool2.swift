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
        
        try? self.createDir(dirURL: videoDir)
        
        let videoURL = videoDir.appendingPathComponent(videoResource.originalFilename)
        do {
            try await PHAssetResourceManager.default().writeData(for: videoResource, toFile: videoURL, options: nil)
        } catch {
            print("Error writing video resource to temporary file: \(error)")
            throw error
        }
        
        return videoURL
    }
    
    static func createDir(dirURL: URL) throws {
        if !FileManager.default.fileExists(atPath: dirURL.path) {
            do {
                try FileManager.default.createDirectory(atPath: dirURL.path, withIntermediateDirectories: true, attributes: nil)
            } catch {
                throw error
            }
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
    
    static func getCGImageOrientation(imageOrientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch imageOrientation {
        case .up:
            return .up
        case .down:
            return .down
        case .left:
            return .left
        case .right:
            return .right
        default:
            return .up
        }
    }
}
