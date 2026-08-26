import ImageIO
import UIKit

/// Decode straight to a bounded size with ImageIO. This is the only way a 40 MB
/// ProRAW/HEIC capture becomes an upload without ever existing full-size in memory,
/// and it handles every format the camera and photo library produce.
func downsampledJPEG(from data: Data, maxPixel: CGFloat) -> Data? {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
        return nil
    }
    let options = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,   // honour EXIF rotation
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ] as CFDictionary
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
        return nil
    }
    return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.6)
}
