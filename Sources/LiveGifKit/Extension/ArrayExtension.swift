import CoreGraphics

extension Array where Element == CGImage {
    func cropImages(toRect rect: CGRect) -> [CGImage] {
        compactMap { $0.cropImage(toRect: rect) }
    }
}
