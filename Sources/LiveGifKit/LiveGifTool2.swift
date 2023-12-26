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
    static func livePhotoConvertToVideo(livePhoto: PHLivePhoto, tempDir: URL) async throws -> URL? {
        let resources = PHAssetResource.assetResources(for: livePhoto)
        guard let videoResource = resources.first(where: { $0.type == .pairedVideo }) else {
            return nil
        }
        
        try? self.createDir(dirURL: tempDir)
        let videoURL = tempDir.appendingPathComponent("\(Date())" + videoResource.originalFilename)
        print("视频临时目录: \(videoURL)")
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
    
    
    /// 批量移除背景
    public static func removeBgColor(images: [CGImage]) async throws -> [CGImage] {
        let tasks = images.map { image in
            Task { () -> (CGImage, CGRect?) in
                let cgImg = await image.removeBackground()
                let rect = await cgImg.nonTransparentBoundingBox()
                return (cgImg, rect)
            }
        }
        return try await withTaskCancellationHandler {
            var newImages: [CGImage] = []
            var finalRect: CGRect?
            for try task in tasks {
                try Task.checkCancellation()
                
                let (cgImg, rect) = await task.value
                if let rect = rect {
                    /// 计算最小矩形 如果矩形为空 说明是透明图片 舍弃掉
                    if let existingBox = finalRect {
                        finalRect = existingBox.union(rect)
                    } else {
                        finalRect = rect
                    }
                    newImages.append(cgImg)
                }
            }
            newImages = newImages.cropImages(toRect: finalRect!)
            return newImages
        } onCancel: {
            tasks.forEach { task in
                task.cancel()
            }
        }
    }
}
