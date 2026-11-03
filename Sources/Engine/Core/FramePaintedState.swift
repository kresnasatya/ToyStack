import CoreGraphics

/// The region covered by the last paint.
struct FramePaintedState: Sendable {
    var bottom: CGFloat
    var window: PaintWindow

    init() {
        self.bottom = 0
        self.window = .full
    }
}
