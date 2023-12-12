//
//  File.swift
//
//
//  Created by tangxiaojun on 2023/12/12.
//

import Foundation
import PhotosUI
 
public enum AlbumTool {
    static let albumName = "LifeStickers"
}

public extension AlbumTool {
    enum Method {
        case url(URL)
        case image(UIImage)
        var request: PHAssetChangeRequest {
            switch self {
            case .url(let url):
                return .creationRequestForAssetFromImage(atFileURL: url)!
            case .image(let uiImage):
                return .creationRequestForAsset(from: uiImage)
            }
        }
    }
    
    static func save(method: Method) async throws -> String {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        switch status {
        case .authorized:
            do {
                let collection = try await createOrFindAlbum(name: albumName)
                try PHPhotoLibrary.shared().performChangesAndWait {
                    let assetChangeRequest = method.request
                    let assetPlaceHolder = assetChangeRequest.placeholderForCreatedAsset
                    let albumChangeRequest = PHAssetCollectionChangeRequest(for: collection)
                    let enumeration: NSArray = [assetPlaceHolder!]
                    albumChangeRequest!.addAssets(enumeration)
                }
                return "成功保存"
            }
            catch {
                return "保存失败"
            }
            
        default:
            return "相册权限不够"
        }
    }
}
    
public extension AlbumTool {
    static func album(name: String) -> PHAssetCollection? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", name)
        let collection = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
        return collection.firstObject
    }
    
    static func createOrFindAlbum(name: String) async throws -> PHAssetCollection {
        if let album = album(name: name) {
            return album
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            }) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if success, let assetCollection = self.album(name: name) {
                    continuation.resume(returning: assetCollection)
                } else {
                    fatalError()
                }
            }
        }
    }
}
