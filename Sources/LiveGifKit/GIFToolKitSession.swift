import CoreGraphics
import Dispatch
import Foundation
import Observation

#if canImport(CryptoKit)
import CryptoKit
#endif

#if DEBUG && canImport(Darwin)
import Darwin
#endif

public struct GIFEditorAttributes: Sendable, Hashable {
    public enum Source: Sendable, Hashable {
        case imageFiles([URL], adjustOrientation: Bool = true)
        case livePhotoVideoFile(URL)
        case videoFile(URL)
    }

    public var source: Source?
    public var outputFPS: Double
    public var sourceFPS: Double
    public var maxResolution: CGFloat
    public var maxFrameCount: Int
    public var decodeMemoryBudgetMB: Int
    public var removeBackground: Bool
    public var enableAutoSubjectFraming: Bool
    public var subjectTargetFillRatio: Double
    public var subjectPaddingRatio: Double
    public var subjectMaxUpscale: Double
    public var watermarkText: String
    public var watermarkPosition: GIFWatermarkPosition
    public var exportMaxLongEdge: CGFloat?
    public var exportMaxFileSizeBytes: Int?

    public init(
        source: Source? = nil,
        outputFPS: Double = 30,
        sourceFPS: Double = 15,
        maxResolution: CGFloat = 500,
        maxFrameCount: Int = 150,
        decodeMemoryBudgetMB: Int = 64,
        removeBackground: Bool = false,
        enableAutoSubjectFraming: Bool = true,
        subjectTargetFillRatio: Double = 0.70,
        subjectPaddingRatio: Double = 0.08,
        subjectMaxUpscale: Double = 2.0,
        watermarkText: String = "",
        watermarkPosition: GIFWatermarkPosition = .center,
        exportMaxLongEdge: CGFloat? = nil,
        exportMaxFileSizeBytes: Int? = nil
    ) {
        self.source = source
        self.outputFPS = outputFPS
        self.sourceFPS = sourceFPS
        self.maxResolution = maxResolution
        self.maxFrameCount = max(1, maxFrameCount)
        self.decodeMemoryBudgetMB = max(1, decodeMemoryBudgetMB)
        self.removeBackground = removeBackground
        self.enableAutoSubjectFraming = enableAutoSubjectFraming
        self.subjectTargetFillRatio = subjectTargetFillRatio
        self.subjectPaddingRatio = subjectPaddingRatio
        self.subjectMaxUpscale = subjectMaxUpscale
        self.watermarkText = watermarkText
        self.watermarkPosition = watermarkPosition
        self.exportMaxLongEdge = exportMaxLongEdge
        self.exportMaxFileSizeBytes = exportMaxFileSizeBytes
    }
}

public struct GIFSessionMemoryTelemetry: Sendable {
    public let residentMB: Double
    public let peakResidentMB: Double

    public init(residentMB: Double, peakResidentMB: Double) {
        self.residentMB = residentMB
        self.peakResidentMB = peakResidentMB
    }
}

@MainActor
@Observable
public final class GIFToolKitSession {
    public enum GenerationState: Sendable, Equatable {
        case idle
        case preparingPreview
        case waitingPreview
        case encodingGIF
        case failed
    }

    public enum PreviewState: Sendable, Equatable {
        case idle
        case preparing
        case ready
        case failed
    }

    public var attributes: GIFEditorAttributes {
        didSet {
            schedulePreviewPreparation()
        }
    }

    public private(set) var generationResult: GIFGenerationURLResult?
    public private(set) var generationProgress: Double?
    public private(set) var generationState: GenerationState
    public var generationStatus: String {
        generationState.statusText
    }
    public private(set) var isGenerating: Bool
    public private(set) var lastErrorMessage: String
    public private(set) var memoryTelemetry: GIFSessionMemoryTelemetry
    public private(set) var lastEffectiveSourceFPS: Double?
    public private(set) var lastEffectiveMaxResolution: CGFloat?
    public private(set) var lastEstimatedDecodeBytes: Int?
    public private(set) var lastExportFileSizeBytes: Int?
    public private(set) var lastExportPixelSize: CGSize?
    public private(set) var lastExportFPS: Double?
    public private(set) var lastExportPassCount: Int
    public private(set) var lastExportStatus: String

    public private(set) var previewFrameURLs: [URL]
    public private(set) var previewPixelSize: CGSize?
    public private(set) var isPreparingPreview: Bool
    public private(set) var previewState: PreviewState
    public var previewStatus: String {
        previewState.statusText
    }

    @ObservationIgnored private let gifToolKit: any GIFToolKit
    @ObservationIgnored private let videoFrameExtractor: any GIFVideoFrameExtracting
    @ObservationIgnored private let backgroundRemover: any GIFBackgroundRemoving
    @ObservationIgnored private let encoding: any GIFEncoding
    @ObservationIgnored private let debounceDuration: Duration
    @ObservationIgnored private let maxCachedResults: Int
    @ObservationIgnored private let maxCacheBytesOnDisk: Int
    @ObservationIgnored private let sessionDirectory: URL
    @ObservationIgnored private let previewDirectory: URL
    @ObservationIgnored private let generatedDirectory: URL
    @ObservationIgnored private let lifetimeCleanup: GIFSessionLifetimeCleanup

    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<GIFPreparedPreviewOutput, Error>?
    @ObservationIgnored private var previewTaskKey: GIFPreviewCacheKey?
    @ObservationIgnored private var previewCache: [GIFPreviewCacheKey: GIFPreviewCacheEntry] = [:]
    @ObservationIgnored private var previewLRUKeys: [GIFPreviewCacheKey] = []
    @ObservationIgnored private var latestPreparedPreviewKey: GIFPreviewCacheKey?
    @ObservationIgnored private var isSavingGIF = false

    @ObservationIgnored private var memoryPressureObserver: GIFMemoryPressureObserver?
    @ObservationIgnored private var isHandlingMemoryPressure = false

    #if DEBUG
    @ObservationIgnored internal private(set) var previewPreparationCount = 0
    @ObservationIgnored internal private(set) var finalEncodeCount = 0
    #endif

    public convenience init(
        gifToolKit: any GIFToolKit,
        debounceDuration: Duration = .milliseconds(300),
        maxCachedResults: Int = 20
    ) {
        self.init(
            gifToolKit: gifToolKit,
            videoFrameExtractor: GIFVideoFrameExtractorLive(),
            backgroundRemover: GIFBackgroundRemoverLive(),
            encoding: GIFEncodingLive(),
            debounceDuration: debounceDuration,
            maxCachedResults: maxCachedResults,
            maxCacheBytesOnDisk: 120 * 1024 * 1024
        )
    }

    internal init(
        gifToolKit: any GIFToolKit,
        videoFrameExtractor: any GIFVideoFrameExtracting,
        backgroundRemover: any GIFBackgroundRemoving,
        encoding: any GIFEncoding,
        debounceDuration: Duration = .milliseconds(300),
        maxCachedResults: Int = 20,
        maxCacheBytesOnDisk: Int = 120 * 1024 * 1024
    ) {
        self.gifToolKit = gifToolKit
        self.videoFrameExtractor = videoFrameExtractor
        self.backgroundRemover = backgroundRemover
        self.encoding = encoding
        self.debounceDuration = debounceDuration
        self.maxCachedResults = max(1, maxCachedResults)
        self.maxCacheBytesOnDisk = max(1, maxCacheBytesOnDisk)
        attributes = GIFEditorAttributes()

        generationResult = nil
        generationProgress = nil
        generationState = .idle
        isGenerating = false
        lastErrorMessage = ""
        memoryTelemetry = GIFSessionMemoryTelemetry(residentMB: 0, peakResidentMB: 0)
        lastEffectiveSourceFPS = nil
        lastEffectiveMaxResolution = nil
        lastEstimatedDecodeBytes = nil
        lastExportFileSizeBytes = nil
        lastExportPixelSize = nil
        lastExportFPS = nil
        lastExportPassCount = 0
        lastExportStatus = "Idle"

        previewFrameURLs = []
        previewPixelSize = nil
        isPreparingPreview = false
        previewState = .idle

        let directory = GIFTemporaryPaths.baseDirectory
            .appending(path: "Sessions")
            .appending(path: UUID().uuidString)
        sessionDirectory = directory
        previewDirectory = directory.appending(path: "preview")
        generatedDirectory = directory.appending(path: "generated")
        lifetimeCleanup = GIFSessionLifetimeCleanup(directory: directory)

        try? FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: generatedDirectory, withIntermediateDirectories: true)
        setupMemoryPressureObserver()
    }

    deinit {
        debounceTask?.cancel()
        previewTask?.cancel()
    }

    public func regenerateNow() {
        debounceTask?.cancel()
        Task { @MainActor [weak self] in
            await self?.preparePreviewIfNeeded(force: true, waitForCompletion: false)
        }
    }

    public func cancelGeneration() {
        debounceTask?.cancel()
        previewTask?.cancel()
        previewTask = nil
        previewTaskKey = nil
        isPreparingPreview = false
        isSavingGIF = false
        isGenerating = false
        generationProgress = nil
        generationState = .idle
        previewState = .idle
        lastExportStatus = "Idle"
    }

    public func saveLatestGIF(
        destination: GIFSaveDestination = .photoLibrary(albumName: "LifeStickers")
    ) async throws -> GIFSaveResult {
        guard let prepared = makePreparedPreviewRequest() else {
            throw GifError.gifResultNil
        }

        isSavingGIF = true
        isGenerating = true
        generationProgress = nil
        generationState = .waitingPreview
        lastErrorMessage = ""
        lastExportFileSizeBytes = nil
        lastExportPixelSize = nil
        lastExportFPS = nil
        lastExportPassCount = 0
        lastExportStatus = "Idle"
        recordMemorySnapshot(reason: "save-start")
        defer {
            isSavingGIF = false
            if !isPreparingPreview {
                isGenerating = false
            }
            if generationState != .failed {
                generationState = .idle
            }
            generationProgress = nil
            recordMemorySnapshot(reason: "save-end")
        }

        let previewEntry = try await ensurePreviewReady(for: prepared)
        generationState = .encodingGIF

        let saveKey = prepared.key.fileStem
        let export = try await encodeFinalGIFWithBudget(
            from: previewEntry.frameURLs,
            saveKey: saveKey
        )
        generationResult = export.result
        lastExportFileSizeBytes = export.fileSizeBytes
        lastExportPixelSize = export.result.pixelSize
        lastExportFPS = export.outputFPS
        lastExportPassCount = export.passCount
        lastExportStatus = export.status

        return try await gifToolKit.save(
            GIFSaveURLRequest(
                payload: .fileURL(export.result.gifURL),
                destination: destination
            )
        )
    }

    public func removeBackground(
        _ request: GIFBackgroundRemovalURLRequest
    ) -> AsyncThrowingStream<GIFBackgroundRemovalEvent, Error> {
        gifToolKit.removeBackground(request)
    }

    public func fetchRecommendedAssets(
        _ request: GIFRecommendationURLRequest
    ) async throws -> [GIFRecommendedAsset] {
        try await gifToolKit.fetchRecommendedAssets(request)
    }

    public func preheat() async throws {
        try await gifToolKit.preheat()
    }

    public func cleanup(_ scope: GIFCleanupScope) async throws {
        cancelGeneration()

        switch scope {
        case .requestOnly:
            try await gifToolKit.cleanup(.requestOnly)
        case .allTemporaryGIFFiles:
            try await gifToolKit.cleanup(.allTemporaryGIFFiles)
            previewCache.removeAll()
            previewLRUKeys.removeAll()
            latestPreparedPreviewKey = nil
            previewFrameURLs = []
            previewPixelSize = nil
            generationResult = nil
            lastEffectiveSourceFPS = nil
            lastEffectiveMaxResolution = nil
            lastEstimatedDecodeBytes = nil
            lastExportFileSizeBytes = nil
            lastExportPixelSize = nil
            lastExportFPS = nil
            lastExportPassCount = 0
            lastExportStatus = "Idle"
            try? FileManager.default.removeItem(at: sessionDirectory)
            try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: generatedDirectory, withIntermediateDirectories: true)
        }

        recordMemorySnapshot(reason: "cleanup")
    }
}

// MARK: - Preview Preparation

private extension GIFToolKitSession {
    func schedulePreviewPreparation() {
        debounceTask?.cancel()
        guard attributes.source != nil else {
            previewTask?.cancel()
            previewTask = nil
            previewTaskKey = nil
            previewFrameURLs = []
            previewPixelSize = nil
            lastEffectiveSourceFPS = nil
            lastEffectiveMaxResolution = nil
            lastEstimatedDecodeBytes = nil
            isPreparingPreview = false
            previewState = .idle
            if !isSavingGIF {
                isGenerating = false
                generationState = .idle
                generationProgress = nil
            }
            return
        }

        debounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: debounceDuration)
            guard !Task.isCancelled else { return }
            await preparePreviewIfNeeded(force: false, waitForCompletion: false)
        }
    }

    func preparePreviewIfNeeded(force: Bool, waitForCompletion: Bool) async {
        guard let prepared = makePreparedPreviewRequest() else {
            return
        }

        if !force, let cached = cachedPreviewEntry(for: prepared.key) {
            applyPreview(entry: cached, key: prepared.key)
            return
        }

        if previewTaskKey == prepared.key, let existingPreviewTask = previewTask {
            if waitForCompletion {
                do {
                    let output = try await existingPreviewTask.value
                    applyPreparedPreview(output, for: prepared.key)
                } catch is CancellationError {
                    return
                } catch {
                    if previewTaskKey == prepared.key {
                        lastErrorMessage = error.localizedDescription
                        previewState = .failed
                        generationState = .failed
                        isPreparingPreview = false
                        if !isSavingGIF {
                            isGenerating = false
                        }
                        previewTask = nil
                        previewTaskKey = nil
                    }
                }
            }
            return
        }

        let task = launchPreviewTask(for: prepared)
        guard waitForCompletion else {
            return
        }
        do {
            let output = try await task.value
            applyPreparedPreview(output, for: prepared.key)
        } catch is CancellationError {
                return
            } catch {
            if previewTaskKey == prepared.key {
                lastErrorMessage = error.localizedDescription
                previewState = .failed
                generationState = .failed
                isPreparingPreview = false
                if !isSavingGIF {
                    isGenerating = false
                }
                previewTask = nil
                previewTaskKey = nil
            }
        }
    }

    func ensurePreviewReady(for prepared: GIFPreparedPreviewRequest) async throws -> GIFPreviewCacheEntry {
        if let cached = cachedPreviewEntry(for: prepared.key) {
            applyPreview(entry: cached, key: prepared.key)
            return cached
        }

        await preparePreviewIfNeeded(force: true, waitForCompletion: true)

        if let cached = cachedPreviewEntry(for: prepared.key) {
            applyPreview(entry: cached, key: prepared.key)
            return cached
        }
        throw GifError.gifResultNil
    }

    @discardableResult
    func launchPreviewTask(for prepared: GIFPreparedPreviewRequest) -> Task<GIFPreparedPreviewOutput, Error> {
        previewTask?.cancel()
        previewTaskKey = prepared.key

        isPreparingPreview = true
        previewState = .preparing
        generationState = .preparingPreview
        generationProgress = nil
        if !isSavingGIF {
            isGenerating = true
        }
        lastErrorMessage = ""
        recordMemorySnapshot(reason: "preview-start")
        #if DEBUG
        previewPreparationCount += 1
        #endif

        let extractor = videoFrameExtractor
        let remover = backgroundRemover
        let preparedRequest = prepared

        let task = Task.detached(priority: .userInitiated) {
            try await GIFPreviewPipeline.prepare(
                request: preparedRequest,
                videoFrameExtractor: extractor,
                backgroundRemover: remover
            )
        }
        previewTask = task

        Task { @MainActor [weak self] in
            guard let self else { return }
            await observePreviewTask(task, for: prepared.key)
        }
        return task
    }

    func observePreviewTask(
        _ task: Task<GIFPreparedPreviewOutput, Error>,
        for key: GIFPreviewCacheKey
    ) async {
        do {
            let output = try await task.value
            guard previewTaskKey == key else {
                return
            }
            applyPreparedPreview(output, for: key)
        } catch is CancellationError {
            guard previewTaskKey == key else {
                return
            }
            isPreparingPreview = false
            previewState = .idle
            if !isSavingGIF {
                isGenerating = false
                generationState = .idle
            }
            previewTask = nil
            previewTaskKey = nil
        } catch {
            guard previewTaskKey == key else {
                return
            }
            isPreparingPreview = false
            previewState = .failed
            generationState = .failed
            lastErrorMessage = error.localizedDescription
            if !isSavingGIF {
                isGenerating = false
            }
            previewTask = nil
            previewTaskKey = nil
            recordMemorySnapshot(reason: "preview-failed")
        }
    }

    func applyPreparedPreview(_ output: GIFPreparedPreviewOutput, for key: GIFPreviewCacheKey) {
        let entry = GIFPreviewCacheEntry(
            framesDirectory: output.framesDirectory,
            frameURLs: output.frameURLs,
            pixelSize: output.pixelSize,
            bytesOnDisk: output.bytesOnDisk,
            lastAccess: Date()
        )
        lastEffectiveSourceFPS = output.extractionSummary?.effectiveSourceFPS
        lastEffectiveMaxResolution = output.extractionSummary?.effectiveMaxResolution
        lastEstimatedDecodeBytes = output.extractionSummary?.estimatedDecodeBytes
        previewCache[key] = entry
        touchPreviewLRU(for: key)
        trimPreviewCacheIfNeeded(keeping: key)
        applyPreview(entry: entry, key: key)
    }

    func applyPreview(entry: GIFPreviewCacheEntry, key: GIFPreviewCacheKey) {
        previewFrameURLs = entry.frameURLs
        previewPixelSize = entry.pixelSize
        latestPreparedPreviewKey = key
        isPreparingPreview = false
        previewState = .ready
        if !isSavingGIF {
            isGenerating = false
            generationState = .idle
            generationProgress = nil
        }
        previewTask = nil
        previewTaskKey = nil
        lastErrorMessage = ""
        recordMemorySnapshot(reason: "preview-ready")
    }
}

private extension GIFToolKitSession.GenerationState {
    var statusText: String {
        switch self {
        case .idle:
            "Idle"
        case .preparingPreview:
            "Preparing Preview"
        case .waitingPreview:
            "Waiting Preview"
        case .encodingGIF:
            "Encoding GIF"
        case .failed:
            "Failed"
        }
    }
}

private extension GIFToolKitSession.PreviewState {
    var statusText: String {
        switch self {
        case .idle:
            "Idle"
        case .preparing:
            "Preparing Preview"
        case .ready:
            "Ready"
        case .failed:
            "Failed"
        }
    }
}

// MARK: - Save Encoding

private extension GIFToolKitSession {
    func encodeFinalGIFWithBudget(
        from frameURLs: [URL],
        saveKey: String
    ) async throws -> GIFEncodedExport {
        let maxFileSizeBytes = attributes.exportMaxFileSizeBytes
        let maxLongEdge = attributes.exportMaxLongEdge
        let outputFPS = max(1, attributes.outputFPS)
        var longEdge = maxLongEdge
        let hasBudget = maxFileSizeBytes != nil || maxLongEdge != nil

        for passIndex in 1...20 {
            let outputURL = generatedDirectory.appending(path: "\(saveKey)-pass-\(passIndex).gif")
            let result = try await encodeFinalGIF(
                from: frameURLs,
                outputURL: outputURL,
                outputFPS: outputFPS,
                maxLongEdge: longEdge
            )
            let fileSizeBytes = gifFileSize(for: result.gifURL)
            let resultLongEdge = max(result.pixelSize.width, result.pixelSize.height)

            let meetsFileSize = maxFileSizeBytes.map { fileSizeBytes <= $0 } ?? true
            let meetsResolution = maxLongEdge.map { resultLongEdge <= $0 + 0.5 } ?? true
            if meetsFileSize, meetsResolution {
                let status = hasBudget ? "FitInBudget" : "Unconstrained"
                return GIFEncodedExport(
                    result: result,
                    fileSizeBytes: fileSizeBytes,
                    outputFPS: outputFPS,
                    passCount: passIndex,
                    status: status
                )
            }

            if let currentLongEdge = longEdge, currentLongEdge > 160 {
                let nextLongEdge = max(160, (currentLongEdge * 0.85).rounded(.down))
                if nextLongEdge < currentLongEdge {
                    longEdge = nextLongEdge
                    continue
                }
            } else if longEdge == nil, resultLongEdge > 160 {
                longEdge = max(160, (resultLongEdge * 0.85).rounded(.down))
                continue
            }

            lastExportStatus = "HitMinQuality"
            throw GIFExportError.unableToFitBudget(
                fileSizeBytes: fileSizeBytes,
                maxFileSizeBytes: maxFileSizeBytes,
                longEdge: resultLongEdge,
                maxLongEdge: maxLongEdge,
                outputFPS: outputFPS
            )
        }

        lastExportStatus = "HitMinQuality"
        throw GIFExportError.unableToFitBudget(
            fileSizeBytes: 0,
            maxFileSizeBytes: maxFileSizeBytes,
            longEdge: 0,
            maxLongEdge: maxLongEdge,
            outputFPS: outputFPS
        )
    }

    func encodeFinalGIF(
        from frameURLs: [URL],
        outputURL: URL,
        outputFPS: Double,
        maxLongEdge: CGFloat?
    ) async throws -> GIFGenerationURLResult {
        #if DEBUG
        finalEncodeCount += 1
        #endif

        let encoder = encoding

        return try await Task.detached(priority: .userInitiated) {
            try GIFFinalEncodePipeline.encode(
                frameURLs: frameURLs,
                outputURL: outputURL,
                outputFPS: outputFPS,
                maxLongEdge: maxLongEdge,
                encoding: encoder
            )
        }.value
    }

    func gifFileSize(for fileURL: URL) -> Int {
        guard
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
            let bytes = values.fileSize
        else {
            return 0
        }
        return bytes
    }
}

// MARK: - Preview Request / Cache

private extension GIFToolKitSession {
    func makePreparedPreviewRequest() -> GIFPreparedPreviewRequest? {
        guard let source = attributes.source else {
            return nil
        }

        let keySource: GIFPreviewKeySource
        let requestSource: GIFGenerationURLSource

        switch source {
        case .imageFiles(let urls, let adjustOrientation):
            guard !urls.isEmpty else {
                return nil
            }
            requestSource = .imageFiles(urls, adjustOrientation: adjustOrientation)
            keySource = .imageFiles(
                signatures: urls.map(fileSignature(for:)),
                adjustOrientation: adjustOrientation
            )
        case .livePhotoVideoFile(let url):
            requestSource = .livePhotoVideoFile(url, sourceFPS: attributes.sourceFPS)
            keySource = .livePhotoVideoFile(
                signature: fileSignature(for: url),
                sourceFPS: normalize(attributes.sourceFPS)
            )
        case .videoFile(let url):
            requestSource = .videoFile(url, sourceFPS: attributes.sourceFPS)
            keySource = .videoFile(
                signature: fileSignature(for: url),
                sourceFPS: normalize(attributes.sourceFPS)
            )
        }

        let key = GIFPreviewCacheKey(
            source: keySource,
            maxResolution: normalize(attributes.maxResolution),
            maxFrameCount: attributes.maxFrameCount,
            decodeMemoryBudgetMB: attributes.decodeMemoryBudgetMB,
            removeBackground: attributes.removeBackground,
            enableAutoSubjectFraming: attributes.enableAutoSubjectFraming,
            subjectTargetFillRatio: normalize(attributes.subjectTargetFillRatio),
            subjectPaddingRatio: normalize(attributes.subjectPaddingRatio),
            subjectMaxUpscale: normalize(attributes.subjectMaxUpscale),
            watermarkText: attributes.watermarkText,
            watermarkPosition: attributes.watermarkPosition
        )

        let frameDirectory = previewDirectory.appending(path: key.fileStem)
        return GIFPreparedPreviewRequest(
            key: key,
            source: requestSource,
            maxResolution: attributes.maxResolution,
            maxFrameCount: attributes.maxFrameCount,
            decodeMemoryBudgetMB: attributes.decodeMemoryBudgetMB,
            removeBackground: attributes.removeBackground,
            autoSubjectFraming: GIFAutoSubjectFramingConfig(
                isEnabled: attributes.enableAutoSubjectFraming,
                targetFillRatio: attributes.subjectTargetFillRatio,
                paddingRatio: attributes.subjectPaddingRatio,
                maxUpscale: attributes.subjectMaxUpscale
            ),
            watermarks: makeWatermarks(),
            frameDirectory: frameDirectory
        )
    }

    func makeWatermarks() -> [GIFWatermark] {
        let trimmed = attributes.watermarkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        return [
            GIFWatermark(
                content: .text(
                    trimmed,
                    font: .systemFont(ofSize: 26),
                    textColor: .red,
                    backgroundColor: .clear
                ),
                position: attributes.watermarkPosition
            ),
        ]
    }

    func cachedPreviewEntry(for key: GIFPreviewCacheKey) -> GIFPreviewCacheEntry? {
        guard var entry = previewCache[key] else {
            return nil
        }
        guard previewFilesExist(for: entry) else {
            removePreviewCacheEntry(for: key, removeFiles: false)
            return nil
        }

        entry.lastAccess = Date()
        previewCache[key] = entry
        touchPreviewLRU(for: key)
        return entry
    }

    func previewFilesExist(for entry: GIFPreviewCacheEntry) -> Bool {
        !entry.frameURLs.isEmpty && entry.frameURLs.allSatisfy {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    func touchPreviewLRU(for key: GIFPreviewCacheKey) {
        previewLRUKeys.removeAll { $0 == key }
        previewLRUKeys.append(key)
    }

    func trimPreviewCacheIfNeeded(keeping keyToKeep: GIFPreviewCacheKey?) {
        while previewCache.count > maxCachedResults || previewCacheBytes > maxCacheBytesOnDisk {
            guard let evictionKey = nextPreviewEvictionKey(keeping: keyToKeep) else {
                break
            }
            removePreviewCacheEntry(for: evictionKey, removeFiles: true)
        }
    }

    func nextPreviewEvictionKey(keeping keyToKeep: GIFPreviewCacheKey?) -> GIFPreviewCacheKey? {
        for key in previewLRUKeys {
            if key == keyToKeep {
                continue
            }
            if key == latestPreparedPreviewKey {
                continue
            }
            return key
        }
        return previewLRUKeys.first(where: { $0 != keyToKeep })
    }

    func removePreviewCacheEntry(for key: GIFPreviewCacheKey, removeFiles: Bool) {
        guard let entry = previewCache.removeValue(forKey: key) else {
            previewLRUKeys.removeAll { $0 == key }
            return
        }
        previewLRUKeys.removeAll { $0 == key }
        if removeFiles {
            try? FileManager.default.removeItem(at: entry.framesDirectory)
        }
    }

    var previewCacheBytes: Int {
        previewCache.values.reduce(into: 0) { partialResult, entry in
            partialResult += entry.bytesOnDisk
        }
    }
}

// MARK: - Memory / Pressure

private extension GIFToolKitSession {
    func setupMemoryPressureObserver() {
        memoryPressureObserver = GIFMemoryPressureObserver { [weak self] in
            Task { @MainActor in
                self?.handleMemoryPressure()
            }
        }
    }

    func handleMemoryPressure() {
        guard !isHandlingMemoryPressure else {
            return
        }
        isHandlingMemoryPressure = true
        defer {
            isHandlingMemoryPressure = false
        }

        guard !previewCache.isEmpty else {
            return
        }

        let keepKey = latestPreparedPreviewKey
        for key in previewCache.keys where key != keepKey {
            removePreviewCacheEntry(for: key, removeFiles: false)
        }
        if let keepKey {
            previewLRUKeys = [keepKey]
        } else {
            previewLRUKeys = []
        }

        recordMemorySnapshot(reason: "memory-pressure")
    }

    func recordMemorySnapshot(reason: String) {
        #if DEBUG
        let residentBytes = GIFMemoryUsage.currentResidentBytes()
        guard residentBytes > 0 else {
            return
        }
        let residentMB = Double(residentBytes) / (1024 * 1024)
        let peakMB = max(memoryTelemetry.peakResidentMB, residentMB)
        memoryTelemetry = GIFSessionMemoryTelemetry(residentMB: residentMB, peakResidentMB: peakMB)
        _ = reason
        #else
        _ = reason
        #endif
    }
}

// MARK: - Utilities

private extension GIFToolKitSession {
    func fileSignature(for url: URL) -> String {
        let standardizedPath = url.standardizedFileURL.path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: standardizedPath) else {
            return "\(standardizedPath)#0#0"
        }

        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(standardizedPath)#\(fileSize)#\(Int(modified))"
    }

    func normalize(_ value: Double) -> Int {
        Int((value * 1000).rounded())
    }

    func normalize(_ value: CGFloat) -> Int {
        Int((Double(value) * 1000).rounded())
    }
}

private struct GIFPreparedPreviewRequest: Sendable {
    let key: GIFPreviewCacheKey
    let source: GIFGenerationURLSource
    let maxResolution: CGFloat
    let maxFrameCount: Int
    let decodeMemoryBudgetMB: Int
    let removeBackground: Bool
    let autoSubjectFraming: GIFAutoSubjectFramingConfig
    let watermarks: [GIFWatermark]
    let frameDirectory: URL
}

private struct GIFPreparedPreviewOutput: Sendable {
    let frameURLs: [URL]
    let pixelSize: CGSize
    let framesDirectory: URL
    let bytesOnDisk: Int
    let extractionSummary: GIFExtractionSummary?
}

private struct GIFPreviewCacheEntry: Sendable {
    let framesDirectory: URL
    let frameURLs: [URL]
    let pixelSize: CGSize
    let bytesOnDisk: Int
    var lastAccess: Date
}

private struct GIFEncodedExport: Sendable {
    let result: GIFGenerationURLResult
    let fileSizeBytes: Int
    let outputFPS: Double
    let passCount: Int
    let status: String
}

private enum GIFExportError: LocalizedError {
    case unableToFitBudget(
        fileSizeBytes: Int,
        maxFileSizeBytes: Int?,
        longEdge: CGFloat,
        maxLongEdge: CGFloat?,
        outputFPS: Double
    )

    var errorDescription: String? {
        switch self {
        case let .unableToFitBudget(fileSizeBytes, maxFileSizeBytes, longEdge, maxLongEdge, outputFPS):
            let filePart: String
            if let maxFileSizeBytes {
                filePart = "file \(fileSizeBytes)B > limit \(maxFileSizeBytes)B"
            } else {
                filePart = "file \(fileSizeBytes)B"
            }
            let edgePart: String
            if let maxLongEdge {
                edgePart = "longEdge \(Int(longEdge))px > limit \(Int(maxLongEdge))px"
            } else {
                edgePart = "longEdge \(Int(longEdge))px"
            }
            return "Unable to fit GIF budget (\(filePart), \(edgePart), fps locked at \(Int(outputFPS)))."
        }
    }
}

private struct GIFAutoSubjectFramingConfig: Sendable {
    let isEnabled: Bool
    let targetFillRatio: Double
    let paddingRatio: Double
    let maxUpscale: Double
}

private struct GIFExtractionSummary: Sendable {
    let effectiveSourceFPS: Double
    let effectiveMaxResolution: CGFloat
    let estimatedDecodeBytes: Int
}

private enum GIFPreviewKeySource: Hashable {
    case imageFiles(signatures: [String], adjustOrientation: Bool)
    case livePhotoVideoFile(signature: String, sourceFPS: Int)
    case videoFile(signature: String, sourceFPS: Int)

    var stableString: String {
        switch self {
        case .imageFiles(let signatures, let adjustOrientation):
            return "images|\(adjustOrientation)|\(signatures.joined(separator: "|"))"
        case .livePhotoVideoFile(let signature, let sourceFPS):
            return "live|\(signature)|\(sourceFPS)"
        case .videoFile(let signature, let sourceFPS):
            return "video|\(signature)|\(sourceFPS)"
        }
    }
}

private struct GIFPreviewCacheKey: Hashable {
    let source: GIFPreviewKeySource
    let maxResolution: Int
    let maxFrameCount: Int
    let decodeMemoryBudgetMB: Int
    let removeBackground: Bool
    let enableAutoSubjectFraming: Bool
    let subjectTargetFillRatio: Int
    let subjectPaddingRatio: Int
    let subjectMaxUpscale: Int
    let watermarkText: String
    let watermarkPosition: GIFWatermarkPosition

    var fileStem: String {
        let raw = [
            source.stableString,
            "res:\(maxResolution)",
            "frame:\(maxFrameCount)",
            "mem:\(decodeMemoryBudgetMB)",
            "bg:\(removeBackground)",
            "framing:\(enableAutoSubjectFraming)",
            "fill:\(subjectTargetFillRatio)",
            "pad:\(subjectPaddingRatio)",
            "up:\(subjectMaxUpscale)",
            "wt:\(watermarkText)",
            "wp:\(watermarkPosition.rawValue)",
        ].joined(separator: "|")
        return raw.gifSHA256()
    }
}

private enum GIFPreviewPipeline {
    static func prepare(
        request: GIFPreparedPreviewRequest,
        videoFrameExtractor: any GIFVideoFrameExtracting,
        backgroundRemover: any GIFBackgroundRemoving
    ) async throws -> GIFPreparedPreviewOutput {
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: request.frameDirectory.path) {
            try FileManager.default.removeItem(at: request.frameDirectory)
        }
        try FileManager.default.createDirectory(at: request.frameDirectory, withIntermediateDirectories: true)

        let source = try await sourceImages(
            from: request,
            videoFrameExtractor: videoFrameExtractor
        )
        let sourceImages = source.images
        guard !sourceImages.isEmpty else {
            throw GifError.gifResultNil
        }

        var cgImages = sourceImages.compactMap(\.gifCGImage)
        guard !cgImages.isEmpty else {
            throw GifError.invalidImageData
        }

        if request.removeBackground {
            cgImages = try await backgroundRemover.removeBackground(images: cgImages)
        }

        if request.removeBackground, request.autoSubjectFraming.isEnabled {
            cgImages = applyAutoSubjectFraming(
                to: cgImages,
                config: request.autoSubjectFraming
            )
        }

        var frameURLs: [URL] = []
        frameURLs.reserveCapacity(cgImages.count)
        var pixelSize = CGSize.zero
        var bytesOnDisk = 0

        for (index, cgImage) in cgImages.enumerated() {
            try Task.checkCancellation()
            var frameImage = GIFImage.gifImage(cgImage: cgImage)
            frameImage = frameImage.decorate(watermarks: request.watermarks)
            if index == 0 {
                pixelSize = frameImage.size
            }
            guard let pngData = frameImage.gifPNGData else {
                throw GifError.invalidImageData
            }

            let frameURL = request.frameDirectory.appending(path: String(format: "frame-%04d.png", index))
            try pngData.write(to: frameURL, options: .atomic)
            frameURLs.append(frameURL)
            bytesOnDisk += pngData.count
        }

        guard !frameURLs.isEmpty else {
            throw GifError.gifResultNil
        }

        return GIFPreparedPreviewOutput(
            frameURLs: frameURLs,
            pixelSize: pixelSize,
            framesDirectory: request.frameDirectory,
            bytesOnDisk: bytesOnDisk,
            extractionSummary: source.extractionSummary
        )
    }

    private static func sourceImages(
        from request: GIFPreparedPreviewRequest,
        videoFrameExtractor: any GIFVideoFrameExtracting
    ) async throws -> (images: [GIFImage], extractionSummary: GIFExtractionSummary?) {
        switch request.source {
        case .imageFiles(let urls, let adjustOrientation):
            var images: [GIFImage] = []
            images.reserveCapacity(urls.count)
            for url in urls {
                guard let image = GIFImage.gifImage(contentsOf: url) else {
                    throw GifError.unableToReadFile
                }
                let oriented = adjustOrientation ? image.adjustOrientation() : image
                images.append(oriented.resize(width: request.maxResolution))
            }
            return (images, nil)
        case .videoFile(let videoURL, let sourceFPS):
            let output = try await videoFrameExtractor.extractFrames(
                from: videoURL,
                policy: GIFFrameExtractionPolicy(
                    sourceFPS: sourceFPS,
                    maxResolution: request.maxResolution,
                    maxFrameCount: request.maxFrameCount,
                    decodeMemoryBudgetBytes: request.decodeMemoryBudgetMB * 1024 * 1024
                )
            )
            return (
                output.frames,
                GIFExtractionSummary(
                    effectiveSourceFPS: output.effectiveSourceFPS,
                    effectiveMaxResolution: output.effectiveMaxResolution,
                    estimatedDecodeBytes: output.estimatedDecodeBytes
                )
            )
        case .livePhotoVideoFile(let videoURL, let sourceFPS):
            let output = try await videoFrameExtractor.extractFrames(
                from: videoURL,
                policy: GIFFrameExtractionPolicy(
                    sourceFPS: sourceFPS,
                    maxResolution: request.maxResolution,
                    maxFrameCount: request.maxFrameCount,
                    decodeMemoryBudgetBytes: request.decodeMemoryBudgetMB * 1024 * 1024
                )
            )
            return (
                output.frames,
                GIFExtractionSummary(
                    effectiveSourceFPS: output.effectiveSourceFPS,
                    effectiveMaxResolution: output.effectiveMaxResolution,
                    estimatedDecodeBytes: output.estimatedDecodeBytes
                )
            )
        }
    }

    private static func applyAutoSubjectFraming(
        to images: [CGImage],
        config: GIFAutoSubjectFramingConfig
    ) -> [CGImage] {
        guard
            let first = images.first,
            first.width > 0,
            first.height > 0
        else {
            return images
        }

        var unionRect: CGRect?
        for image in images {
            guard let rect = image.nonTransparentBoundingBox() else {
                continue
            }
            if let existing = unionRect {
                unionRect = existing.union(rect)
            } else {
                unionRect = rect
            }
        }
        guard let unionRect, unionRect.width > 0, unionRect.height > 0 else {
            return images
        }

        let canvasWidth = CGFloat(first.width)
        let canvasHeight = CGFloat(first.height)
        let currentFill = max(unionRect.width / canvasWidth, unionRect.height / canvasHeight)
        guard currentFill > 0 else {
            return images
        }

        let normalizedPadding = min(max(config.paddingRatio, 0), 0.3)
        let maxFillFromPadding = max(0.2, 1 - (normalizedPadding * 2))
        let targetFill = min(max(config.targetFillRatio, 0.2), maxFillFromPadding)
        guard currentFill < targetFill else {
            return images
        }

        let maxUpscale = max(1, config.maxUpscale)
        let zoom = min(maxUpscale, targetFill / currentFill)
        guard zoom > 1.01 else {
            return images
        }

        let focusCenter = CGPoint(x: unionRect.midX, y: unionRect.midY)
        let outputSize = CGSize(width: canvasWidth, height: canvasHeight)
        return images.compactMap { image in
            let baseImage = GIFImage.gifImage(cgImage: image)
            let scaledImage = baseImage.resize(
                to: CGSize(
                    width: outputSize.width * zoom,
                    height: outputSize.height * zoom
                )
            )
            guard let scaledCGImage = scaledImage.gifCGImage else {
                return image
            }

            let scaledCenter = CGPoint(
                x: focusCenter.x * zoom,
                y: focusCenter.y * zoom
            )
            let cropRect = CGRect(
                x: scaledCenter.x - (outputSize.width / 2),
                y: scaledCenter.y - (outputSize.height / 2),
                width: outputSize.width,
                height: outputSize.height
            )
            .intersection(
                CGRect(
                    x: 0,
                    y: 0,
                    width: CGFloat(scaledCGImage.width),
                    height: CGFloat(scaledCGImage.height)
                )
            )
            .integral

            guard
                cropRect.width >= outputSize.width * 0.95,
                cropRect.height >= outputSize.height * 0.95,
                let cropped = scaledCGImage.cropping(to: cropRect)
            else {
                return scaledCGImage
            }
            return cropped
        }
    }
}

private enum GIFFinalEncodePipeline {
    static func encode(
        frameURLs: [URL],
        outputURL: URL,
        outputFPS: Double,
        maxLongEdge: CGFloat?,
        encoding: any GIFEncoding
    ) throws -> GIFGenerationURLResult {
        guard !frameURLs.isEmpty else {
            throw GifError.gifResultNil
        }
        let parent = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let start = CFAbsoluteTimeGetCurrent()
        let effectiveLongEdge = maxLongEdge.map { max(1, $0) }
        var cgImages: [CGImage] = []
        cgImages.reserveCapacity(frameURLs.count)
        for frameURL in frameURLs {
            guard
                var image = GIFImage.gifImage(contentsOf: frameURL)
            else {
                throw GifError.invalidImageData
            }
            if let effectiveLongEdge {
                image = image.resize(width: effectiveLongEdge)
            }
            guard let cgImage = image.gifCGImage else {
                throw GifError.invalidImageData
            }
            cgImages.append(cgImage)
        }
        let frameDelay = 1.0 / max(outputFPS, 1)

        let frames = try encoding.encode(
            cgImages: cgImages,
            outputURL: outputURL,
            frameDelay: frameDelay,
            watermarks: [],
            onProgress: { _, _ in }
        )
        let duration = CFAbsoluteTimeGetCurrent() - start
        let pixelSize = frames.first?.size ?? .zero

        return GIFGenerationURLResult(
            gifURL: outputURL,
            frameCount: frames.count,
            pixelSize: pixelSize,
            duration: duration
        )
    }
}

private final class GIFSessionLifetimeCleanup {
    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class GIFMemoryPressureObserver {
    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    private let source: DispatchSourceMemoryPressure

    init(onPressure: @escaping @Sendable () -> Void) {
        source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .utility)
        )
        source.setEventHandler(handler: onPressure)
        source.resume()
    }

    deinit {
        source.cancel()
    }
    #else
    init(onPressure: @escaping @Sendable () -> Void) {}
    #endif
}

private extension String {
    func gifSHA256() -> String {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: Data(utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        return replacingOccurrences(of: "/", with: "_")
        #endif
    }
}

#if DEBUG && canImport(Darwin)
private enum GIFMemoryUsage {
    static func currentResidentBytes() -> UInt64 {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    intPtr,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else {
            return 0
        }
        return UInt64(info.resident_size)
    }
}
#else
private enum GIFMemoryUsage {
    static func currentResidentBytes() -> UInt64 {
        0
    }
}
#endif
