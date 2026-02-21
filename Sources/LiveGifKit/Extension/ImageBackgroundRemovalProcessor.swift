//
//  ImageBackgroundRemovalProcessor.swift
//
//
//  Created by Kai Shao on 2024/2/16.
//

import Vision
import CoreImage

class ImageBackgroundRemovalProcessor {
    var inputImage: CGImage
    
    init(inputImage: CGImage) {
        self.inputImage = inputImage
    }
    
    func process() async throws -> CGImage? {
        guard let mask = try await makeMask2() else {
            return nil
        }
        
        let ciImage = CIImage(cgImage: inputImage)
        // Acquire the selected background image.
        let backgroundImage = CIImage(color: CIColor.clear).cropped(to: ciImage.extent)
        let filter = CIFilter.blendWithMask()
        filter.inputImage = ciImage
        filter.backgroundImage = backgroundImage
        filter.maskImage = mask
        let image = filter.outputImage!
        
        guard let cgImage = CIContext(options: nil).createCGImage(image, from: image.extent) else {
            return nil
        }
        
        return cgImage
    }
    
    private func makeMask2() async throws -> CIImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let ciImage = CIImage(cgImage: inputImage)
        let handler = VNImageRequestHandler(ciImage: ciImage)
        
        try handler.perform([request])

        guard let result = request.results?.first else { return nil }
 
        let mask = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        
        return CIImage(cvPixelBuffer: mask)
    }
}
