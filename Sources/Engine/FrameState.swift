import CoreGraphics

struct ThemeState: Equatable {
    let prefersDark: Bool
    let forcedColors: Bool
}

struct ScrollState {
    let scroll: CGFloat
    let interestTop: CGFloat
    let interestBottom: CGFloat
    let maxScroll: CGFloat
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
