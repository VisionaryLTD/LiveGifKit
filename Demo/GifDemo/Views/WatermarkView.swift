import LiveGifKit
import SwiftUI

struct WatermarkView: View {
    @Environment(LiveGIFDemoViewModel.self) private var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Watermark")
                .font(.headline)

            TextField("Watermark text", text: Bindable(viewModel).watermarkText)
                .textFieldStyle(.roundedBorder)

            Picker("Watermark position", selection: Bindable(viewModel).watermarkLocation) {
                ForEach(GIFWatermarkPosition.allCases, id: \.self) { position in
                    Text(position.rawValue).tag(position)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

