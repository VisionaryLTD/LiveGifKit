# LiveGIFKit Migration Guide (Breaking: URL-First + Consumer Streams)

This release is a **breaking migration** to URL-first APIs and stream-based progress events.

## What changed

- `LiveGifTool`, `GifToolParameter`, `GifResult`, and `Method` were removed.
- `GIFToolKit` is the only public entrypoint (resolved through `swift-dependencies`).
- Generation and background removal now return `AsyncThrowingStream` event streams.
- Public request/response models are URL-first:
  - `GIFGenerationURLRequest`, `GIFGenerationURLSource`, `GIFGenerationURLResult`
  - `GIFBackgroundRemovalURLRequest`, `GIFBackgroundRemovalURLResult`
  - `GIFSaveURLRequest`, `GIFSaveURLPayload`, `GIFSaveResult`
  - `GIFRecommendationURLRequest`, `GIFRecommendedAsset`
- `GIFWatermark.Content` keeps URL-only image payload (`.imageFile(URL, width:)`), plus a bridge:
  - `@MainActor static func image(_ image: GIFImage, width: CGFloat) throws -> GIFWatermark.Content`

## Old → new mapping

| Previous API | New API |
| --- | --- |
| `LiveGifTool.createGif(parameter:)` | `gifToolKit.generateGIF(_:)` (stream) |
| `LiveGifTool.removeBackground(uiImage:)` | `gifToolKit.removeBackground(_:)` (stream) |
| `LiveGifTool.save(method:)` | `gifToolKit.save(_:)` |
| `FetchPhoto.fetch(days:)` | `gifToolKit.fetchRecommendedAssets(_:)` |
| `GifToolParameter.DataSource.images` | `GIFGenerationURLSource.imageFiles` |
| `GifToolParameter.DataSource.video` | `GIFGenerationURLSource.videoFile` |
| `GifToolParameter.DataSource.livePhoto` | `GIFGenerationURLSource.livePhotoVideoFile` |

## Dependency injection

```swift
import Dependencies
import LiveGifKit

@Dependency(\.gifToolKit) var gifToolKit
```

For tests:

```swift
let output = try await withDependencies {
  $0.gifToolKit = MyGIFToolKitStub()
} operation: {
  try await runFeature()
}
```

## Generate GIF (before/after)

Before:

```swift
let tool = LiveGifTool()
let result = try await tool.createGif(parameter: parameter)
```

After:

```swift
let request = GIFGenerationURLRequest(
  source: .imageFiles(imageURLs, adjustOrientation: true),
  options: GIFGenerationOptions(outputFPS: 24, removeBackground: true)
)

var finalResult: GIFGenerationURLResult?
for try await event in gifToolKit.generateGIF(request) {
  switch event {
  case .preparingFrames(let completed, let total):
    print("Preparing \(completed)/\(total ?? 0)")
  case .encoding(let completed, let total):
    print("Encoding \(completed)/\(total ?? 0)")
  case .completed(let result):
    finalResult = result
  }
}
```

## Remove background (before/after)

Before:

```swift
let data = try await LiveGifTool().removeBackground(uiImage: image)
```

After:

```swift
let request = GIFBackgroundRemovalURLRequest(inputImageURL: inputURL)
for try await event in gifToolKit.removeBackground(request) {
  if case .completed(let result) = event {
    print(result.imageURL)
  }
}
```

## Watermark image bridge

Core watermark payloads are URL-only. If your caller has `GIFImage`, convert once on main actor:

```swift
let content = try await MainActor.run {
  try GIFWatermark.Content.image(image, width: 60)
}
let watermark = GIFWatermark(content: content, position: .bottomRight)
```

The generated temporary watermark files are cleaned by:
- `cleanup(.requestOnly)` for request-scoped cleanup
- `cleanup(.allTemporaryGIFFiles)` for full temporary cleanup

## Save and recommendations

```swift
_ = try await gifToolKit.save(
  GIFSaveURLRequest(payload: .fileURL(gifURL))
)

let assets = try await gifToolKit.fetchRecommendedAssets(
  GIFRecommendationURLRequest(days: 30)
)
```

## Cleanup and lifecycle

```swift
try await gifToolKit.preheat()
try await gifToolKit.cleanup(.requestOnly)
try await gifToolKit.cleanup(.allTemporaryGIFFiles)
```

## Platform notes

- Minimum platforms: `iOS 17+`, `macOS 14+`.
- Public API is URL-first for concurrency safety and memory stability.
- `GIFImage` remains available for platform image interop (`UIImage`/`NSImage`) and watermark bridging.
