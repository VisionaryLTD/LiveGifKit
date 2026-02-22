import LiveGifKit
import SwiftUI

struct ImageListView: View {
    let imageURLs: [URL]

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120, maximum: 220))],
                spacing: 12
            ) {
                ForEach(imageURLs, id: \.self) { imageURL in
                    if let image = platformImage(for: imageURL) {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                    }
                }
            }
            .padding()
        }
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
}
