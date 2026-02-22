//
//  ImageBackgroundRemovalProcessor.swift
//
//
//  Created by Kai Shao on 2024/2/16.
//

@preconcurrency import Vision
import CoreImage.CIFilterBuiltins

struct ImageBackgroundRemovalProcessor {
    var inputImage: CGImage

    enum Error: LocalizedError {
        case makeMaskFailed
    }

    func process() async throws -> CGImage? {
        let maskBuffer: CVPixelBuffer
        if #available(iOS 18.0, macOS 15.0, *) {
            maskBuffer = try await makeMask18()
        } else {
            maskBuffer = try await makeMask()
        }

        let maskImage = CIImage(cvPixelBuffer: maskBuffer)
        let foregroundImage = CIImage(cgImage: inputImage)
        let backgroundImage = CIImage(color: .clear).cropped(to: foregroundImage.extent)

        let filter = CIFilter.blendWithMask()
        filter.inputImage = foregroundImage
        filter.backgroundImage = backgroundImage
        filter.maskImage = maskImage

        guard
            let outputImage = filter.outputImage,
            let cgImage = CIContext(options: nil).createCGImage(outputImage, from: outputImage.extent)
        else {
            return nil
        }

        return cgImage
    }

    private func makeMask() async throws -> CVPixelBuffer {
        let ciImage = CIImage(cgImage: inputImage)
        let handler = VNImageRequestHandler(ciImage: ciImage)

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNGenerateForegroundInstanceMaskRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
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
    private func makeMask18() async throws -> CVPixelBuffer {
        let request = GenerateForegroundInstanceMaskRequest()
        guard let result = try await request.perform(on: inputImage) else {
            throw Error.makeMaskFailed
        }
        return try result.generateScaledMask(
            for: result.allInstances,
            scaledToImageFrom: .init(inputImage)
        )
    }
}
