//
//  AIRecognize.swift
//
//
//  Created by tangxiaojun on 2023/12/19.
//

import Foundation
import Vision
import UIKit

protocol ResultChecking {
    func isValid() -> Bool
}

extension VNRecognizeAnimalsRequest: ResultChecking {
    func isValid() -> Bool {
        if let result = self.results?.first as? VNRecognizedObjectObservation {
            print("ResultChecking: 识别到动物 \(result.labels.map({ $0.identifier}))")
            return true
        }
        return false
    }
}

extension VNDetectFaceRectanglesRequest: ResultChecking {
    func isValid() -> Bool {
        if let result = self.results?.first as? VNFaceObservation {
            print("ResultChecking: 检测到人物")
            return true
        }
        return false
    }
}

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
}
