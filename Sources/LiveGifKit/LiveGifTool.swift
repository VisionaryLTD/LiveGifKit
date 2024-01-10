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
    func cleanup() throws
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
        let videoUrl = try await LiveGifTool.livePhotoConvertToVideo(livePhoto: livePhoto, tempDir: self.gifTempDir)
        guard let videoUrl = videoUrl else { throw GifError.unableToFindvideoUrl }
        return try await VideoGifHander.convertToGIF(videoUrl: videoUrl, config: self.parameter)
    }
    
    /// 通过图片合成GIF
    ///
    /// images: GIF帧数组
    private func createImagesGif(images: [UIImage]) async throws -> GifResult {
        return try await ImageGifHander.createGif(uiImages: images, config: self.parameter)
    }
    
    /// 保存相册
    public func save(method: Method) async throws {
        try await AlbumTool.save(method: method)
    }
    
    /// 去图片背景和空白部分
    public func removeBackground(uiImage: UIImage) async throws -> Data? {
        if let cgImage = uiImage.cgImage,
           let cgImage2 = try await LiveGifTool.removeBg(images: [cgImage]).first {
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
    
    public func preheating() async throws {
        print("LiveGifTool ... 预热。。。。。")
        let img = UIImage(named: "example", in: .module, with: nil)
        let parameter = GifToolParameter(data: .images(frames: [img!]),  removeBg: true)
        let result = try await self.createGif(parameter: parameter)
        try self.cleanup()
        print("预热的URL: \(String(describing: result.url))")
    }
    
    /// 删除生成GIF的文件目录
    public func cleanup() throws {
        if FileManager.default.fileExists(atPath: self.gifTempDir.path) {
            print("删除GIF目录: \(self.gifTempDir.path())")
            try FileManager.default.removeItem(atPath: self.gifTempDir.path())
        } else {
            print("GIF目录不存在")
        }
        
        let tempDirPath = NSTemporaryDirectory() + "/live-photo-bundle"
        if FileManager.default.fileExists(atPath: tempDirPath) {
            print("删除live-photo-bundle目录: \(tempDirPath)")
            try FileManager.default.removeItem(atPath: tempDirPath)
        } else {
            print("live-photo-bundle目录不存在")
        }
    }
    
    deinit {
        print("LiveGifTool deinit")
    }
}
