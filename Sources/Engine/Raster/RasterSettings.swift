struct RasterSettings: Sendable {
    let viewport: Viewport
    let colors: PageColors
    let flags: RasterInvalidation
    let accessibility: AccessibilityBounds
}
