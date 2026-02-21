import Dependencies
import Foundation
import LiveGifKit
import Observation
import OSLog
import PhotosUI
import SwiftUI

@MainActor
@Observable
final class LiveGIFDemoViewModel {
    enum SourceMode: String, CaseIterable, Identifiable {
        case livePhoto = "Live Photo"
        case image = "Image"

        var id: String { rawValue }
    }

    @ObservationIgnored @Dependency(\.gifToolKit) private var gifToolKit
    @ObservationIgnored private var generationTask: Task<GIFGenerationResult, Error>?
    @ObservationIgnored private var pickerTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "LiveGIFKit.Demo", category: "ViewModel")

    var sourceMode: SourceMode = .livePhoto {
        didSet { scheduleAutoGenerate() }
    }
    var pickerItem: PhotosPickerItem?
    var sourceImage: GIFImage?
    var sourceLivePhoto: PHLivePhoto?
    var generatedResult: GIFGenerationResult?
    var singleBackgroundRemovedImage: GIFImage?
    var recommendedImages: [GIFImage] = []
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
    var lastErrorMessage = ""

    func warmUp() {
        operationTask?.cancel()
        operationTask = Task { @MainActor in
            logger.info("Preheat start")
            try? await gifToolKit.preheat()
            logger.info("Preheat end")
        }
    }

    func handlePickerChange() {
        guard let pickerItem else {
            return
        }
        pickerTask?.cancel()
        pickerTask = Task { @MainActor in
            isLoadingSource = true
            defer { isLoadingSource = false }
            do {
                logger.info("Picker load start")
                if let imageData = try await pickerItem.loadTransferable(type: Data.self) {
                    sourceImage = image(from: imageData)
                }
                sourceLivePhoto = try await pickerItem.loadTransferable(type: PHLivePhoto.self)
                logger.info("Picker load done; generating")
                scheduleAutoGenerate()
            } catch {
                lastErrorMessage = error.localizedDescription
                logger.error("Picker load failed: \(error.localizedDescription)")
            }
        }
    }

    func generateGIF() async throws {
        guard let source = currentSource() else {
            return
        }

        let request = GIFGenerationRequest(
            source: source,
            options: GIFGenerationOptions(
                outputFPS: outputFPS,
                maxResolution: 500,
                removeBackground: removeBackground,
                includeOriginalFrames: true,
                watermarks: makeWatermarks()
            )
        )
        try await startGeneration(with: request)
    }

    func saveGIF() {
        guard let generatedResult else {
            return
        }
        operationTask?.cancel()
        operationTask = Task { @MainActor in
            do {
                logger.info("Save GIF start")
                _ = try await gifToolKit.save(.init(payload: .fileURL(generatedResult.fileURL)))
                saveStatus = "Saved"
                logger.info("Save GIF success")
            } catch {
                saveStatus = "Failed"
                lastErrorMessage = error.localizedDescription
                logger.error("Save GIF failed: \(error.localizedDescription)")
            }
        }
    }

    func removeBackgroundFromSourceImage() {
        guard let sourceImage else {
            return
        }
        operationTask?.cancel()
        operationTask = Task { @MainActor in
            isRemovingBackground = true
            defer { isRemovingBackground = false }
            do {
                logger.info("Single image remove background start")
                let image = try await gifToolKit.removeBackground(from: sourceImage)
                generatedResult = nil
                singleBackgroundRemovedImage = image
                lastErrorMessage = ""
                logger.info("Single image remove background done")
            } catch {
                lastErrorMessage = error.localizedDescription
                logger.error("Single image remove background failed: \(error.localizedDescription)")
            }
        }
    }

    func loadRecommendations() {
        operationTask?.cancel()
        operationTask = Task { @MainActor in
            do {
                let request = GIFRecommendationRequest(days: 30)
                logger.info("Recommendations start")
                let images = try await gifToolKit.fetchRecommendedImages(request)
                recommendedImages = images
                showRecommendations = true
                logger.info("Recommendations done: \(images.count)")
            } catch {
                lastErrorMessage = error.localizedDescription
                logger.error("Recommendations failed: \(error.localizedDescription)")
            }
        }
    }

    func cleanup() {
        operationTask?.cancel()
        operationTask = Task { @MainActor in
            logger.info("Cleanup start")
            try? await gifToolKit.cleanup(.allTemporaryGIFFiles)
            logger.info("Cleanup end")
        }
    }

    private func scheduleAutoGenerate() {
        guard currentSource() != nil else {
            return
        }
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else {
                return
            }
            try? await generateGIF()
        }
    }

    private func startGeneration(with request: GIFGenerationRequest) async throws {
        generationTask?.cancel()
        isGenerating = true
        let toolKit = gifToolKit

        let task = Task<GIFGenerationResult, Error>(priority: .userInitiated) { @MainActor in
            logger.info("Generate GIF start")
            return try await toolKit.generateGIF(request)
        }
        generationTask = task

        do {
            let result = try await task.value
            guard !Task.isCancelled else {
                isGenerating = false
                return
            }
            generatedResult = result
            singleBackgroundRemovedImage = nil
            logger.info("Generate GIF done with \(result.frames.count) frames")
            lastErrorMessage = ""
            isGenerating = false
        } catch is CancellationError {
            isGenerating = false
        } catch {
            lastErrorMessage = error.localizedDescription
            logger.error("Generate GIF failed: \(error.localizedDescription)")
            isGenerating = false
            throw error
        }
    }

    private func currentSource() -> GIFGenerationSource? {
        switch sourceMode {
        case .image:
            guard let sourceImage else {
                return nil
            }
            return .images([sourceImage], adjustOrientation: true)
        case .livePhoto:
            if let sourceLivePhoto {
                return .livePhoto(sourceLivePhoto, sourceFPS: sourceFPS)
            }
            guard let sourceImage else {
                return nil
            }
            return .images([sourceImage], adjustOrientation: true)
        }
    }

    private func makeWatermarks() -> [GIFWatermark] {
        guard !watermarkText.isEmpty else {
            return []
        }
        return [
            GIFWatermark(
                content: .text(watermarkText, font: .systemFont(ofSize: 26), textColor: .red, backgroundColor: .clear),
                position: watermarkLocation
            ),
        ]
    }

    private func image(from data: Data) -> GIFImage? {
        #if canImport(UIKit)
        GIFImage(data: data)
        #else
        GIFImage(data: data)
        #endif
    }
}
