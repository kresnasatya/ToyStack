import CoreGraphics
import Foundation

// MARK: - LineData

struct LineData {
    var content: LineContent
    var paint: LinePaint
    var placement: LinePlacement

    init() {
        self.content = LineContent()
        self.paint = LinePaint()
        self.placement = LinePlacement()
    }
}

// MARK: - LineContent

struct LineContent {
    var centered: Bool
    var hasEmbed: Bool

    init() {
        self.centered = false
        self.hasEmbed = false
    }
}

// MARK: - LinePaint

struct LinePaint {
    var generation: UInt
    var paintedChildCount: Int

    init() {
        self.generation = 0
        self.paintedChildCount = -1
    }
}

// MARK: - LinePlacement

struct LinePlacement {
    var inlineYOffset: CGFloat
    var childOriginY: CGFloat?
    var declaredInlineChildCount: Int

    init() {
        self.inlineYOffset = 0
        self.childOriginY = nil
        self.declaredInlineChildCount = -1
    }
}
