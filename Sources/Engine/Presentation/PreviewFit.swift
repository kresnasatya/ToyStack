import CoreGraphics
import Foundation

/// Fits the last complete frame into a new viewport while resizing.
public struct PreviewFit: Equatable, Sendable {
    public let scale: CGFloat
    public let scaledSize: CGSize

    public init(old: CGSize, new: CGSize, scale contentScale: ContentScale) {
        guard old.width > 0, old.height > 0, new.width > 0, new.height > 0 else {
            self.scale = 1
            self.scaledSize = old
            return
        }
        let exact: CGFloat = min(1, min(new.width / old.width, new.height / old.height))
        let scale: CGFloat = Self.wholeTileScale(
            exact,
            tileDevicePixels: RasterLayer.tileSize * contentScale.effective
        )
        self.scale = scale
        self.scaledSize = CGSize(width: old.width * scale, height: old.height * scale)
    }

    private static func wholeTileScale(_ scale: CGFloat, tileDevicePixels: CGFloat) -> CGFloat {
        guard scale < 1, tileDevicePixels.isFinite, tileDevicePixels >= 1 else { return scale }
        let pixels: CGFloat = max(1, (scale * tileDevicePixels).rounded(.down))
        return pixels / tileDevicePixels
    }
}
