import LiveGifKit
import PhotosUI
import SDWebImageSwiftUI
import SwiftUI

struct MainView: View {
    @Environment(LiveGIFDemoViewModel.self) private var viewModel

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
            Toggle("Remove Background", isOn: Bindable(viewModel).removeBackground)

            LabeledContent("Source FPS: \(Int(viewModel.sourceFPS))") {
                Slider(value: Bindable(viewModel).sourceFPS, in: 5...60, step: 1)
            }

            LabeledContent("Output GIF FPS: \(Int(viewModel.outputFPS))") {
                Slider(value: Bindable(viewModel).outputFPS, in: 5...60, step: 1)
            }

            Text(viewModel.isGenerating ? "Updating preview…" : "Preview updates automatically")
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

                ProgressView(value: viewModel.generationProgress)
                    .controlSize(.small)
                    .frame(width: 80)
                    .opacity(viewModel.isProgressVisible ? 1 : 0)

                if viewModel.isProgressVisible {
                    Text(viewModel.generationStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Idle")
                        .font(.footnote)
                        .foregroundStyle(.clear)
                }
            }

            if let result = viewModel.generatedResult {
                previewContainer {
                    if let data = result.data {
                        AnimatedImage(data: data)
                            .resizable()
                    } else {
                        Text("Failed to load GIF data")
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("Frames: \(result.frameCount)")
                    Spacer()
                    Button("View Frames") {
                        viewModel.showFramesSheet()
                    }
                }
            } else if let imageURL = viewModel.singleBackgroundRemovedImageURL {
                previewContainer {
                    if let image = platformImage(for: imageURL) {
                        image
                            .resizable()
                    }
                }
            } else {
                Text("Select a source to start auto-generating the GIF preview.")
                    .foregroundStyle(.secondary)
            }
        }

        if !viewModel.lastErrorMessage.isEmpty {
            Text(viewModel.lastErrorMessage)
                .foregroundStyle(.red)
        }
    }

    private var previewAspectRatio: CGFloat {
        if let result = viewModel.generatedResult {
            let width = max(result.pixelSize.width, 1)
            let height = max(result.pixelSize.height, 1)
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
