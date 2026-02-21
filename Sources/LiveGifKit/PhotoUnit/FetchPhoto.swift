import Foundation
import Photos

public struct FetchPhoto {
    public static func fetch(days: Int = 30, targetSize: CGSize = CGSize(width: 50, height: 50)) -> [GIFImage] {
        var images: [GIFImage] = []
        let fetchOptions = PHFetchOptions()
        let fromDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        fetchOptions.predicate = NSPredicate(format: "creationDate > %@", fromDate as NSDate)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        fetchResult.enumerateObjects { asset, _, _ in
            let requestOptions = PHImageRequestOptions()
            requestOptions.isSynchronous = true
            PHCachingImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: requestOptions
            ) { image, _ in
                guard let image = image else { return }
                if image.recognition() {
                    images.append(image)
                }
            }
        }

        return images
    }
}
