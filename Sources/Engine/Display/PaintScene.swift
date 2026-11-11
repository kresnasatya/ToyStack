import CoreGraphics

// MARK: - PaintScene

/// Node children are indices into the same frame's `nodes`, so the tree is
/// data and paint can walk it without touching a `Frame`, a `LayoutTree`, or a
/// `DOMTree`.
struct PaintScene {
    var frames: [PaintFrame]
}

// MARK: - PaintFrame

struct PaintFrame {
    var nodes: [PaintNode]
    var epoch: UInt
    var revisions: [UInt64]
}

// MARK: - PaintNode

struct PaintNode {
    var geometry: PaintGeometry
    var surface: PaintSurface
    var content: PaintContent
    var links: PaintLinks
}

struct PaintGeometry {
    var rect: Rect
    var frame: Rect
    var zoom: CGFloat
}

struct PaintSurface {
    var style: ComputedStyle
    var font: BrowserFont
    var effects: PaintEffects
    var state: PaintState
}

struct PaintEffects {
    var style: PaintEffectStyle?
    var animatedTransform: Bool
}

struct PaintState {
    var forcedColors: Bool
    var isFocusVisible: Bool
    var isFocused: Bool
}

enum PaintContent {
    case document
    case block(PaintBlock)
    case line(PaintLine)
    case text(PaintText)
    case embed(PaintEmbed)
}

struct PaintBlock {
    var shouldPaint: Bool
    var isListItem: Bool
    var scrollOffset: CGFloat
    var extras: PaintBlockExtras
}

struct PaintBlockExtras {
    var backgroundImage: CGImage?
    var trailing: [DisplayOp]
}

struct PaintLine {
    var canCache: Bool
    var generation: UInt
    var focusRing: [DisplayOp]
    var inlineText: [PaintInlineText]
}

struct PaintInlineText {
    var string: String
    var font: BrowserFont
    var color: BrowserColor
    var rect: Rect
}

struct PaintText {
    var string: String
    var width: CGFloat
    var top: CGFloat
    var color: BrowserColor
}

enum PaintEmbed {
    case image(PaintImage)
    case input(PaintInput)
    case button
    case iframe(PaintIframe)
    case canvas(PaintCanvas)
}

struct PaintImage {
    var image: CGImage?
    var height: CGFloat
}

struct PaintInput {
    var text: String
    var isCheckbox: Bool
    var isChecked: Bool
}

struct PaintIframe {
    var frame: Int?
    var inner: Rect
    var scroll: CGFloat
    var bar: DisplayOp?
}

struct PaintCanvas {
    var image: CGImage?
    var revision: UInt64
}

struct PaintLinks {
    var id: LayoutID
    var dom: NodeID
    var parent: Int?
    var children: [Int]
}
