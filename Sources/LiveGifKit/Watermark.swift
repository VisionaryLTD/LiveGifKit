//
//  File.swift
//
//
//  Created by tangxiaojun on 2023/12/18.
//

import Foundation
import UIKit

/// 水印参数model
/// text: 水印文字
/// font: 文字字体
/// textColor: 文字颜色
/// bgColor: 文字背景色
/// location: WatermarkLocation 位置，可选值: topLeft、topRight、bottomLeft、bottomRight、center
public struct WatermarkConfig {
    let text: String = "test"
    let font: UIFont = .systemFont(ofSize: 12)
    let textColor: UIColor = .red
    let bgColor: UIColor = .clear
    let location: WatermarkLocation = .center
}

public extension UIImage {
    func watermark(watermark: WatermarkConfig) -> UIImage {
        let textAttributes = [NSAttributedString.Key.foregroundColor:watermark.textColor,
                              NSAttributedString.Key.font:watermark.font,
                              NSAttributedString.Key.backgroundColor:watermark.bgColor]
        let textSize = NSString(string: watermark.text).size(withAttributes: textAttributes)
        let imageSize = self.size
        let frame = watermark.location.rect(imageSize: imageSize, watermarkSize: textSize)
        
        UIGraphicsBeginImageContext(imageSize)
        self.draw(in: CGRectMake(0, 0, imageSize.width, imageSize.height))
        NSString(string: watermark.text).draw(in: frame, withAttributes: textAttributes)
        
        guard let imagetext = UIGraphicsGetImageFromCurrentImageContext() else { return self }
        UIGraphicsEndImageContext()
        
        return imagetext
    }
}

public enum WatermarkLocation: Int {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case center
    
    func rect(imageSize: CGSize, watermarkSize: CGSize) -> CGRect {
        switch self {
        case .topLeft:
            return CGRect(origin: CGPoint.zero, size: watermarkSize)
        case .topRight:
            return CGRect(origin: CGPoint(x: imageSize.width - watermarkSize.width, y: 0), size: watermarkSize)
        case .bottomLeft:
            return CGRect(origin: CGPoint(x: 0, y: imageSize.height - watermarkSize.height), size: watermarkSize)
        case .bottomRight:
            return CGRect(origin: CGPoint(x: imageSize.width - watermarkSize.width, y: imageSize.height - watermarkSize.height), size: watermarkSize)
        case .center:
            return CGRect(origin: CGPoint(x: imageSize.width / 2 - watermarkSize.width / 2, y: imageSize.height / 2 - watermarkSize.height / 2), size: watermarkSize)
        }
    }
}

