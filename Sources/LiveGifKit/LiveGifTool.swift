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
    func createGif(livePhoto: PHLivePhoto, frameDelay: CGFloat, gifFrameRate: CGFloat) async throws -> GifResult
    func createGif(frames: [UIImage], gifFrameRate: CGFloat) async throws -> GifResult
    func cleanup()
}

public class LiveGifTool: GifTool {
    let gifTempDir: URL
    public init() {
        self.gifTempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "Gif/" + UUID().uuidString)
    }
   
    public func save(method: Method) async throws {
        do {
            try await AlbumTool.save(method: method)
        } catch {
            throw error
        }
    }
    
    public func createGif(livePhoto: PHLivePhoto, frameDelay: CGFloat = 15, gifFrameRate: CGFloat) async throws -> GifResult {
        let videoUrl = try? await LiveGifTool2.livePhotoConvertToVideo(livePhoto: livePhoto)
        guard let videoUrl = videoUrl else { throw GifError.unableToFindvideoUrl }
        do {
            let gif = try await videoUrl.convertToGIF(maxResolution: 300, frameDelay: frameDelay, gifFrameRate: gifFrameRate, gifDirURL: self.gifTempDir, updateProgress: { progress in
                print("转换进度: \(progress)")
            })
            return gif
        } catch {
            throw error
        }
    }
    
    public func createGif(frames: [UIImage], gifFrameRate: CGFloat = 30) async throws -> GifResult {
        do {
            let gif = try await frames.createGif(gifFrameRate: gifFrameRate, gifDirURL: self.gifTempDir)
            return gif
        } catch {
            throw error
        }
    }
    
    public func cleanup() {
        do {
            print("删除目录: \(self.gifTempDir.path())")
            try FileManager.default.removeItem(atPath: self.gifTempDir.path())
        } catch {
            print("删除目录失败: \(self.gifTempDir) \(error)")
        }
    }
}
