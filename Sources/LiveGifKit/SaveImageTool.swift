//
//  File.swift
//  
//
//  Created by 汤小军 on 2023/12/11.
//

import Foundation
import Photos
import PhotosUI

public struct SaveImageTool {
    public static func saveImage(gifUrl: URL) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            if status == .authorized {
                try? PHPhotoLibrary.shared().performChangesAndWait {
                    let assetChangeRequest = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: gifUrl)
                    let assetPlaceHolder = assetChangeRequest?.placeholderForCreatedAsset
                    createAlbum(albumName: "小军自定义的") { assertCollect in
                        let albumChangeRequest = PHAssetCollectionChangeRequest(for: assertCollect)
                        let enumeration: NSArray = [assetPlaceHolder!]
                        albumChangeRequest!.addAssets(enumeration)
                        print("成功保存")
                    }
                }
            }
        }
    }
    
    static func findAlbum(name: String) -> PHAssetCollection? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", name)
        let collection = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
        
        return collection.firstObject
    }
    
    static func createAlbum(albumName: String, completion: @escaping (PHAssetCollection) -> Void) {
        if let assetCollection = self.findAlbum(name: albumName) {
            completion(assetCollection)
            return
        }
        PHPhotoLibrary.shared().performChanges({
            PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
        }){ success, error in
            if success, let assetCollection = self.findAlbum(name: albumName) {
                completion(assetCollection)
            }
        }
    }
}
