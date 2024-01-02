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

protocol GifTool {
    func save(method: Method) async throws
    func createGif(parameter: GifToolParameter) async throws -> GifResult
    func removeBackground(uiImage: UIImage) async throws -> Data?
    func cleanup()
}

public class LiveGifTool: GifTool {
    
    /// 生成GIF
    ///
    /// - parameter: GifToolParameter
    /// - gifFPS: gif帧率 默认 30
    /// - watermarkInfo: 水印信息 默认为空
    /// - data: livePhoto、images 两种方式
    /// - maxResolution: 图片大小 默认300
    public func createGif(parameter: GifToolParameter) async throws -> GifResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        self.parameter = parameter
        self.parameter.gifTempDir = self.gifTempDir
        switch parameter.data {
        case .livePhoto(let livePhoto, let livePhotoFPS):
            var result = try await self.createLivePhotoGif(livePhoto: livePhoto, livePhotoFPS: livePhotoFPS)
#if DEBUG
            result.totalTime = CFAbsoluteTimeGetCurrent() - startTime
#endif
            return result
        case .images(let frames, _):
            var result =  try await self.createImagesGif(images: frames)
#if DEBUG
            result.totalTime = CFAbsoluteTimeGetCurrent() - startTime
#endif
            return result
        }
    }
    
    /// 通过LivePhoto 合成GIF
    ///
    ///livePhoto: PHLivePhoto
    ///PHLivePhoto: PHLivePhoto帧率
    private func createLivePhotoGif(livePhoto: PHLivePhoto, livePhotoFPS: CGFloat) async throws -> GifResult {
        let videoUrl = try? await LiveGifTool2.livePhotoConvertToVideo(livePhoto: livePhoto, tempDir: self.gifTempDir)
        guard let videoUrl = videoUrl else { throw GifError.unableToFindvideoUrl }
        do {
            return try await VideoGifHander.convertToGIF(videoUrl: videoUrl, config: self.parameter)
        } catch {
            throw error
        }
    }
    
    /// 通过图片合成GIF
    ///
    /// images: GIF帧数组
    private func createImagesGif(images: [UIImage]) async throws -> GifResult {
        do {
            return try await ImageGifHander.createGif(uiImages: images, config: self.parameter)
        } catch {
            throw error
        }
    }
    
    /// 删除生成GIF的文件目录
    public func cleanup() {
        do {
            print("删除目录: \(self.gifTempDir.path())")
            if FileManager.default.fileExists(atPath: self.gifTempDir.path) {
                try FileManager.default.removeItem(atPath: self.gifTempDir.path())
            } else {
                print("目录已被删除")
            }
        } catch {
            print("删除目录失败: \(self.gifTempDir) \(error)")
        }
    }
    
    /// 保存相册
    public func save(method: Method) async throws {
        do {
            try await AlbumTool.save(method: method)
        } catch {
            throw error
        }
    }
    
    /// 去图片背景和空白部分
    public func removeBackground(uiImage: UIImage) async throws -> Data? {
        if let cgImage = uiImage.cgImage,
           let cgImage2 = try await LiveGifTool2.removeBg(images: [cgImage]).first {
            let image = UIImage(cgImage: cgImage2, scale: 1.0, orientation: uiImage.imageOrientation)
            return image.pngData()
        }
        return nil
    }
    
    var parameter: GifToolParameter!
    var gifTempDir: URL
    public init() {
        self.gifTempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "Gif/" + UUID().uuidString)
    }
    
    deinit {
         print("LiveGifTool deinit")
    }
}
