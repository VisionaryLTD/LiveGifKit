//
//  ImageBackgroundRemovalProcessor.swift
//
//
//  Created by Kai Shao on 2024/2/16.
//

import Vision
import UIKit

class ImageBackgroundRemovalProcessor {
    var inputImage: CGImage
    
    init(inputImage: CGImage) {
        self.inputImage = inputImage
    }
    
    func process() async throws -> CGImage? {
        guard let mask = try await makeMask() else {
            assertionFailure()
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
            assertionFailure()
            return nil
        }
        
        return cgImage
    }
    
    private func makeMask() async throws -> CIImage? {
        guard let model = try? VNCoreMLModel(for: DeepLabV3(configuration: .init()).model) else {
            return nil
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNCoreMLFeatureValueObservation],
                      let segmentationmap = observations.first?.featureValue.multiArrayValue else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let segmentationMask = segmentationmap.image(min: 0, max: 1)

                continuation.resume(returning: segmentationMask)
            }
            
            request.imageCropAndScaleOption = .scaleFill
            
            DispatchQueue.global().async {
                let handler = VNImageRequestHandler(cgImage: self.inputImage, options: [:])
                
                do {
                    try handler.perform([request])
                } catch {
                    print(error)
                }
            }
        }
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
