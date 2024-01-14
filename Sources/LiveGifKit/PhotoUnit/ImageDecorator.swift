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
public struct ImageDecorateConfig {
    public var location: DecoratorLocation
    public var offset: CGPoint
    public let type: WatermarkType
    public var origin: CGPoint?
    public enum WatermarkType {
        case text(text: String, font: UIFont = .boldSystemFont(ofSize: 62), textColor: UIColor = .red, bgColor: UIColor = .clear)
        case attributeText(text: NSAttributedString)
        case image(image: UIImage, width: CGFloat = 60)
    }
    
    public init(type: WatermarkType, location: DecoratorLocation = .center, offset: CGPoint = .init(x: 8, y: 8)) {
        self.type = type
        self.location = location
        self.offset = offset
    }
}

public extension UIImage {
    func watermark(watermark: ImageDecorateConfig) -> UIImage {
        let originImageSize = self.size
        UIGraphicsBeginImageContext(originImageSize)
        self.draw(in: CGRectMake(0, 0, originImageSize.width, originImageSize.height))

        switch watermark.type {
        case let .text(text, font, textColor, bgColor):
            let textAttributes = [NSAttributedString.Key.foregroundColor: textColor,
                                  NSAttributedString.Key.font: font,
                                  NSAttributedString.Key.backgroundColor: bgColor]
            let textSize = NSString(string: text).size(withAttributes: textAttributes)
            if let origin = watermark.origin {
                NSString(string: text).draw(in: CGRect(origin: origin, size: textSize), withAttributes: textAttributes)
            } else {
                let frame = watermark.location.rect(imageSize: originImageSize, decoratorSize: textSize, offset: watermark.offset)
                NSString(string: text).draw(in: frame, withAttributes: textAttributes)
            }
            
        case let .attributeText(text: text):
            let textSize = text.size()
            if let origin = watermark.origin {
                text.draw(in: CGRect(origin: origin, size: textSize))
            } else {
                let frame = watermark.location.rect(imageSize: originImageSize, decoratorSize: textSize, offset: watermark.offset)
                text.draw(in: frame)
            }
            
        case let .image(image, width):
            let img = image.resize(width: width)
            if let origin = watermark.origin {
                image.draw(in: CGRect(origin: origin, size: img.size))
            } else {
                let frame = watermark.location.rect(imageSize: originImageSize, decoratorSize: img.size, offset: watermark.offset)
                image.draw(in: frame)
            }
        }

        guard let newImage = UIGraphicsGetImageFromCurrentImageContext() else { return self }
        UIGraphicsEndImageContext()
        return newImage
    }
}

public enum DecoratorLocation: String, CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case center
    
    func rect(imageSize: CGSize, decoratorSize: CGSize, offset: CGPoint) -> CGRect {
        switch self {
        case .topLeft:
            return CGRect(origin: offset, size: decoratorSize)
        case .topRight:
            return CGRect(origin: CGPoint(x: imageSize.width - decoratorSize.width - offset.x, y: offset.y), size: decoratorSize)
        case .bottomLeft:
            return CGRect(origin: CGPoint(x: offset.x, y: imageSize.height - decoratorSize.height - offset.y), size: decoratorSize)
        case .bottomRight:
            return CGRect(origin: CGPoint(x: imageSize.width - decoratorSize.width - offset.x, y: imageSize.height - decoratorSize.height - offset.y), size: decoratorSize)
        case .center:
            return CGRect(origin: CGPoint(x: imageSize.width / 2 - decoratorSize.width / 2, y: imageSize.height / 2 - decoratorSize.height / 2), size: decoratorSize)
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

