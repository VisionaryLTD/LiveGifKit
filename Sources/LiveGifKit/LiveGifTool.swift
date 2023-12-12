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
    public let frames: [CGImage]
    
    public var data: Data {
        try! Data(contentsOf: url)
    }
    
    public var uiImages: [UIImage] {
        return self.frames.map({
            if let videoTransform = self.videoTransform {
                return UIImage(cgImage: $0, scale: 1.0, orientation: LiveGifTool2.getImageOrientation(transform: videoTransform))
            }
            return UIImage(cgImage: $0)
            
        })
    }
    
    public let videoTransform: CGAffineTransform?
    
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
    func createGif(pickerItem: PhotosPickerItem, frameDelay: CGFloat) async throws -> Result<GifResult, GifError>
    func createGif(frames: [CGImage], frameDelay: CGFloat) async throws -> Result<GifResult, GifError>
    func cleanup()
}

public class LiveGifTool: GifTool {
    public static let shared = LiveGifTool()
    
    public func saveToAlbum(from url: URL, albumName: String?) async throws -> Bool {
        return false
    }
    
    public func createGif(pickerItem: PhotosPickerItem, frameDelay: CGFloat = 15) async throws -> Result<GifResult, GifError> {
        if let livePhoto = try? await pickerItem.loadTransferable(type: PHLivePhoto.self) {
            let videoUrl = try? await LiveGifTool2.livePhotoConvertToVideo(livePhoto: livePhoto)
            guard let videoUrl = videoUrl else { return .failure(.unableToFindvideoUrl) }
            guard let result = try? await videoUrl.convertToGIF(maxResolution: nil, frameDelay: 15, updateProgress: { progress in
                print("转换进度: \(progress)")
            }) else { return .failure(.gifResultNil) }
            return result
        }
        
        return .failure(.unknown)
    }
    
    public func createGif(frames: [CGImage], frameDelay: CGFloat = 15.0) async throws -> Result<GifResult, GifError> {
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

