import SwiftUI

struct OperatorButtonsView: View {
    @Environment(LiveGIFDemoViewModel.self) private var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Public API Actions")
                .font(.headline)

            HStack {
                Button("Fetch Recommendations") {
                    viewModel.loadRecommendations()
                }

                Button("Remove BG (Image)") {
                    viewModel.removeBackgroundFromSourceImage()
                }
                .disabled(!viewModel.canRemoveBackground)

                Button("Save GIF") {
                    viewModel.saveGIF()
                }
                .disabled(viewModel.generatedResult == nil)

                Button("Cleanup") {
                    viewModel.cleanup()
                }
            }
            .buttonStyle(.bordered)

            if !viewModel.saveStatus.isEmpty {
                Text("Save status: \(viewModel.saveStatus)")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
