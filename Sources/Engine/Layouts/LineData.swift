import CoreGraphics
import Foundation

// MARK: - LineData

struct LineData {
    var content: LineContent
    var paint: LinePaint
    var placement: LinePlacement
    var inlineBoxes: LineInlineBoxes

    init() {
        self.content = LineContent()
        self.paint = LinePaint()
        self.placement = LinePlacement()
        self.inlineBoxes = LineInlineBoxes()
    }
}

// MARK: - LineInlineBoxes

/// Inline elements with padding or border on this line: `events` is what the
/// block's placement recorded, `fragments` is where the line put them.
struct LineInlineBoxes {
    var events: [InlineFlowEvent]
    var fragments: [InlineBoxFragment]

    init() {
        self.events = []
        self.fragments = []
    }
}

// MARK: - LineContent

struct LineContent {
    var centered: Bool
    var hasEmbed: Bool
    var inlineWidths: [CGFloat]
    var boxes: [InlineBox]

    init() {
        self.centered = false
        self.hasEmbed = false
        self.inlineWidths = []
        self.boxes = []
    }
}

// MARK: - LinePaint

struct LinePaint {
    var generation: UInt
    var paintedChildCount: Int
    var boxRevision: UInt64

    init() {
        self.generation = 0
        self.paintedChildCount = -1
        self.boxRevision = 0
    }
}

// MARK: - LinePlacement

struct LinePlacement {
    var inlineYOffset: CGFloat
    var childOriginY: CGFloat?
    var declaredInlineChildCount: Int
    var floatInsets: LineFloatInsets

    init() {
        self.inlineYOffset = 0
        self.childOriginY = nil
        self.declaredInlineChildCount = -1
        self.floatInsets = .zero
    }
}

// MARK: - LineFloatInsets

/// CSS 2.1 §9.5: a line box next to a float is shortened by the float's
/// margin box, and moves down below it when even its first item does not fit.
struct LineFloatInsets: Equatable {
    var left: CGFloat
    var right: CGFloat
    var gap: CGFloat

    static let zero: LineFloatInsets = LineFloatInsets(left: 0, right: 0, gap: 0)
}
