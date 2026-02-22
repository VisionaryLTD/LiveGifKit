import Foundation
import Photos

internal enum AlbumTool {
    static func save(request: GIFSaveURLRequest) async throws -> GIFSaveResult {
        let addOnlyStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        let status: PHAuthorizationStatus
        switch addOnlyStatus {
        case .denied:
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        default:
            status = addOnlyStatus
        }

        switch status {
        case .authorized, .limited:
            break
        case .denied, .restricted:
            throw AlbumToolError.denied
        case .notDetermined:
            throw AlbumToolError.notDetermined
        @unknown default:
            throw AlbumToolError.unknown
        }

        let albumName: String
        switch request.destination {
        case .photoLibrary(let name):
            albumName = name
        }

        let collection = try await createOrFindAlbum(name: albumName)
        var localIdentifier: String?

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let albumRequest = PHAssetCollectionChangeRequest(for: collection)
                switch request.payload {
                case .fileURL(let fileURL):
                    let assetRequest = PHAssetCreationRequest.forAsset()
                    assetRequest.addResource(with: .photo, fileURL: fileURL, options: nil)
                    localIdentifier = assetRequest.placeholderForCreatedAsset?.localIdentifier
                    if let placeholder = assetRequest.placeholderForCreatedAsset {
                        albumRequest?.addAssets([placeholder] as NSArray)
                    }
                }
            }
        } catch {
            throw AlbumToolError.saveFail
        }

        return GIFSaveResult(localIdentifier: localIdentifier)
    }
}

private extension AlbumTool {
    static func album(name: String) -> PHAssetCollection? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", name)
        let collection = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: fetchOptions
        )
        return collection.firstObject
    }

    static func createOrFindAlbum(name: String) async throws -> PHAssetCollection {
        if let existingAlbum = album(name: name) {
            return existingAlbum
        }

        return try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            }) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if success, let createdAlbum = album(name: name) {
                    continuation.resume(returning: createdAlbum)
                } else {
                    continuation.resume(throwing: AlbumToolError.saveFail)
                }
            }
        }
    }
}
