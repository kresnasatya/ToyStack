import CoreGraphics

struct FrameGeometry: Equatable {
    let scroll: CGFloat
    let viewport: CGSize
    let displayScale: CGFloat
}

struct FrameEpoch: Equatable {
    let paintEpoch: UInt
    let effectUpdates: UInt
}

struct FrameSignature: Equatable {
    let geometry: FrameGeometry
    let epochs: FrameEpoch
    let theme: ThemeState
    let accessibility: AccessibilityBounds
}
