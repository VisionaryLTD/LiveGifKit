//
//  File.swift
//
//
//  Created by tangxiaojun on 2023/12/12.
//

import Foundation
import Vision
import CoreImage.CIFilterBuiltins

extension CGImage {
    func removeBackground(_ isTrue: Bool = true) async -> CGImage? {
        if !isTrue {
            return self
        }
        return await Task.detached {
            self.removeBackgroundImpl()
        }.value
    }
    
    private func removeBackgroundImpl() -> CGImage? {
        let ciImage = CIImage(cgImage: self)
        guard let mask = subjectMask(ciImage: ciImage) else {
            return self
        }
        // Acquire the selected background image.
        let backgroundImage = CIImage(color: CIColor.clear).cropped(to: ciImage.extent)
        let filter = CIFilter.blendWithMask()
        filter.inputImage = ciImage
        filter.backgroundImage = backgroundImage
        filter.maskImage = mask
        let image = filter.outputImage!
        let resultImage = render(ciImage: image)
        return resultImage
    }
}

private func render(ciImage img: CIImage) -> CGImage {
    guard let cgImage = CIContext(options: nil).createCGImage(img, from: img.extent) else {
        fatalError("Failed to render CIImage.")
    }
    return cgImage
}

private extension CGImage {
    func subjectMask(ciImage: CIImage) -> CIImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: ciImage)
        do {
            try handler.perform([request])
        } catch {
            print("Failed to perform Vision request.")
            return nil
        }

        guard let result = request.results?.first else { return nil }
 
        do {
            let mask = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
            return CIImage(cvPixelBuffer: mask)
        } catch {
            return nil
        }
    }
}
 
extension CGImage {
    func nonTransparentBoundingBox() -> CGRect? {
        let image = self
        
        guard let pixelData = dataProvider?.data else { return nil }

        let width = self.width
        let height = self.height
        let data: UnsafePointer<UInt8> = CFDataGetBytePtr(pixelData)

        var minX: Int = width
        var minY: Int = height
        var maxX: Int = 0
        var maxY: Int = 0

        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex: Int = (width * y + x) * 4 // Assuming 4 bytes per pixel (RGBA)
                if data[pixelIndex + 3] != 0 { // Alpha value is not zero; pixel is not transparent
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        if minX > maxX || minY > maxY {
            return nil // Entire image is transparent
        }

        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
    
    func cropImage(toRect rect: CGRect) -> CGImage? {
        guard let cgImage = self.cropping(to: rect) else { return nil }
        return cgImage
    }

}

extension Array where Element == CGImage {
    func cropImages(toRect rect: CGRect) -> [CGImage] {
        compactMap { $0.cropImage(toRect: rect) }
    }
    
    func commonBoundingBox() async -> CGRect? {
        await withTaskGroup(of: CGRect?.self) { group in
            for image in self {
                group.addTask {
                    await Task.detached {
                        image.nonTransparentBoundingBox()
                    }.value
                }
            }
            
            var commonBox: CGRect?
            
            for await rect in group {
                guard let rect else {
                    continue
                }
                
                if let existingBox = commonBox {
                    commonBox = existingBox.union(rect)
                } else {
                    commonBox = rect
                }
            }
            
            return commonBox
        }
    }
}
