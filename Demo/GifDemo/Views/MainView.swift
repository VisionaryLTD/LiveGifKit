import LiveGifKit
import PhotosUI
import SwiftUI

struct MainView: View {
    @Environment(LiveGIFDemoViewModel.self) private var viewModel
    @Environment(GIFToolKitSession.self) private var session

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sourceSection
                    controlsSection
                    WatermarkView()
                    resultSection
                    OperatorButtonsView()
                }
                .padding()
            }
            .navigationTitle("LiveGIFKit Demo")
            .sheet(isPresented: Bindable(viewModel).showFrames) {
                ImageListView(imageURLs: viewModel.generatedFrameURLs)
            }
            .sheet(isPresented: Bindable(viewModel).showRecommendations) {
                ImageListView(imageURLs: viewModel.recommendedAssets.map(\.thumbnailURL))
            }
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotosPicker(
                "Select Source",
                selection: Bindable(viewModel).pickerItem,
                matching: viewModel.sourceMode == .livePhoto ? .livePhotos : .images
            )
            .buttonStyle(.borderedProminent)

            Picker("Source Type", selection: Bindable(viewModel).sourceMode) {
                ForEach(LiveGIFDemoViewModel.SourceMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .onChange(of: viewModel.pickerItem) { _, _ in
            viewModel.handlePickerChange()
        }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Remove Background", isOn: removeBackgroundBinding)

            LabeledContent("Source FPS: \(Int(session.attributes.sourceFPS))") {
                Slider(value: sourceFPSBinding, in: 5...60, step: 1)
            }

            LabeledContent("Output GIF FPS: \(Int(session.attributes.outputFPS))") {
                Slider(value: outputFPSBinding, in: 5...60, step: 1)
            }

            LabeledContent("Max Resolution: \(Int(session.attributes.maxResolution))") {
                Slider(value: maxResolutionBinding, in: 160...1200, step: 10)
            }

            Stepper(
                "Max Frames: \(session.attributes.maxFrameCount)",
                value: maxFrameCountBinding,
                in: 10...300
            )

            Stepper(
                "Decode Budget: \(session.attributes.decodeMemoryBudgetMB)MB",
                value: decodeMemoryBudgetBinding,
                in: 16...512
            )

            Divider()

            Toggle("Auto Subject Framing", isOn: autoSubjectFramingBinding)
            if session.attributes.enableAutoSubjectFraming {
                LabeledContent(
                    "Subject Fill: \(session.attributes.subjectTargetFillRatio, format: .number.precision(.fractionLength(2)))"
                ) {
                    Slider(value: subjectFillRatioBinding, in: 0.3...0.9, step: 0.01)
                }
                LabeledContent(
                    "Subject Padding: \(session.attributes.subjectPaddingRatio, format: .number.precision(.fractionLength(2)))"
                ) {
                    Slider(value: subjectPaddingRatioBinding, in: 0...0.2, step: 0.01)
                }
                LabeledContent(
                    "Subject Max Upscale: \(session.attributes.subjectMaxUpscale, format: .number.precision(.fractionLength(2)))"
                ) {
                    Slider(value: subjectMaxUpscaleBinding, in: 1...3, step: 0.05)
                }
            }

            Divider()

            Toggle("Limit Export Long Edge", isOn: exportLongEdgeEnabledBinding)
            if let exportMaxLongEdge = session.attributes.exportMaxLongEdge {
                LabeledContent("Export Long Edge: \(Int(exportMaxLongEdge))") {
                    Slider(value: exportMaxLongEdgeBinding, in: 160...1024, step: 8)
                }
            }

            Toggle("Limit Export File Size", isOn: exportFileSizeEnabledBinding)
            if let exportMaxFileSizeBytes = session.attributes.exportMaxFileSizeBytes {
                LabeledContent("Export File Size: \(Int(Double(exportMaxFileSizeBytes) / 1024))KB") {
                    Slider(
                        value: exportMaxFileSizeKBValueBinding,
                        in: 100...3000,
                        step: 25
                    )
                }
            }

            Text(session.isGenerating ? "Updating preview…" : "Preview updates automatically")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Result")
                    .font(.headline)

                ProgressView(value: session.generationProgress)
                    .controlSize(.small)
                    .frame(width: 80)
                    .opacity(viewModel.isProgressVisible ? 1 : 0)

                if viewModel.isProgressVisible {
                    Text(
                        session.isPreparingPreview
                            ? session.previewStatus
                            : session.generationStatus
                    )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Idle")
                        .font(.footnote)
                        .foregroundStyle(.clear)
                }
            }

            #if DEBUG
            Text(
                "Memory \(session.memoryTelemetry.residentMB, format: .number.precision(.fractionLength(1)))MB, Peak \(session.memoryTelemetry.peakResidentMB, format: .number.precision(.fractionLength(1)))MB"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            #endif

            if let previewPixelSize = session.previewPixelSize {
                Text("Preview: \(session.previewFrameURLs.count) frames, \(Int(previewPixelSize.width))×\(Int(previewPixelSize.height))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if
                let exportPixelSize = session.lastExportPixelSize,
                let exportFileSizeBytes = session.lastExportFileSizeBytes
            {
                Text(
                    "Export: \(Int(exportPixelSize.width))×\(Int(exportPixelSize.height)), \(Int(Double(exportFileSizeBytes) / 1024))KB, fps \(Int(session.lastExportFPS ?? 0)), pass \(session.lastExportPassCount), \(session.lastExportStatus)"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if let imageURL = viewModel.singleBackgroundRemovedImageURL {
                previewContainer {
                    if let image = platformImage(for: imageURL) {
                        image
                            .resizable()
                    }
                }
            } else if !session.previewFrameURLs.isEmpty {
                previewContainer {
                    GIFFrameLoopPreview(
                        frameURLs: session.previewFrameURLs,
                        fps: session.attributes.outputFPS
                    )
                }

                HStack {
                    Text("Frames: \(session.previewFrameURLs.count)")
                    Spacer()
                    Button("View Frames") {
                        viewModel.showFramesSheet()
                    }
                }
            } else {
                Text("Select a source to start auto-generating the GIF preview.")
                    .foregroundStyle(.secondary)
            }
        }

        if !viewModel.localErrorMessage.isEmpty {
            Text(viewModel.localErrorMessage)
                .foregroundStyle(.red)
        } else if !session.lastErrorMessage.isEmpty {
            Text(session.lastErrorMessage)
                .foregroundStyle(.red)
        }
    }

    private var removeBackgroundBinding: Binding<Bool> {
        Binding(
            get: { session.attributes.removeBackground },
            set: { newValue in
                var attributes = session.attributes
                attributes.removeBackground = newValue
                session.attributes = attributes
            }
        )
    }

    private var sourceFPSBinding: Binding<Double> {
        Binding(
            get: { session.attributes.sourceFPS },
            set: { newValue in
                var attributes = session.attributes
                attributes.sourceFPS = newValue
                session.attributes = attributes
            }
        )
    }

    private var outputFPSBinding: Binding<Double> {
        Binding(
            get: { session.attributes.outputFPS },
            set: { newValue in
                var attributes = session.attributes
                attributes.outputFPS = newValue
                session.attributes = attributes
            }
        )
    }

    private var maxResolutionBinding: Binding<Double> {
        Binding(
            get: { Double(session.attributes.maxResolution) },
            set: { newValue in
                var attributes = session.attributes
                attributes.maxResolution = CGFloat(newValue)
                session.attributes = attributes
            }
        )
    }

    private var maxFrameCountBinding: Binding<Int> {
        Binding(
            get: { session.attributes.maxFrameCount },
            set: { newValue in
                var attributes = session.attributes
                attributes.maxFrameCount = newValue
                session.attributes = attributes
            }
        )
    }

    private var decodeMemoryBudgetBinding: Binding<Int> {
        Binding(
            get: { session.attributes.decodeMemoryBudgetMB },
            set: { newValue in
                var attributes = session.attributes
                attributes.decodeMemoryBudgetMB = newValue
                session.attributes = attributes
            }
        )
    }

    private var autoSubjectFramingBinding: Binding<Bool> {
        Binding(
            get: { session.attributes.enableAutoSubjectFraming },
            set: { newValue in
                var attributes = session.attributes
                attributes.enableAutoSubjectFraming = newValue
                session.attributes = attributes
            }
        )
    }

    private var subjectFillRatioBinding: Binding<Double> {
        Binding(
            get: { session.attributes.subjectTargetFillRatio },
            set: { newValue in
                var attributes = session.attributes
                attributes.subjectTargetFillRatio = newValue
                session.attributes = attributes
            }
        )
    }

    private var subjectPaddingRatioBinding: Binding<Double> {
        Binding(
            get: { session.attributes.subjectPaddingRatio },
            set: { newValue in
                var attributes = session.attributes
                attributes.subjectPaddingRatio = newValue
                session.attributes = attributes
            }
        )
    }

    private var subjectMaxUpscaleBinding: Binding<Double> {
        Binding(
            get: { session.attributes.subjectMaxUpscale },
            set: { newValue in
                var attributes = session.attributes
                attributes.subjectMaxUpscale = newValue
                session.attributes = attributes
            }
        )
    }

    private var exportLongEdgeEnabledBinding: Binding<Bool> {
        Binding(
            get: { session.attributes.exportMaxLongEdge != nil },
            set: { isEnabled in
                var attributes = session.attributes
                attributes.exportMaxLongEdge = isEnabled ? (attributes.exportMaxLongEdge ?? 480) : nil
                session.attributes = attributes
            }
        )
    }

    private var exportMaxLongEdgeBinding: Binding<Double> {
        Binding(
            get: { Double(session.attributes.exportMaxLongEdge ?? 480) },
            set: { newValue in
                var attributes = session.attributes
                attributes.exportMaxLongEdge = CGFloat(newValue)
                session.attributes = attributes
            }
        )
    }

    private var exportFileSizeEnabledBinding: Binding<Bool> {
        Binding(
            get: { session.attributes.exportMaxFileSizeBytes != nil },
            set: { isEnabled in
                var attributes = session.attributes
                attributes.exportMaxFileSizeBytes = isEnabled ? (attributes.exportMaxFileSizeBytes ?? 500 * 1024) : nil
                session.attributes = attributes
            }
        )
    }

    private var exportMaxFileSizeKBValueBinding: Binding<Double> {
        Binding(
            get: { Double(session.attributes.exportMaxFileSizeBytes ?? (500 * 1024)) / 1024 },
            set: { newValue in
                var attributes = session.attributes
                attributes.exportMaxFileSizeBytes = Int(newValue * 1024)
                session.attributes = attributes
            }
        )
    }

    private var previewAspectRatio: CGFloat {
        if let previewPixelSize = session.previewPixelSize {
            let width = max(previewPixelSize.width, 1)
            let height = max(previewPixelSize.height, 1)
            return width / height
        }

        if
            let imageURL = viewModel.singleBackgroundRemovedImageURL,
            let image = loadPlatformImage(from: imageURL)
        {
            let width = max(image.size.width, 1)
            let height = max(image.size.height, 1)
            return width / height
        }
        return 1
    }

    private func platformImage(for url: URL) -> Image? {
        guard let image = loadPlatformImage(from: url) else {
            return nil
        }
        #if canImport(UIKit)
        return Image(uiImage: image)
        #else
        return Image(nsImage: image)
        #endif
    }

    private func loadPlatformImage(from url: URL) -> GIFImage? {
        #if canImport(UIKit)
        GIFImage(contentsOfFile: url.path)
        #else
        GIFImage(contentsOf: url)
        #endif
    }

    private func previewContainer<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        GeometryReader { proxy in
            let maxPreviewHeight: CGFloat = 320
            let ratio = previewAspectRatio
            let previewWidth = min(proxy.size.width, maxPreviewHeight * ratio)
            let previewHeight = previewWidth / ratio

            content()
                .frame(width: previewWidth, height: previewHeight)
                .overlay {
                    Rectangle()
                        .stroke(.red, lineWidth: 2)
                }
                .position(x: proxy.size.width / 2, y: previewHeight / 2)
        }
        .frame(height: 320)
    }
}
