import CoreGraphics

/// Cached hit regions for iframes and independently scrollable blocks.
struct ScrollTargetState {
    var iframes: [IframeTarget]
    var blocks: [ScrollBlockTarget]
    var isValid: Bool
    var needsRebuild: Bool

    init() {
        self.iframes = []
        self.blocks = []
        self.isValid = false
        self.needsRebuild = false
    }
}

// MARK: - IframeTarget

struct IframeTarget {
    let rect: Rect
    let layout: LayoutID
    let node: NodeID
}

// MARK: - ScrollBlockTarget

struct ScrollBlockTarget {
    let rect: Rect
    let node: NodeID
    let layout: LayoutID
}
