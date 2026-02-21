import CoreGraphics
import Foundation

#if canImport(UIKit)
@preconcurrency import UIKit
public typealias GIFImage = UIImage
public typealias PlatformFont = UIFont
public typealias PlatformColor = UIColor
#elseif canImport(AppKit)
@preconcurrency import AppKit
public typealias GIFImage = NSImage
public typealias PlatformFont = NSFont
public typealias PlatformColor = NSColor
#endif

extension GIFImage {
    var gifCGImage: CGImage? {
        #if canImport(UIKit)
        cgImage
        #else
        var proposedRect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        #endif
    }

    static func gifImage(cgImage: CGImage) -> GIFImage {
        #if canImport(UIKit)
        GIFImage(cgImage: cgImage)
        #else
        GIFImage(cgImage: cgImage, size: .zero)
        #endif
    }

    var gifPNGData: Data? {
        #if canImport(UIKit)
        pngData()
        #else
        guard let tiffData = tiffRepresentation else {
            return nil
        }
        guard
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            return nil
        }
        return pngData
        #endif
    }
}

