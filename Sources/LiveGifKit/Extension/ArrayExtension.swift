//
//  File.swift
//
//
//  Created by tangxiaojun on 2023/12/12.
//

import Foundation
import AVFoundation
import Foundation
import UniformTypeIdentifiers
import CoreText
import UIKit

extension Array where Element == CGImage {
    func cropImages(toRect rect: CGRect) -> [CGImage] {
        compactMap { $0.cropImage(toRect: rect) }
    }
}



