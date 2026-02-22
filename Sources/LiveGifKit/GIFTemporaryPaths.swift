import Foundation

internal enum GIFTemporaryPaths {
    static var baseDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "GIF")
    }

    static var watermarkDirectory: URL {
        baseDirectory.appending(path: "Watermarks")
    }

    static func isManagedWatermarkFile(_ url: URL) -> Bool {
        let managedComponents = watermarkDirectory.standardizedFileURL.pathComponents
        let targetComponents = url.standardizedFileURL.pathComponents
        return targetComponents.starts(with: managedComponents)
    }
}
