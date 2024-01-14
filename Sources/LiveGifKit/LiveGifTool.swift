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
    /// - decoratorInfo: 水印信息 默认为空
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
    
    /// 预热
    public func preheating() async throws {
        print("LiveGifTool ... 预热。。。。。")
        let img = UIImage(named: "example", in: .module, with: nil)
        let parameter = GifToolParameter(data: .images(frames: [img!]),  removeBg: true)
        let result = try await self.createGif(parameter: parameter)
        try self.cleanup()
        print("预热的URL: \(String(describing: result.url))")
    }
    
    /// 删除tmp文件夹
    public static func cleanupAllTmp() throws {
        let tempDir = NSTemporaryDirectory()
        if FileManager.default.fileExists(atPath: tempDir) {
            print("删除tmp目录: \(tempDir)")
            try FileManager.default.removeItem(atPath: tempDir)
        }
    }
    
    /// 删除生成GIF的文件目录
    public func cleanup() throws {
        let gifDirPath = NSTemporaryDirectory() + "/Gif/"
        if FileManager.default.fileExists(atPath: gifDirPath) {
            print("删除GIF目录: \(gifDirPath)")
            try FileManager.default.removeItem(atPath: gifDirPath)
        } else {
            print("GIF目录不存在")
        }
        
        print("检查live-photo-bundle目录")
        let livePhotoBundlePath = NSTemporaryDirectory() + "/live-photo-bundle"
        let fileList = try self.getFileList(path: livePhotoBundlePath)
        let sortedFileList = fileList.sorted(by: { $0.key < $1.key })
        let fileNameList = sortedFileList.filter({ $0.value.hasSuffix(".pvt")}).map({ ($0.value as NSString).lastPathComponent.replacingOccurrences(of: ".pvt", with: "") })
        print("文件名称: \(fileNameList)")
        print("live-photo-bundle目录文件总个数: \(sortedFileList.count)")
        for (date, value) in sortedFileList {
            print("!!!: \(date) -- \(value)")
        }
        if fileNameList.count > 1 {
            if let saveFileName = fileNameList.suffix(1).first {
                for (date, url) in sortedFileList {
                    if !url.contains(saveFileName) {
                        print("删除的文件时间: \(date)\nurl:\(url)")
                        try self.deleteFilePath(path: url)
                    }
                }
            }
        }
    }
    
    func deleteFilePath(path: String) throws {
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
    }
    
    func getFileList(path: String) throws -> [Date: String] {
        var files = [Date: String]()
        if let enumerator = FileManager.default.enumerator(atPath: path){
            while let filePath = enumerator.nextObject() as? String {
                let fullPath = "\(path)/\(filePath)"
                let fileAttributes = try FileManager.default.attributesOfItem(atPath: fullPath)
                // 从文件属性中获取它的创建日期
                if let creationDate = fileAttributes[FileAttributeKey.creationDate] as? Date {
                    files[creationDate] = fullPath
                }
            }
        }
        return files
    }
    
    deinit {
        print("LiveGifTool deinit")
    }
}
