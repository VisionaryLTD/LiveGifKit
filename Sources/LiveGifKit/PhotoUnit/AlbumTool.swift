import Foundation
import Photos

internal enum AlbumTool {
    static let albumName = "LifeStickers"
}

@available(*, deprecated, message: "Use GIFSaveRequest and GIFSavePayload.")
public enum Method {
    case url(URL)
    case image(GIFImage)
}

extension AlbumTool {
    @available(*, deprecated, message: "Use save(request:) with GIFSaveRequest.")
    static func save(method: Method) async throws {
        let saveRequest: GIFSaveRequest
        switch method {
        case .url(let url):
            saveRequest = GIFSaveRequest(payload: .fileURL(url))
        case .image(let image):
            saveRequest = GIFSaveRequest(payload: .image(image))
        }
        _ = try await save(request: saveRequest)
    }

    static func save(request: GIFSaveRequest) async throws -> GIFSaveResult {
        let albumName: String
        switch request.destination {
        case .photoLibrary(let name):
            albumName = name
        }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        switch status {
        case .authorized, .limited:
            do {
                let collection = try await createOrFindAlbum(name: albumName)
                var localIdentifier: String?
                try await PHPhotoLibrary.shared().performChanges {
                    let albumRequest = PHAssetCollectionChangeRequest(for: collection)
                    switch request.payload {
                    case .fileURL(let url):
                        guard let assetRequest = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url) else {
                            return
                        }
                        localIdentifier = assetRequest.placeholderForCreatedAsset?.localIdentifier
                        if let placeholder = assetRequest.placeholderForCreatedAsset {
                            albumRequest?.addAssets([placeholder] as NSArray)
                        }
                    case .image(let image):
                        #if canImport(UIKit)
                        let assetRequest = PHAssetChangeRequest.creationRequestForAsset(from: image)
                        localIdentifier = assetRequest.placeholderForCreatedAsset?.localIdentifier
                        if let placeholder = assetRequest.placeholderForCreatedAsset {
                            albumRequest?.addAssets([placeholder] as NSArray)
                        }
                        #else
                        guard let png = image.gifPNGData else {
                            return
                        }
                        let assetRequest = PHAssetCreationRequest.forAsset()
                        assetRequest.addResource(with: .photo, data: png, options: nil)
                        localIdentifier = assetRequest.placeholderForCreatedAsset?.localIdentifier
                        if let placeholder = assetRequest.placeholderForCreatedAsset {
                            albumRequest?.addAssets([placeholder] as NSArray)
                        }
                        #endif
                    }
                }
                return GIFSaveResult(localIdentifier: localIdentifier)
            }
            catch {
                throw AlbumToolError.saveFail
            }
        case .denied:
            throw AlbumToolError.denied
        case .notDetermined:
            throw AlbumToolError.notDetermined
        default:
            throw AlbumToolError.unknown
        }
    }
}
    
extension AlbumTool {
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
                    continuation.resume(throwing: AlbumToolError.saveFail)
                }
            }
        }
    }
}
