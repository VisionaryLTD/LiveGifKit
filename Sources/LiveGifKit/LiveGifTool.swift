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

public enum GifError: Error {
    case unableToReadFile
    case unableToFindTrack
    case unableToCreateOutput
    case unknown
    case unableToFindvideoUrl
    case gifResultNil
}

public protocol GifTool {
    func saveToAlbum(from url: URL, albumName: String?) async throws -> Bool
    func createGif(pickerItem: PhotosPickerItem, frameDelay: CGFloat, gifFps: CGFloat) async throws -> Result<GifResult, GifError>
    func createGif(frames: [UIImage], frameDelay: CGFloat) async throws -> Result<GifResult, GifError>
    func cleanup()
}

public class LiveGifTool: GifTool {
    public static let shared = LiveGifTool()
    
    public func saveToAlbum(from url: URL, albumName: String?) async throws -> Bool {
        return false
    }
    
    public func createGif(pickerItem: PhotosPickerItem, frameDelay: CGFloat = 15, gifFps: CGFloat) async throws -> Result<GifResult, GifError> {
        if let livePhoto = try? await pickerItem.loadTransferable(type: PHLivePhoto.self) {
            let videoUrl = try? await LiveGifTool2.livePhotoConvertToVideo(livePhoto: livePhoto)
            guard let videoUrl = videoUrl else { return .failure(.unableToFindvideoUrl) }
            guard let result = try? await videoUrl.convertToGIF(maxResolution: 300, frameDelay: frameDelay, gifFps: gifFps, updateProgress: { progress in
                print("转换进度: \(progress)")
            }) else { return .failure(.gifResultNil) }
            return result
        }
        
        return .failure(.unknown)
    }
    
    public func createGif(frames: [UIImage], frameDelay: CGFloat = 0.03) async throws -> Result<GifResult, GifError> {
        do {
            return try await frames.createGif(frameDelay: frameDelay)
        } catch {
            return .failure(.unknown)
        }
    }
    
    public func cleanup() {
        //
//        try FileManager.default.removeItem(at: resultingFileURL)
    }
   
}

