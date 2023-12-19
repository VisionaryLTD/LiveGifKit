//
//  FetchPhoto.swift
//
//
//  Created by tangxiaojun on 2023/12/19.
//

import Foundation
import Photos
import UIKit

public struct FetchPhoto {
    
    public static func fetch(days: Int = 30) -> [UIImage] {
        var images: [UIImage] = []
        // 获取最近三十天的照片
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "creationDate > %@", Calendar.current.date(byAdding: .day, value: -days, to: Date())! as NSDate)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        fetchResult.enumerateObjects { asset, _, _ in
            if asset.mediaSubtypes.contains(.photoLive) {
                print("这个为实况照片")
            } else {
                print("普通照片")
            }
            let requestOptions = PHImageRequestOptions()
            requestOptions.isSynchronous = true
            PHCachingImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 50, height: 50), contentMode: .aspectFit, options: requestOptions) { image, _ in
                guard let image = image else { return }
                if image.recognition() {
                    images.append(image)
                }
            }
        }
        
        return images
    }
}
