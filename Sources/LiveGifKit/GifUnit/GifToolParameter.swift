import Foundation
import Photos
#if canImport(PhotosUI)
import PhotosUI
#endif

/// 生成Gif的参数Model
///
///gifFPS: gif帧率 默认 30
///DecoratorInfo: 水印信息 默认为空
///data: DataSource、livePhoto和图片两种方式
///maxResolution: 图片大小 默认300
///removeImageBgColor: 是否去背景
@available(*, deprecated, message: "Use GIFGenerationRequest and GIFGenerationOptions.")
public struct GifToolParameter {
    public var data: DataSource
    public var gifFPS: CGFloat
    public var imageDecorates: [ImageDecorateConfig]
    public var maxResolution: CGFloat
    public var removeBg: Bool
    public var isReturnOriginFrames: Bool
    
    @available(*, deprecated, message: "Use GIFGenerationSource.")
    public enum DataSource {
        #if canImport(PhotosUI)
        case livePhoto(livePhoto: PHLivePhoto, livePhotoFPS: CGFloat = 30)
        #endif
        case images(frames: [GIFImage], adjustOrientation: Bool = false)
        case video(url: URL, sourceFPS: CGFloat? = nil)
    }
    
    public init(data: DataSource, gifFPS: CGFloat = 30, imageDecorates: [ImageDecorateConfig] = [], maxResolution: CGFloat = 500, removeBg: Bool = false, isReturnOriginFrames: Bool = false) {
        self.gifFPS = gifFPS
        self.imageDecorates = imageDecorates
        self.data = data
        self.maxResolution = maxResolution
        self.removeBg = removeBg
        self.isReturnOriginFrames = isReturnOriginFrames
    }
    
    var livePhotoFPS: CGFloat {
        switch self.data {
        #if canImport(PhotosUI)
        case .livePhoto(_, let livePhotoFPS):
            return livePhotoFPS
        #endif
        case .images(_, _), .video(_, _):
            return 30
        }
    }
    
    var gifTempDir: URL!
}
