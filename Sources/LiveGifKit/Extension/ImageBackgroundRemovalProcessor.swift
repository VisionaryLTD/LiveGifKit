//
//  ImageBackgroundRemovalProcessor.swift
//
//
//  Created by Kai Shao on 2024/2/16.
//

@preconcurrency import Vision
import UIKit

struct ImageBackgroundRemovalProcessor {
    var inputImage: CGImage
    
    enum Error: LocalizedError {
        case makeMaskFailed
    }
    
    func process() async throws -> CGImage? {
        let maskBuffer: CVPixelBuffer
        
        if #available(iOS 18.0, *) {
            maskBuffer = try await makeMask_18()
        } else {
            maskBuffer = try await makeMask()
        }
        
        let mask = CIImage(cvPixelBuffer: maskBuffer)
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
    
    private func makeMask() async throws -> CVPixelBuffer {
        let ciImage = CIImage(cgImage: inputImage)
        let handler = VNImageRequestHandler(ciImage: ciImage)
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNGenerateForegroundInstanceMaskRequest { request, error in
                guard let result = request.results?.first as? VNInstanceMaskObservation else {
                    continuation.resume(throwing: Error.makeMaskFailed)
                    return
                }
                
                do {
                    let mask = try result.generateScaledMaskForImage(
                        forInstances: result.allInstances,
                        from: handler
                    )
                    
                    continuation.resume(returning: mask)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    @available(iOS 18.0, macOS 15.0, *)
    private func makeMask_18() async throws -> CVPixelBuffer {
        let request = GenerateForegroundInstanceMaskRequest()
        
        guard let result = try await request.perform(on: inputImage) else {
            throw Error.makeMaskFailed
        }
        
        let mask = try result.generateScaledMask(
            for: result.allInstances,
            scaledToImageFrom: .init(inputImage)
        )
        
        return mask
    }
}
