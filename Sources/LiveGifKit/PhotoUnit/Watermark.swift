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
    public var location: WatermarkLocation = .center
    public var offset: CGFloat = 8
    public let type: WatermarkType
    public enum WatermarkType {
        case text(text: String, font: UIFont = .systemFont(ofSize: 12), textColor: UIColor = .red, bgColor: UIColor = .clear)
        case image(image: UIImage, width: CGFloat = 60)
    }
    
    public init(type: WatermarkType, location: WatermarkLocation = .center) {
        self.type = type
        self.location = location
    }
}

public extension UIImage {
    func watermark(watermark: WatermarkConfig) -> UIImage {
        let originImageSize = self.size
        UIGraphicsBeginImageContext(originImageSize)
        self.draw(in: CGRectMake(0, 0, originImageSize.width, originImageSize.height))

        
        switch watermark.type {
        case let .text(text, font, textColor, bgColor):
            let textAttributes = [NSAttributedString.Key.foregroundColor: textColor,
                                  NSAttributedString.Key.font: font,
                                  NSAttributedString.Key.backgroundColor: bgColor]
            let textSize = NSString(string: text).size(withAttributes: textAttributes)
            let frame = watermark.location.rect(imageSize: originImageSize, watermarkSize: textSize, offset: watermark.offset)
            NSString(string: text).draw(in: frame, withAttributes: textAttributes)
            
        case let .image(image, width):
            let img = image.resize(width: width)
            let frame = watermark.location.rect(imageSize: originImageSize, watermarkSize: img.size, offset: watermark.offset)
            image.draw(in: frame)
        }

        guard let newImage = UIGraphicsGetImageFromCurrentImageContext() else { return self }
        UIGraphicsEndImageContext()
        return newImage
    }
}

public enum WatermarkLocation: String, CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case center
    
    func rect(imageSize: CGSize, watermarkSize: CGSize, offset: CGFloat) -> CGRect {
        switch self {
        case .topLeft:
            return CGRect(origin: CGPoint(x: offset, y: offset), size: watermarkSize)
        case .topRight:
            return CGRect(origin: CGPoint(x: imageSize.width - watermarkSize.width - offset, y: offset), size: watermarkSize)
        case .bottomLeft:
            return CGRect(origin: CGPoint(x: offset, y: imageSize.height - watermarkSize.height - offset), size: watermarkSize)
        case .bottomRight:
            return CGRect(origin: CGPoint(x: imageSize.width - watermarkSize.width - offset, y: imageSize.height - watermarkSize.height - offset), size: watermarkSize)
        case .center:
            return CGRect(origin: CGPoint(x: imageSize.width / 2 - watermarkSize.width / 2, y: imageSize.height / 2 - watermarkSize.height / 2), size: watermarkSize)
        }
    }
    
    public var title: String {
        switch self {
        case .bottomLeft:
            return "左下角"
        case .bottomRight:
            return "右下角"
        case .center:
            return "中心"
        case .topLeft:
            return "左上角"
        case .topRight:
            return "右上角"
        }
    }
}

