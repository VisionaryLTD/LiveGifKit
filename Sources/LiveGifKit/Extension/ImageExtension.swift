//
//  File.swift
//
//
//  Created by tangxiaojun on 2023/12/12.
//

import Foundation
import Vision
import CoreImage.CIFilterBuiltins
import UIKit

public extension UIImage {
    func recognition() -> Bool {
        guard let cgImage = self.cgImage else { return false }
        let requests = [
            VNRecognizeAnimalsRequest(),
            VNDetectFaceRectanglesRequest()
        ]
        let requestHandler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try requestHandler.perform(requests)
        } catch {
            print("识别请求错误 \(error)")
        }
        let results = requests.map({ $0 as! ResultChecking })
        if let request = results.first(where: { $0.isValid() }) {
            return true
        }
        return false
    }
    
    func adjustOrientation() -> UIImage {
           let imageSize = self.size
           UIGraphicsBeginImageContext(imageSize)
           self.draw(in: CGRectMake(0, 0, imageSize.width, imageSize.height))
           guard let newImage = UIGraphicsGetImageFromCurrentImageContext() else { return self }
           UIGraphicsEndImageContext()
           return newImage
       }
}

public extension UIImage {
    func resize(scale: CGFloat = 0.5) -> UIImage {
        let size = self.size
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        self.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage ?? self
    }
     
    func resize(width: CGFloat = 1, height: CGFloat = 1) -> UIImage {
        let widthRatio  = width  / size.width
        let heightRatio = height / size.height
        let scalingFactor = max(widthRatio, heightRatio)
        return resize(scale: scalingFactor)
    }
}

extension CGImage {
    func removeBackground(_ isTrue: Bool = true) async -> CGImage? {
        if !isTrue {
            return self
        }
        
        let processor = ImageBackgroundRemovalProcessor(inputImage: self)
        
        do {
            return try await processor.process()
        } catch {
            return nil
        }
    }
    
//    private func removeBackgroundImpl() -> CGImage {
//        let ciImage = CIImage(cgImage: self)
//        guard let mask = subjectMask(ciImage: ciImage) else {
//            return self
//        }
//        // Acquire the selected background image.
//        let backgroundImage = CIImage(color: CIColor.clear).cropped(to: ciImage.extent)
//        let filter = CIFilter.blendWithMask()
//        filter.inputImage = ciImage
//        filter.backgroundImage = backgroundImage
//        filter.maskImage = mask
//        let image = filter.outputImage!
//        let resultImage = render(ciImage: image)
//        return resultImage
        
//        let processor = ImageBackgroundRemovalProcessor(inputImage: self)
//        return try! awa
//    }
}

private func render(ciImage img: CIImage) -> CGImage {
    guard let cgImage = CIContext(options: nil).createCGImage(img, from: img.extent) else {
        fatalError("Failed to render CIImage.")
    }
    return cgImage
}

//private extension CGImage {
//    func subjectMask(ciImage: CIImage) -> CIImage? {
//        let request = VNGenerateForegroundInstanceMaskRequest()
//        let handler = VNImageRequestHandler(ciImage: ciImage)
//        do {
//            try handler.perform([request])
//        } catch {
//            print("Failed to perform Vision request.")
//            return nil
//        }
//
//        guard let result = request.results?.first else { return nil }
// 
//        do {
//            let mask = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
//            return CIImage(cvPixelBuffer: mask)
//        } catch {
//            return nil
//        }
//    }
//}
 
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
