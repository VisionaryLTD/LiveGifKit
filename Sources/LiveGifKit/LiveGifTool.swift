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

public struct GifResult {
    public let url: URL
    public let frames: [UIImage]
    public var data: Data {
        try! Data(contentsOf: url)
    }
}

protocol GifTool {
    func save(method: Method) async throws
    func createGif(livePhoto: PHLivePhoto, livePhotoFPS: CGFloat, gifFPS: CGFloat, watermark: WatermarkConfig?) async throws -> GifResult
    func createGif(frames: [UIImage], gifFPS: CGFloat, watermark: WatermarkConfig?) async throws -> GifResult
    func cleanup()
}

public class LiveGifTool: GifTool {
    
    let gifTempDir: URL
    public init() {
        self.gifTempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "Gif/" + UUID().uuidString)
    }
   
    /// 保存相册
    public func save(method: Method) async throws {
        do {
            try await AlbumTool.save(method: method)
        } catch {
            throw error
        }
    }
    
    /// 通过PHLivePhoto创建GIF
    ///
    /// livePhotoFPS: PHLivePhoto帧率 默认每秒 15
    ///
    /// gifFPS: 合成的GIF帧率 默认 30
    ///
    /// watermark: 水印配置 默认为nil
    public func createGif(livePhoto: PHLivePhoto, livePhotoFPS: CGFloat = 15, gifFPS: CGFloat = 30, watermark: WatermarkConfig? = nil) async throws -> GifResult {
        let videoUrl = try? await LiveGifTool2.livePhotoConvertToVideo(livePhoto: livePhoto)
        guard let videoUrl = videoUrl else { throw GifError.unableToFindvideoUrl }
        do {
            let gif = try await videoUrl.convertToGIF(maxResolution: 300, livePhotoFPS: livePhotoFPS, gifFPS: gifFPS, gifDirURL: self.gifTempDir, watermark: watermark)
            return gif
        } catch {
            throw error
        }
    }
    
    /// 通过图片合成GIF
    ///
    /// gifFPS: 合成的GIF帧率 默认 30
    ///
    /// watermark: 水印配置 默认为nil
    public func createGif(frames: [UIImage], gifFPS: CGFloat = 30, watermark: WatermarkConfig? = nil) async throws -> GifResult {
        do {
            let gif = try await frames.createGif(gifFPS: gifFPS, gifDirURL: self.gifTempDir, watermark: watermark)
            return gif
        } catch {
            throw error
        }
    }
    
    /// 删除生成GIF的文件目录
    public func cleanup() {
        do {
            print("删除目录: \(self.gifTempDir.path())")
            try FileManager.default.removeItem(atPath: self.gifTempDir.path())
        } catch {
            print("删除目录失败: \(self.gifTempDir) \(error)")
        }
    }
}
