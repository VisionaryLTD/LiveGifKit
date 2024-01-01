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

