import Foundation

struct FrameLayoutState {
    var tree: FrameLayoutTree
    var viewport: FrameViewportState
    var scroll: FrameScrollState
    var targets: ScrollTargetState

    init(width: CGFloat, height: CGFloat) {
        self.tree = FrameLayoutTree()
        self.viewport = FrameViewportState(width: width, height: height)
        self.scroll = FrameScrollState()
        self.targets = ScrollTargetState()
    }
}
