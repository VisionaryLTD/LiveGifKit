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
                ImageListView(images: viewModel.generatedResult?.originalFrames ?? [])
            }
            .sheet(isPresented: Bindable(viewModel).showRecommendations) {
                ImageListView(images: viewModel.recommendedImages)
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
                if viewModel.isLoadingSource || viewModel.isGenerating || viewModel.isRemovingBackground {
                    ProgressView()
                        .controlSize(.small)
                }
                if viewModel.isLoadingSource {
                    Text("Loading source…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if viewModel.isRemovingBackground {
                    Text("Removing background…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if viewModel.isGenerating {
                    Text("Generating GIF…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let data = viewModel.generatedResult?.data {
                previewContainer {
                    AnimatedImage(data: data)
                        .resizable()
                }

                HStack {
                    Text("Frames: \(viewModel.generatedResult?.frames.count ?? 0)")
                    Spacer()
                    Button("View Frames") {
                        viewModel.showFrames = true
                    }
                }
            } else if let image = viewModel.singleBackgroundRemovedImage {
                previewContainer {
                    platformImage(for: image)
                        .resizable()
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
        guard let frame = viewModel.generatedResult?.frames.first else {
            guard let image = viewModel.singleBackgroundRemovedImage else {
                return 1
            }
            let width = max(image.size.width, 1)
            let height = max(image.size.height, 1)
            return width / height
        }
        let width = max(frame.size.width, 1)
        let height = max(frame.size.height, 1)
        return width / height
    }

    private func platformImage(for image: GIFImage) -> Image {
        #if canImport(UIKit)
        Image(uiImage: image)
        #else
        Image(nsImage: image)
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
                .overlay(
                    Rectangle()
                        .stroke(.red, lineWidth: 2)
                )
                .position(x: proxy.size.width / 2, y: previewHeight / 2)
        }
        .frame(height: 320)
    }
}
