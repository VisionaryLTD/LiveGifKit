import Dependencies
#if canImport(CoreTransferable)
import CoreTransferable
#endif
import Foundation
import ImageIO
import LiveGifKit
import Observation
import OSLog
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

@MainActor
@Observable
final class LiveGIFDemoViewModel {
    enum SourceMode: String, CaseIterable, Identifiable {
        case livePhoto = "Live Photo"
        case image = "Image"

        var id: String { rawValue }
    }

    @ObservationIgnored @Dependency(\.gifToolKit) private var gifToolKit
    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var pickerTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "LiveGIFKit.Demo", category: "ViewModel")

    var sourceMode: SourceMode = .livePhoto {
        didSet { scheduleAutoGenerate() }
    }
    var pickerItem: PhotosPickerItem?
    var sourceImageURL: URL?
    var sourceLivePhotoVideoURL: URL?
    var generatedResult: GIFGenerationURLResult?
    var singleBackgroundRemovedImageURL: URL?
    var generatedFrameURLs: [URL] = []
    var recommendedAssets: [GIFRecommendedAsset] = []
    var isLoadingSource = false
    var isRemovingBackground = false
    var removeBackground = false {
        didSet { scheduleAutoGenerate() }
    }
    var outputFPS = 30.0 {
        didSet { scheduleAutoGenerate() }
    }
    var sourceFPS = 15.0 {
        didSet { scheduleAutoGenerate() }
    }
    var showRecommendations = false
    var showFrames = false
    var watermarkText = "" {
        didSet { scheduleAutoGenerate() }
    }
    var watermarkLocation: GIFWatermarkPosition = .center {
        didSet { scheduleAutoGenerate() }
    }
    var saveStatus = ""
    var isGenerating = false
    var generationProgress: Double?
    var generationStatus = "Idle"
    var lastErrorMessage = ""

    var canGenerate: Bool {
        currentSource() != nil
    }

    var canRemoveBackground: Bool {
        sourceImageURL != nil
    }

    var isProgressVisible: Bool {
        isLoadingSource || isGenerating || isRemovingBackground
    }

    func warmUp() {
        operationTask?.cancel()
        operationTask = Task { [gifToolKit, logger] in
            logger.info("Preheat start")
            try? await gifToolKit.preheat()
            logger.info("Preheat end")
        }
    }

    func handlePickerChange() {
        guard let pickerItem else {
            sourceImageURL = nil
            sourceLivePhotoVideoURL = nil
            return
        }

        pickerTask?.cancel()
        pickerTask = Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                isLoadingSource = true
                lastErrorMessage = ""
            }
            defer {
                Task { @MainActor in
                    isLoadingSource = false
                }
            }

            do {
                let imageURL = try await loadImageURL(from: pickerItem)
                let livePhotoVideoURL: URL?
                switch sourceMode {
                case .livePhoto:
                    livePhotoVideoURL = try await loadLivePhotoVideoURL(from: pickerItem)
                case .image:
                    livePhotoVideoURL = nil
                }

                await MainActor.run {
                    sourceImageURL = imageURL
                    sourceLivePhotoVideoURL = livePhotoVideoURL
                    generatedResult = nil
                    singleBackgroundRemovedImageURL = nil
                    generatedFrameURLs = []
                    if sourceMode == .livePhoto && livePhotoVideoURL == nil {
                        lastErrorMessage = "Failed to load live photo video resource."
                    } else {
                        scheduleAutoGenerate()
                    }
                }
            } catch {
                await MainActor.run {
                    lastErrorMessage = error.localizedDescription
                }
                logger.error("Picker load failed: \(error.localizedDescription)")
            }
        }
    }

    func generateGIF() {
        guard let source = currentSource() else {
            return
        }

        generationTask?.cancel()
        let request = GIFGenerationURLRequest(
            source: source,
            options: GIFGenerationOptions(
                outputFPS: outputFPS,
                maxResolution: 500,
                removeBackground: removeBackground,
                watermarks: makeWatermarks()
            )
        )

        generationTask = Task(priority: .userInitiated) { [gifToolKit, logger] in
            do {
                isGenerating = true
                generationProgress = nil
                generationStatus = "Preparing"

                for try await event in gifToolKit.generateGIF(request) {
                    try Task.checkCancellation()
                    switch event {
                    case .preparingFrames(let completed, let total):
                        generationStatus = "Preparing Frames"
                        generationProgress = progress(completed: completed, total: total)
                    case .encoding(let completed, let total):
                        generationStatus = "Encoding GIF"
                        generationProgress = progress(completed: completed, total: total)
                    case .completed(let result):
                        generatedResult = result
                        singleBackgroundRemovedImageURL = nil
                        generatedFrameURLs = []
                        saveStatus = ""
                        lastErrorMessage = ""
                    }
                }

                isGenerating = false
                generationStatus = "Idle"
                logger.info("Generate GIF done")
            } catch is CancellationError {
                isGenerating = false
                generationStatus = "Idle"
            } catch {
                isGenerating = false
                generationStatus = "Failed"
                lastErrorMessage = error.localizedDescription
                logger.error("Generate GIF failed: \(error.localizedDescription)")
            }
        }
    }

    func saveGIF() {
        guard let generatedResult else {
            return
        }

        operationTask?.cancel()
        operationTask = Task { [gifToolKit, logger] in
            do {
                logger.info("Save GIF start")
                _ = try await gifToolKit.save(.init(payload: .fileURL(generatedResult.gifURL)))
                await MainActor.run {
                    saveStatus = "Saved"
                    lastErrorMessage = ""
                }
                logger.info("Save GIF success")
            } catch {
                await MainActor.run {
                    saveStatus = "Failed"
                    lastErrorMessage = error.localizedDescription
                }
                logger.error("Save GIF failed: \(error.localizedDescription)")
            }
        }
    }

    func removeBackgroundFromSourceImage() {
        guard let sourceImageURL else {
            return
        }

        operationTask?.cancel()
        operationTask = Task { [gifToolKit, logger] in
            do {
                await MainActor.run {
                    isRemovingBackground = true
                    generationStatus = "Removing Background"
                }

                let stream = gifToolKit.removeBackground(
                    .init(inputImageURL: sourceImageURL)
                )
                for try await event in stream {
                    switch event {
                    case .processing:
                        await MainActor.run {
                            generationProgress = nil
                        }
                    case .completed(let result):
                        await MainActor.run {
                            generatedResult = nil
                            singleBackgroundRemovedImageURL = result.imageURL
                            generatedFrameURLs = []
                            lastErrorMessage = ""
                        }
                    }
                }

                await MainActor.run {
                    isRemovingBackground = false
                    generationStatus = "Idle"
                }
                logger.info("Single image remove background done")
            } catch {
                await MainActor.run {
                    isRemovingBackground = false
                    generationStatus = "Failed"
                    lastErrorMessage = error.localizedDescription
                }
                logger.error("Single image remove background failed: \(error.localizedDescription)")
            }
        }
    }

    func loadRecommendations() {
        operationTask?.cancel()
        operationTask = Task { [gifToolKit, logger] in
            do {
                logger.info("Recommendations start")
                let assets = try await gifToolKit.fetchRecommendedAssets(.init(days: 30))
                await MainActor.run {
                    recommendedAssets = assets
                    showRecommendations = true
                    lastErrorMessage = ""
                }
                logger.info("Recommendations done: \(assets.count)")
            } catch {
                await MainActor.run {
                    lastErrorMessage = error.localizedDescription
                }
                logger.error("Recommendations failed: \(error.localizedDescription)")
            }
        }
    }

    func showFramesSheet() {
        guard let generatedResult else {
            return
        }

        operationTask?.cancel()
        operationTask = Task { [logger] in
            do {
                let frameURLs: [URL]
                if generatedFrameURLs.isEmpty {
                    frameURLs = try extractFrameURLs(from: generatedResult.gifURL)
                } else {
                    frameURLs = generatedFrameURLs
                }
                await MainActor.run {
                    generatedFrameURLs = frameURLs
                    showFrames = true
                }
            } catch {
                await MainActor.run {
                    lastErrorMessage = error.localizedDescription
                }
                logger.error("Load frame previews failed: \(error.localizedDescription)")
            }
        }
    }

    func cleanup() {
        operationTask?.cancel()
        operationTask = Task { [gifToolKit, logger] in
            logger.info("Cleanup start")
            try? await gifToolKit.cleanup(.allTemporaryGIFFiles)
            await MainActor.run {
                generatedFrameURLs = []
            }
            logger.info("Cleanup end")
        }
    }

    private func scheduleAutoGenerate() {
        guard canGenerate else {
            return
        }

        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else {
                return
            }
            generateGIF()
        }
    }

    private func currentSource() -> GIFGenerationURLSource? {
        switch sourceMode {
        case .image:
            guard let sourceImageURL else {
                return nil
            }
            return .imageFiles([sourceImageURL], adjustOrientation: true)
        case .livePhoto:
            guard let sourceLivePhotoVideoURL else {
                return nil
            }
            return .livePhotoVideoFile(sourceLivePhotoVideoURL, sourceFPS: sourceFPS)
        }
    }

    private func makeWatermarks() -> [GIFWatermark] {
        guard !watermarkText.isEmpty else {
            return []
        }

        return [
            GIFWatermark(
                content: .text(
                    watermarkText,
                    font: .systemFont(ofSize: 26),
                    textColor: .red,
                    backgroundColor: .clear
                ),
                position: watermarkLocation
            ),
        ]
    }

    private func loadImageURL(from item: PhotosPickerItem) async throws -> URL? {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            return nil
        }
        return try writeToDemoTemporaryDirectory(data: data, fileExtension: "png", prefix: "picker-image")
    }

    private func loadLivePhotoVideoURL(from item: PhotosPickerItem) async throws -> URL? {
        if let transferable = try await item.loadTransferable(type: PickedMovieFile.self) {
            return transferable.url
        }

        if let transferable = try await item.loadTransferable(type: PickedLivePhotoBundle.self) {
            return transferable.videoURL
        }

        if let transferable = try await item.loadTransferable(type: PickedMovieData.self) {
            return try writeToDemoTemporaryDirectory(
                data: transferable.data,
                fileExtension: transferable.preferredExtension,
                prefix: "picker-live"
            )
        }

        if let providerURL = try await item.loadTransferable(type: URL.self), providerURL.isFileURL {
            let fileExtension = providerURL.pathExtension.isEmpty ? "mov" : providerURL.pathExtension
            let outputURL = try demoDirectory().appending(path: "picker-live-\(UUID().uuidString).\(fileExtension)")
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            try FileManager.default.copyItem(at: providerURL, to: outputURL)
            return outputURL
        }

        let readStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard readStatus == .authorized || readStatus == .limited else {
            return nil
        }

        guard let itemIdentifier = item.itemIdentifier else {
            return nil
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [itemIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else {
            return nil
        }

        let resources = PHAssetResource.assetResources(for: asset)
        guard
            let resource = resources.first(where: {
                $0.type == .pairedVideo || $0.type == .fullSizePairedVideo || $0.type == .video
            })
        else {
            return nil
        }

        let fileExtension = resource.originalFilename.split(separator: ".").last.map(String.init) ?? "mov"
        let outputURL = try demoDirectory().appending(path: "picker-live-\(UUID().uuidString).\(fileExtension)")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(
                for: resource,
                toFile: outputURL,
                options: nil
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        return outputURL
    }

    private struct PickedMovieFile: Transferable {
        let url: URL

        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(importedContentType: .quickTimeMovie) { received in
                try copyFileToTemporaryURL(from: received.file, fallbackExtension: "mov")
            }
            FileRepresentation(importedContentType: .movie) { received in
                try copyFileToTemporaryURL(from: received.file, fallbackExtension: "mov")
            }
            FileRepresentation(importedContentType: .mpeg4Movie) { received in
                try copyFileToTemporaryURL(from: received.file, fallbackExtension: "mp4")
            }
        }

        private static func copyFileToTemporaryURL(from sourceURL: URL, fallbackExtension: String) throws -> Self {
            let fileExtension = sourceURL.pathExtension.isEmpty ? fallbackExtension : sourceURL.pathExtension
            let destinationURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "GIF-Demo-PickedMovie-\(UUID().uuidString).\(fileExtension)")
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return Self(url: destinationURL)
        }
    }

    private struct PickedMovieData: Transferable {
        let data: Data
        let preferredExtension: String

        static var transferRepresentation: some TransferRepresentation {
            DataRepresentation(importedContentType: .quickTimeMovie) { data in
                Self(data: data, preferredExtension: "mov")
            }
            DataRepresentation(importedContentType: .movie) { data in
                Self(data: data, preferredExtension: "mov")
            }
            DataRepresentation(importedContentType: .mpeg4Movie) { data in
                Self(data: data, preferredExtension: "mp4")
            }
        }
    }

    private struct PickedLivePhotoBundle: Transferable {
        let videoURL: URL

        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(importedContentType: .livePhoto) { received in
                let candidates = findVideoCandidates(in: received.file)
                guard let sourceURL = candidates.first else {
                    throw GifError.unableToFindvideoUrl
                }
                let fileExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
                let destinationURL = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appending(path: "GIF-Demo-LivePhoto-\(UUID().uuidString).\(fileExtension)")
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                return Self(videoURL: destinationURL)
            }
        }

        private static func findVideoCandidates(in rootURL: URL) -> [URL] {
            var candidates: [URL] = []
            if rootURL.pathExtension.lowercased() == "mov" || rootURL.pathExtension.lowercased() == "mp4" {
                candidates.append(rootURL)
            }

            if let enumerator = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    let ext = fileURL.pathExtension.lowercased()
                    guard ext == "mov" || ext == "mp4" else {
                        continue
                    }
                    candidates.append(fileURL)
                }
            }

            return candidates.sorted { lhs, rhs in
                let lhsSize = (try? lhs.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let rhsSize = (try? rhs.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return lhsSize > rhsSize
            }
        }
    }

    private func progress(completed: Int, total: Int?) -> Double? {
        guard let total, total > 0 else {
            return nil
        }
        return min(max(Double(completed) / Double(total), 0), 1)
    }

    private func demoDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "GIF-Demo")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeToDemoTemporaryDirectory(
        data: Data,
        fileExtension: String,
        prefix: String
    ) throws -> URL {
        let fileURL = try demoDirectory().appending(path: "\(prefix)-\(UUID().uuidString).\(fileExtension)")
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private func extractFrameURLs(from gifURL: URL) throws -> [URL] {
        guard let source = CGImageSourceCreateWithURL(gifURL as CFURL, nil) else {
            throw GifError.unableToReadFile
        }

        let count = CGImageSourceGetCount(source)
        guard count > 0 else {
            return []
        }

        let framesDirectory = try demoDirectory().appending(path: "frames-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: framesDirectory, withIntermediateDirectories: true)

        var frameURLs: [URL] = []
        frameURLs.reserveCapacity(count)
        for index in 0..<count {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                continue
            }
            let image = platformImage(cgImage: frame)
            guard let pngData = platformPNGData(from: image) else {
                continue
            }
            let frameURL = framesDirectory.appending(path: "frame-\(index).png")
            try pngData.write(to: frameURL, options: .atomic)
            frameURLs.append(frameURL)
        }
        return frameURLs
    }

    private func platformImage(cgImage: CGImage) -> GIFImage {
        #if canImport(UIKit)
        GIFImage(cgImage: cgImage)
        #else
        GIFImage(cgImage: cgImage, size: .zero)
        #endif
    }

    private func platformPNGData(from image: GIFImage) -> Data? {
        #if canImport(UIKit)
        image.pngData()
        #else
        guard
            let tiffData = image.tiffRepresentation,
            let bitmapImage = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        return bitmapImage.representation(using: .png, properties: [:])
        #endif
    }
}
