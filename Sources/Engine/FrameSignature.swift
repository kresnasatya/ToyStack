import CoreGraphics

struct FrameSignature: Equatable {
    let viewport: FrameViewport
    let revisions: FrameRevisions
    let preferences: ColorPreferences
    let accessibility: AccessibilityBounds
}
