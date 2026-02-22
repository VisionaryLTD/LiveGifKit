import Foundation
import Photos

public struct FetchPhoto {
    public static func fetchAssets(
        days: Int = 30,
        targetSize: CGSize = CGSize(width: 50, height: 50),
        outputDirectoryURL: URL? = nil
    ) throws -> [GIFRecommendedAsset] {
        let outputDirectory = outputDirectoryURL
            ?? GIFTemporaryPaths.baseDirectory.appending(path: "Recommendations")
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        var assets: [GIFRecommendedAsset] = []
        let fetchOptions = PHFetchOptions()
        let fromDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        fetchOptions.predicate = NSPredicate(format: "creationDate > %@", fromDate as NSDate)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        fetchResult.enumerateObjects { asset, _, _ in
            let requestOptions = PHImageRequestOptions()
            requestOptions.isSynchronous = true
            requestOptions.resizeMode = .fast

            PHCachingImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: requestOptions
            ) { image, _ in
                guard
                    let image,
                    image.recognition(),
                    let data = image.gifPNGData
                else {
                    return
                }

                let fileName = "\(UUID().uuidString).png"
                let fileURL = outputDirectory.appending(path: fileName)
                do {
                    try data.write(to: fileURL, options: .atomic)
                    assets.append(
                        GIFRecommendedAsset(
                            assetLocalIdentifier: asset.localIdentifier,
                            thumbnailURL: fileURL
                        )
                    )
                } catch {
                    return
                }
            }
        }

        return assets
    }
}
