import CoreGraphics

@testable import Engine

/// A display list drawn at 1x on a transparent canvas, read back pixel by
/// pixel. Lets a test check what a reader would see, not which ops made it.
struct PagePixels {
    private let bytes: [UInt8]
    private let width: Int
    private let height: Int

    init(_ ops: [DisplayOp], width: Int, height: Int) {
        let size: CGSize = CGSize(width: width, height: height)
        let image: CGImage? = CGRenderer.renderBitmap(size: size, target: RasterTarget(scale: 1)) { renderer in
            renderDisplayList(ops, renderer: renderer)
        }
        var bytes: [UInt8] = Array(repeating: 0, count: width * height * 4)
        if let image {
            bytes.withUnsafeMutableBytes { buffer in
                let context: CGContext? = CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: RasterTarget.sRGB,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
                context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
        }
        self.bytes = bytes
        self.width = width
        self.height = height
    }

    /// The pixel whose area contains the point (`x`, `y`), counted from the
    /// top left of the page.
    func color(x: CGFloat, y: CGFloat) -> BrowserColor {
        let column: Int = Int(x.rounded(.down))
        let row: Int = Int(y.rounded(.down))
        guard column >= 0, column < width, row >= 0, row < height else {
            return BrowserColor(red: 0, green: 0, blue: 0, alpha: 0)
        }
        let offset: Int = (row * width + column) * 4
        return BrowserColor(
            red: Double(bytes[offset]) / 255,
            green: Double(bytes[offset + 1]) / 255,
            blue: Double(bytes[offset + 2]) / 255,
            alpha: Double(bytes[offset + 3]) / 255
        )
    }

    func isClear(x: CGFloat, y: CGFloat) -> Bool {
        return color(x: x, y: y).alpha < 0.1
    }

    /// Close to `expected` on every channel, allowing for antialiasing and
    /// color-space rounding.
    func matches(_ expected: BrowserColor, x: CGFloat, y: CGFloat) -> Bool {
        let actual: BrowserColor = color(x: x, y: y)
        let tolerance: Double = 0.1
        return abs(actual.red - expected.red) < tolerance
            && abs(actual.green - expected.green) < tolerance
            && abs(actual.blue - expected.blue) < tolerance
            && abs(actual.alpha - expected.alpha) < tolerance
    }
}
