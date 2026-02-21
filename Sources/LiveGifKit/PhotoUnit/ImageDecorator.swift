import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 水印参数model
/// text: 水印文字
/// font: 文字字体
/// textColor: 文字颜色
/// bgColor: 文字背景色
/// location: DecoratorLocation 位置，可选值: topLeft、topRight、bottomLeft、bottomRight、center
public struct ImageDecorateConfig {
    public var location: DecoratorLocation
    public var offset: CGPoint
    public let type: DecoratorType
    public var origin: CGPoint?
    public enum DecoratorType {
        case text(text: String, font: PlatformFont = .boldSystemFont(ofSize: 62), textColor: PlatformColor = .red, bgColor: PlatformColor = .clear)
        case attributeText(text: NSAttributedString)
        case image(image: GIFImage, width: CGFloat = 60)
    }
    
    public init(type: DecoratorType, location: DecoratorLocation = .center, offset: CGPoint = .init(x: 8, y: 8)) {
        self.type = type
        self.location = location
        self.offset = offset
    }
}

public extension GIFImage {
    func decorate(config: ImageDecorateConfig) -> GIFImage {
        decorate(watermarks: [GIFWatermark(config: config)])
    }

    func decorate(watermarks: [GIFWatermark]) -> GIFImage {
        guard let cgImage = gifCGImage else {
            return self
        }
        let width = cgImage.width
        let height = cgImage.height
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return self
        }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let imageSize = CGSize(width: width, height: height)
        for watermark in watermarks {
            draw(watermark: watermark, context: context, imageSize: imageSize)
        }

        guard let output = context.makeImage() else {
            return self
        }
        return GIFImage.gifImage(cgImage: output)
    }
    
    func maxChineseCharacterCount(forFont font: PlatformFont, inImageWidth imageWidth: CGFloat) -> Int {
        let text = "我爱中文"
        let attributes = [NSAttributedString.Key.font: font]
        let size = CGSize(width: imageWidth, height: CGFloat.greatestFiniteMagnitude)
        #if canImport(UIKit)
        let options: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        #else
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        #endif
        let boundingRect = (text as NSString).boundingRect(with: size, options: options, attributes: attributes, context: nil)
        let characterCount = text.count
        let characterWidth = boundingRect.width / CGFloat(characterCount)
        let maxCharactersPerLine = Int(imageWidth / characterWidth)
        return maxCharactersPerLine
    }

    private func draw(watermark: GIFWatermark, context: CGContext, imageSize: CGSize) {
        switch watermark.content {
        case let .text(text, font, textColor, backgroundColor):
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
                .backgroundColor: backgroundColor,
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            draw(attributed: attributed, watermark: watermark, context: context, imageSize: imageSize)
        case let .attributedText(text):
            draw(attributed: text, watermark: watermark, context: context, imageSize: imageSize)
        case let .image(image, width):
            let resized = image.resize(width: width)
            guard let cgImage = resized.gifCGImage else {
                return
            }
            let decoratorSize = CGSize(width: cgImage.width, height: cgImage.height)
            let origin = watermark.origin
                ?? watermark.position.decoratorLocation.rect(
                    imageSize: imageSize,
                    decoratorSize: decoratorSize,
                    offset: watermark.offset
                ).origin
            let frame = CGRect(origin: origin, size: decoratorSize)
            context.draw(cgImage, in: frame)
        }
    }

    private func draw(
        attributed: NSAttributedString,
        watermark: GIFWatermark,
        context: CGContext,
        imageSize: CGSize
    ) {
        let textSize = attributed.size()
        let frame = CGRect(
            origin: watermark.origin
                ?? watermark.position.decoratorLocation.rect(
                    imageSize: imageSize,
                    decoratorSize: textSize,
                    offset: watermark.offset
                ).origin,
            size: textSize
        )
        #if canImport(UIKit)
        UIGraphicsPushContext(context)
        attributed.draw(with: frame, options: [.usesLineFragmentOrigin], context: nil)
        UIGraphicsPopContext()
        #else
        let drawContext = NSStringDrawingContext()
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        attributed.draw(with: frame, options: [.usesLineFragmentOrigin], context: drawContext)
        NSGraphicsContext.restoreGraphicsState()
        #endif
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
            return CGRect(origin: CGPoint(x: imageSize.width / 2 - decoratorSize.width / 2 + offset.x, y: imageSize.height / 2 - decoratorSize.height / 2 + offset.y), size: decoratorSize)
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

extension GIFWatermarkPosition {
    var decoratorLocation: DecoratorLocation {
        switch self {
        case .topLeft:
            return .topLeft
        case .topRight:
            return .topRight
        case .bottomLeft:
            return .bottomLeft
        case .bottomRight:
            return .bottomRight
        case .center:
            return .center
        }
    }
}

extension GIFWatermark {
    init(config: ImageDecorateConfig) {
        let content: GIFWatermark.Content
        switch config.type {
        case let .text(text, font, textColor, bgColor):
            content = .text(text, font: font, textColor: textColor, backgroundColor: bgColor)
        case let .attributeText(text):
            content = .attributedText(text)
        case let .image(image, width):
            content = .image(image, width: width)
        }

        self.init(
            content: content,
            position: config.location.gifPosition,
            offset: config.offset,
            origin: config.origin
        )
    }
}

extension ImageDecorateConfig {
    init(watermark: GIFWatermark) {
        let type: DecoratorType
        switch watermark.content {
        case let .text(text, font, textColor, backgroundColor):
            type = .text(text: text, font: font, textColor: textColor, bgColor: backgroundColor)
        case let .attributedText(text):
            type = .attributeText(text: text)
        case let .image(image, width):
            type = .image(image: image, width: width)
        }

        self.init(
            type: type,
            location: watermark.position.decoratorLocation,
            offset: watermark.offset
        )
        self.origin = watermark.origin
    }
}

extension DecoratorLocation {
    var gifPosition: GIFWatermarkPosition {
        switch self {
        case .topLeft:
            return .topLeft
        case .topRight:
            return .topRight
        case .bottomLeft:
            return .bottomLeft
        case .bottomRight:
            return .bottomRight
        case .center:
            return .center
        }
    }
}
