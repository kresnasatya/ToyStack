import CoreGraphics

struct FrameScrollState {
    var offset: CGFloat
    var interestTop: CGFloat

    init() {
        self.offset = 0
        self.interestTop = 0
    }
}
