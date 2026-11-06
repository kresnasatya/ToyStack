import CoreGraphics
import Foundation

/// Fits the last complete frame into a new viewport while resizing.
public struct PreviewFit: Equatable, Sendable {
    public let scale: CGFloat
    public let scaledSize: CGSize

    public init(old: CGSize, new: CGSize) {
        guard old.width > 0, old.height > 0, new.width > 0, new.height > 0 else {
            self.scale = 1
            self.scaledSize = old
            return
        }
        let scale: CGFloat = min(1, min(new.width / old.width, new.height / old.height))
        self.scale = scale
        self.scaledSize = CGSize(width: old.width * scale, height: old.height * scale)
    }
}
