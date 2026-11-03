import CoreGraphics
import Foundation

// MARK: - BlockData

struct BlockData {
    var content: BlockContent
    var scroll: BlockScroll
    var paint: BlockPaint
    var changes: BlockChanges

    init() {
        self.content = BlockContent()
        self.scroll = BlockScroll()
        self.paint = BlockPaint()
        self.changes = BlockChanges()
    }
}

// MARK: - BlockContent

struct BlockContent {
    var extraNodes: [NodeID]
    var inlineItems: [InlineItem]
    var inlineObjects: [Int: LayoutID]
    var inlineLinePlan: [[Int]]?

    init() {
        self.extraNodes = []
        self.inlineItems = []
        self.inlineObjects = [:]
        self.inlineLinePlan = nil
    }
}

// MARK: - BlockScroll

struct BlockScroll {
    var offset: CGFloat
    var contentHeight: CGFloat

    init() {
        self.offset = 0
        self.contentHeight = 0
    }
}

// MARK: - BlockPaint

struct BlockPaint {
    var style: BlockStyle?
    var styleRevision: UInt64

    init() {
        self.style = nil
        self.styleRevision = 0
    }
}

// MARK: - BlockChanges

struct BlockChanges {
    var childChanges: [BlockChildChange]
    var declaredHeightChildren: [LayoutID]

    init() {
        self.childChanges = []
        self.declaredHeightChildren = []
    }
}

// MARK: - BlockChildChange

enum BlockChildChange {
    case append([NodeID])
    case insert([NodeID], before: NodeID)
}
