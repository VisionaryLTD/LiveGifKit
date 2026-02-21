# LiveGIFKit Migration Guide

This guide explains how to migrate from the legacy `LiveGifTool` API to the new `GIFToolKit` API.

## What changed

- New primary API is `GIFToolKit` resolved from `swift-dependencies`.
- New request/response models use `GIF`-uppercase naming:
  - `GIFGenerationRequest`, `GIFGenerationSource`, `GIFGenerationOptions`, `GIFGenerationResult`
  - `GIFSaveRequest`, `GIFSavePayload`, `GIFSaveResult`
  - `GIFRecommendationRequest`, `GIFCleanupScope`
- Legacy public APIs (`LiveGifTool`, `GifToolParameter`, `GifResult`, `Method`) are kept as deprecated compatibility wrappers.

## Two-phase deprecation timeline

1. **Current release**: New `GIFToolKit` APIs are the recommended path. Legacy APIs still work, but are deprecated.
2. **Next major release**: Legacy wrappers are scheduled for removal.

## Old → new API mapping

| Legacy API | New API |
| --- | --- |
| `LiveGifTool.createGif(parameter:)` | `gifToolKit.generateGIF(_:)` |
| `LiveGifTool.save(method:)` | `gifToolKit.save(_:)` |
| `LiveGifTool.removeBackground(uiImage:)` | `gifToolKit.removeBackground(from:)` |
| `LiveGifTool.preheating()` | `gifToolKit.preheat()` |
| `LiveGifTool.cleanup()` / `cleanupAllTmp()` | `gifToolKit.cleanup(_:)` |
| `GifToolParameter` | `GIFGenerationRequest` + `GIFGenerationOptions` |
| `GifResult` | `GIFGenerationResult` |
| `Method` | `GIFSaveRequest` + `GIFSavePayload` |
| `FetchPhoto.fetch(days:)` | `gifToolKit.fetchRecommendedImages(_:)` |

## Dependency injection usage

```swift
import Dependencies
import LiveGifKit

@Dependency(\.gifToolKit) var gifToolKit
```

For tests:

```swift
let result = try await withDependencies {
  $0.gifToolKit = MyTestGIFToolKit()
} operation: {
  try await gifToolKit.generateGIF(request)
}
```

## Migration examples

### 1) Generate GIF from images

Legacy:

```swift
let tool = LiveGifTool()
let parameter = GifToolParameter(
  data: .images(frames: images, adjustOrientation: true),
  gifFPS: 30,
  removeBg: true
)
let result = try await tool.createGif(parameter: parameter)
```

New:

```swift
@Dependency(\.gifToolKit) var gifToolKit

let request = GIFGenerationRequest(
  source: .images(images, adjustOrientation: true),
  options: GIFGenerationOptions(
    outputFPS: 30,
    removeBackground: true
  )
)
let result = try await gifToolKit.generateGIF(request)
```

### 2) Generate GIF from Live Photo

Legacy:

```swift
let parameter = GifToolParameter(
  data: .livePhoto(livePhoto: livePhoto, livePhotoFPS: 15),
  gifFPS: 30
)
let result = try await LiveGifTool().createGif(parameter: parameter)
```

New:

```swift
let request = GIFGenerationRequest(
  source: .livePhoto(livePhoto, sourceFPS: 15),
  options: GIFGenerationOptions(outputFPS: 30)
)
let result = try await gifToolKit.generateGIF(request)
```

### 3) Add watermark

Legacy:

```swift
let config = ImageDecorateConfig(type: .text(text: "Demo"))
let parameter = GifToolParameter(
  data: .images(frames: images),
  imageDecorates: [config]
)
```

New:

```swift
let watermark = GIFWatermark(
  content: .text("Demo", font: .boldSystemFont(ofSize: 24), textColor: .red, backgroundColor: .clear),
  position: .center
)
let request = GIFGenerationRequest(
  source: .images(images),
  options: GIFGenerationOptions(watermarks: [watermark])
)
```

### 4) Remove background

Legacy:

```swift
let data = try await LiveGifTool().removeBackground(uiImage: image)
```

New:

```swift
let image = try await gifToolKit.removeBackground(from: image)
let data = image.gifPNGData
```

### 5) Save to photo library

Legacy:

```swift
try await LiveGifTool().save(method: .url(result.url))
```

New:

```swift
let saveRequest = GIFSaveRequest(payload: .fileURL(result.fileURL))
_ = try await gifToolKit.save(saveRequest)
```

### 6) Cleanup

Legacy:

```swift
try LiveGifTool().cleanup()
```

New:

```swift
try await gifToolKit.cleanup(.allTemporaryGIFFiles)
```

## Platform notes (iOS + macOS)

- Package supports `iOS 17+` and `macOS 14+`.
- Demo target now runs on iOS and can run on Apple Silicon Mac as a Designed-for-iPad app destination.
- Use `GIFImage` for cross-platform image type:
  - `UIImage` on iOS
  - `NSImage` on macOS

