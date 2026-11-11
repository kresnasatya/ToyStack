import CoreGraphics

struct ScrollTargetState {
    var iframes: [IframeTarget]
    var blocks: [ScrollBlockTarget]
    /// Only compared for equality.
    private(set) var revision: UInt64
    var builtRevision: UInt64

    init() {
        self.iframes = []
        self.blocks = []
        self.revision = 1
        self.builtRevision = 0
    }

    mutating func invalidate() {
        revision &+= 1
    }

    /// The revision keeps counting up, so a pass recorded before the clear
    /// can never look current.
    mutating func clear() {
        iframes = []
        blocks = []
        invalidate()
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
