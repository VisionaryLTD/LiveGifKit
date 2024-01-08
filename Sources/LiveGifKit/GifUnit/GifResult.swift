//
//  File.swift
//
//
//  Created by 汤小军 on 2024/1/1.
//

import Foundation
import UIKit
import Photos

/// 生成的GIF
public struct GifResult {
    public let url: URL
    public let frames: [UIImage]
    public var data: Data? {
        return try? Data(contentsOf: url)
    }
    
#if DEBUG
    public var totalTime: Double = 0
#endif
}

