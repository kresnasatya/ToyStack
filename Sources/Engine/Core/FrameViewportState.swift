import CoreGraphics

/// The frame's own layout viewport in CSS pixels.
struct FrameViewportState {
    var width: CGFloat
    var height: CGFloat
    var zoom: CGFloat

    init(width: CGFloat, height: CGFloat, zoom: CGFloat = 1) {
        self.width = width
        self.height = height
        self.zoom = zoom
    }
}
