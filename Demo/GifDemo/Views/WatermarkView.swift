import LiveGifKit
import SwiftUI

struct WatermarkView: View {
    @Environment(GIFToolKitSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Watermark")
                .font(.headline)

            TextField("Watermark text", text: watermarkTextBinding)
                .textFieldStyle(.roundedBorder)

            Picker("Watermark position", selection: watermarkPositionBinding) {
                ForEach(GIFWatermarkPosition.allCases, id: \.self) { position in
                    Text(position.rawValue).tag(position)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var watermarkTextBinding: Binding<String> {
        Binding(
            get: { session.attributes.watermarkText },
            set: { newValue in
                var attributes = session.attributes
                attributes.watermarkText = newValue
                session.attributes = attributes
            }
        )
    }

    private var watermarkPositionBinding: Binding<GIFWatermarkPosition> {
        Binding(
            get: { session.attributes.watermarkPosition },
            set: { newValue in
                var attributes = session.attributes
                attributes.watermarkPosition = newValue
                session.attributes = attributes
            }
        )
    }
}
