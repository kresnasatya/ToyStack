import CoreGraphics

// MARK: - ImageLoadingRegion
struct ImageLoadingRegion {
    let scroll: CGFloat
    let viewportHeight: CGFloat
    let margin: CGFloat

    func contains(_ rect: Rect) -> Bool {
        let top: CGFloat = scroll - margin
        let bottom: CGFloat = scroll + viewportHeight + margin
        return rect.bottom >= top && rect.top <= bottom
    }
}
