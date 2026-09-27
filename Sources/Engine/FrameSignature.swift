import CoreGraphics

struct FrameGeometry: Equatable {
    let scroll: CGFloat
    let viewport: CGSize
    let displayScale: CGFloat
}

struct FrameSignature: Equatable {
    let geometry: FrameGeometry
    let revisions: FrameRevisions
    let preferences: ColorPreferences
    let accessibility: AccessibilityBounds
}
