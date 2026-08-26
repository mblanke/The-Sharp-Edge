import XCTest
@testable import TheSharpEdge

/// The photo path exists to survive a 40 MB ProRAW capture: decoding one whole
/// would spike memory and stall the upload, which is what kept the phone failing.
final class ImageDownsampleTests: XCTestCase {
    private func bigImageData(width: Int, height: Int) -> Data {
        let size = CGSize(width: width, height: height)
        // scale 1 so "width" means pixels; the renderer defaults to screen scale,
        // which would silently make every fixture 3x bigger than it reads.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            // some structure so the JPEG cannot compress to nothing
            UIColor.black.setFill()
            for row in stride(from: 0, to: height, by: 40) {
                ctx.fill(CGRect(x: 0, y: row, width: width, height: 12))
            }
        }
        return image.jpegData(compressionQuality: 1.0)!
    }

    func testLargePhotoIsBoundedAndShrunk() throws {
        let original = bigImageData(width: 4032, height: 3024)  // 12 MP, iPhone-sized
        let shrunk = try XCTUnwrap(downsampledJPEG(from: original, maxPixel: 1400))

        // A flat synthetic image already compresses well, so assert the property
        // that matters — bounded pixels and a small absolute payload — rather than
        // a ratio that only holds for detailed photographs.
        XCTAssertLessThan(shrunk.count, original.count, "downsample must shrink it")
        let decoded = try XCTUnwrap(UIImage(data: shrunk))
        XCTAssertLessThanOrEqual(max(decoded.size.width, decoded.size.height), 1400)
        // comfortably inside the server's 15 MB ceiling, and quick over Tailscale
        XCTAssertLessThan(shrunk.count, 1_500_000)
    }

    func testSmallImagePassesThroughWithoutUpscaling() throws {
        let original = bigImageData(width: 800, height: 600)
        let shrunk = try XCTUnwrap(downsampledJPEG(from: original, maxPixel: 1400))
        let decoded = try XCTUnwrap(UIImage(data: shrunk))
        XCTAssertLessThanOrEqual(max(decoded.size.width, decoded.size.height), 800)
    }

    func testGarbageBytesReturnNilRatherThanCrashing() {
        XCTAssertNil(downsampledJPEG(from: Data("not an image".utf8), maxPixel: 1400))
    }
}
