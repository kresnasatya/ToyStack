struct RasterSettings: Sendable {
    let viewport: Viewport
    let preferences: ColorPreferences
    let flags: RasterInvalidation
    let accessibility: AccessibilityBounds
}
