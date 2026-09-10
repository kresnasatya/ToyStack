import CoreGraphics

struct ThemeState: Equatable {
    var prefersDark: Bool
    var forcedColors: Bool
}

struct ScrollState {
    var scroll: CGFloat
    var interestTop: CGFloat
    var interestBottom: CGFloat
    var maxScroll: CGFloat
}

struct ViewportInfo {
    let windowSize: CGSize
    let topInset: CGFloat
    let displayScale: CGFloat
}

struct RasterFlags {
    let needsComposite: Bool
    let needsDraw: Bool
}

struct AccessibilityBounds: Equatable {
    let hoveredBounds: Rect?
    let readBounds: Rect?
}
