struct RasterInvalidation: Sendable {
    let needsComposite: Bool
    let needsDraw: Bool
}
