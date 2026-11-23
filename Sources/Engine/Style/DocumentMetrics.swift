import CoreGraphics

// MARK: - DocumentMetrics

struct DocumentMetrics: Equatable {
    var rootFontSize: CGFloat
    var viewport: CGSize

    static let initial: DocumentMetrics = DocumentMetrics(
        rootFontSize: TextStyle.initial.font.size,
        viewport: .zero
    )
}
