//
//  UIImage+BackgroundRemoval.swift
//
//
//  Created by Kai Shao on 2023/11/28.
//

import UIKit
import Vision
import CoreImage.CIFilterBuiltins

extension UIImage {
    func removeBackground(_ isTrue: Bool = true) async -> UIImage? {
        if !isTrue {
            return self
        }
        
        return await Task.detached {
            self.removeBackgroundImpl()
        }.value
    }
    
    private func removeBackgroundImpl() -> UIImage? {
        guard let ciImage = getCIImage() else {
            assertionFailure()
            return self
        }
        
        guard let mask = subjectMask(ciImage: ciImage, atPoint: nil) else {
            return self
        }
        
        // Acquire the selected background image.
        let backgroundImage = CIImage(color: CIColor.clear).cropped(to: ciImage.extent)
        
        let filter = CIFilter.blendWithMask()
        filter.inputImage = ciImage
        filter.backgroundImage = backgroundImage
        filter.maskImage = mask
        
        let image = filter.outputImage!
        let resultImage = UIImage(cgImage: render(ciImage: image))
        
        return resultImage
    }
    
    func getCIImage() -> CIImage? {
        if let ciImage = ciImage {
            // CIImage is already available
            return ciImage
        } else if let cgImage = cgImage {
            // Create a new CIImage from the CGImage
            return CIImage(cgImage: cgImage)
        } else {
            // No underlying CIImage or CGImage available
            return nil
        }
    }
}

private func render(ciImage img: CIImage) -> CGImage {
    guard let cgImage = CIContext(options: nil).createCGImage(img, from: img.extent) else {
        fatalError("Failed to render CIImage.")
    }
    return cgImage
}

private extension UIImage {
    func subjectMask(ciImage: CIImage, atPoint point: CGPoint?) -> CIImage? {
        // Create a request.
        let request = VNGenerateForegroundInstanceMaskRequest()

        // Create a request handler.
        let handler = VNImageRequestHandler(ciImage: ciImage)

        // Perform the request.
        do {
            try handler.perform([request])
        } catch {
            print("Failed to perform Vision request.")
            return nil
        }

        // Acquire the instance mask observation.
        guard let result = request.results?.first else {
            print("No subject observations found.")
            return nil
        }

        let instances = instances(atPoint: point, inObservation: result)
        
        // Create a matted image with the subject isolated from the background.
        do {
            let mask = try result.generateScaledMaskForImage(forInstances: instances, from: handler)
            return CIImage(cvPixelBuffer: mask)
        } catch {
            print("Failed to generate subject mask.")
            return nil
        }
    }
}

/// Returns the indices of the instances at the given point.
///
/// - parameter atPoint: A point with a top-left origin, normalized within the range [0, 1].
/// - parameter inObservation: The observation instance to extract subject indices from.
private func instances(
    atPoint maybePoint: CGPoint?,
    inObservation observation: VNInstanceMaskObservation
) -> IndexSet {
    guard let point = maybePoint else {
        return observation.allInstances
    }

    // Transform the normalized UI point to an instance map pixel coordinate.
    let instanceMap = observation.instanceMask
    let coords = VNImagePointForNormalizedPoint(
        point,
        CVPixelBufferGetWidth(instanceMap) - 1,
        CVPixelBufferGetHeight(instanceMap) - 1)

    // Look up the instance label at the computed pixel coordinate.
    CVPixelBufferLockBaseAddress(instanceMap, .readOnly)
    guard let pixels = CVPixelBufferGetBaseAddress(instanceMap) else {
        fatalError("Failed to access instance map data.")
    }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(instanceMap)
    let instanceLabel = pixels.load(
        fromByteOffset: Int(coords.y) * bytesPerRow + Int(coords.x),
        as: UInt8.self)
    CVPixelBufferUnlockBaseAddress(instanceMap, .readOnly)

    // If the point lies on the background, select all instances.
    // Otherwise, restrict this to just the selected instance.
    return instanceLabel == 0 ? observation.allInstances : [Int(instanceLabel)]
}

extension UIImage {
    func nonTransparentBoundingBox() -> CGRect? {
        let image = self
        guard let cgImage = image.cgImage, let dataProvider = cgImage.dataProvider else { return nil }
        guard let pixelData = dataProvider.data else { return nil }

        let width = cgImage.width
        let height = cgImage.height
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
    
    func cropImage(toRect rect: CGRect) -> UIImage? {
        guard let cgImage = cgImage?.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: imageOrientation)
    }

}

extension Array where Element == UIImage {
    func cropImages(toRect rect: CGRect) -> [UIImage] {
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
