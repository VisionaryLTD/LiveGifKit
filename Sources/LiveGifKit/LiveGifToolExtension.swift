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

extension LiveGifTool {
    /// 转成视频url
    static func livePhotoConvertToVideo(livePhoto: PHLivePhoto, tempDir: URL) async throws -> URL? {
        let resources = PHAssetResource.assetResources(for: livePhoto)
        guard let videoResource = resources.first(where: { $0.type == .pairedVideo }) else {
            return nil
        }
        
        try self.createDir(dirURL: tempDir)
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
            try FileManager.default.createDirectory(atPath: dirURL.path, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    static func getCGImageOrientation(imageOrientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        return CGImagePropertyOrientation(rawValue: UInt32(imageOrientation.rawValue)) ?? .up
    }
    
    static func getUIImageOrientation(transform: CGAffineTransform) -> UIImage.Orientation {
        if transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0 {
            return .right
        }  else if transform.a == 0 && transform.b == -1.0 && transform.c == -1.0 && transform.d == 0 {
            return .rightMirrored
        }
        
        else if transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0 {
            return .left
        }  else if transform.a == 0 && transform.b == 1.0 && transform.c == 1.0 && transform.d == 0 {
            return .leftMirrored
        }
        
        else if transform.a == 1.0 && transform.b == 0 && transform.c == 0 && transform.d == 1.0 {
            return .up
        } else if transform.a == -1.0 && transform.b == 0 && transform.c == 0 && transform.d == 1.0 {
            return .upMirrored
        }
        
        else if transform.a == -1.0 && transform.b == 0 && transform.c == 0 && transform.d == -1.0 {
            return .down
        } else if transform.a == 1.0 && transform.b == 0 && transform.c == 0 && transform.d == -1.0 {
            return .downMirrored
        }
        
        else {
            return .up
        }
    }
    
    /// 批量移除背景
    public static func removeBg(images: [CGImage]) async throws -> [CGImage] {
        let tasks = images.map { image in
            Task { () -> (CGImage?, CGRect?) in
                let cgImg = await image.removeBackground()
                let rect = cgImg?.nonTransparentBoundingBox()
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
                    
                    if let cgImg {
                        newImages.append(cgImg)
                    }
                }
            }
            if let finalRect = finalRect {
                newImages = newImages.cropImages(toRect: finalRect)
            }
            return newImages
        } onCancel: {
            tasks.forEach { task in
                task.cancel()
            }
        }
    }
}
