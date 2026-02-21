import LiveGifKit
import SwiftUI

struct ImageListView: View {
    var images: [GIFImage]

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120, maximum: 220))],
                spacing: 12
            ) {
                ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                    platformImage(for: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                }
            }
            .padding()
        }
    }

    private func platformImage(for image: GIFImage) -> Image {
        #if canImport(UIKit)
        Image(uiImage: image)
        #else
        Image(nsImage: image)
        #endif
    }
}
