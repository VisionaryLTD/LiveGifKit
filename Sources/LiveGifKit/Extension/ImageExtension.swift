import Foundation
import Vision
import CoreImage.CIFilterBuiltins
import CoreGraphics

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public extension GIFImage {
    func recognition() -> Bool {
        guard let cgImage = gifCGImage else {
            return false
        }

        let requestHandler = VNImageRequestHandler(cgImage: cgImage)
        let animalRequest = VNRecognizeAnimalsRequest()
        let faceRequest = VNDetectFaceRectanglesRequest()

        do {
            try requestHandler.perform([animalRequest, faceRequest])
        } catch {
            return false
        }

        let hasAnimal = (animalRequest.results?.first as? VNRecognizedObjectObservation) != nil
        let hasFace = (faceRequest.results?.first as? VNFaceObservation) != nil
        return hasAnimal || hasFace
    }

    func adjustOrientation() -> GIFImage {
        #if canImport(UIKit)
        guard let cgImage else {
            return self
        }
        return GIFImage(cgImage: cgImage, scale: 1.0, orientation: .up)
        #else
        self
        #endif
    }

    func resize(scale: CGFloat = 0.5) -> GIFImage {
        let baseSize = size
        let newSize = CGSize(width: baseSize.width * scale, height: baseSize.height * scale)
        return resize(to: newSize)
    }

    func resize(width: CGFloat = 1, height: CGFloat = 1) -> GIFImage {
        guard size.width > 0, size.height > 0 else {
            return self
        }
        let widthRatio = width / size.width
        let heightRatio = height / size.height
        let scalingFactor = max(widthRatio, heightRatio)
        return resize(scale: scalingFactor)
    }

    func resize(to size: CGSize) -> GIFImage {
        guard let cgImage = gifCGImage else {
            return self
        }
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0 else {
            return self
        }
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return self
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let resizedImage = context.makeImage() else {
            return self
        }
        return GIFImage.gifImage(cgImage: resizedImage)
    }

    static func gifExampleImage() -> GIFImage? {
        #if canImport(UIKit)
        return GIFImage(named: "example", in: .module, with: nil)
        #else
        guard
            let imageURL = Bundle.module.url(
                forResource: "example",
                withExtension: "png",
                subdirectory: "Assets.xcassets/example.imageset"
            ),
            let image = GIFImage(contentsOf: imageURL)
        else {
            return nil
        }
        return image
        #endif
    }
}

extension CGImage {
    func nonTransparentBoundingBox(
        minimumAlpha: UInt8 = 8,
        relativeAlphaThreshold: Double = 0.08
    ) -> CGRect? {
        guard width > 0, height > 0 else {
            return nil
        }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard pixels.withUnsafeMutableBytes({ buffer in
            guard let baseAddress = buffer.baseAddress else {
                return false
            }
            guard let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }) else {
            return nil
        }

        var maxAlpha: UInt8 = 0
        for index in stride(from: 3, to: pixels.count, by: 4) {
            maxAlpha = max(maxAlpha, pixels[index])
        }
        guard maxAlpha > 0 else {
            return nil
        }
        let adaptiveThreshold = max(
            Int(minimumAlpha),
            Int((Double(maxAlpha) * relativeAlphaThreshold).rounded(.up))
        )

        if let rect = boundingRect(in: pixels, alphaThreshold: UInt8(clamping: adaptiveThreshold)) {
            return rect
        }
        return boundingRect(in: pixels, alphaThreshold: minimumAlpha)
    }

    private func boundingRect(in pixels: [UInt8], alphaThreshold: UInt8) -> CGRect? {
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0

        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = ((y * width) + x) * 4
                if pixels[pixelIndex + 3] >= alphaThreshold {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard minX <= maxX, minY <= maxY else {
            return nil
        }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    func cropImage(toRect rect: CGRect) -> CGImage? {
        guard let cgImage = cropping(to: rect) else { return nil }
        return cgImage
    }
}
