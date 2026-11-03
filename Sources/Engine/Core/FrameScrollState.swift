import CoreGraphics

/// The frame's scroll offset and interest window.
struct FrameScrollState {
    var offset: CGFloat
    var interestTop: CGFloat

    init() {
        self.offset = 0
        self.interestTop = 0
    }
}
