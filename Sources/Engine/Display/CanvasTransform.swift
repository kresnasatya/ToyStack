import CoreGraphics

// MARK: - CanvasTransform
struct CanvasTransform {
    private(set) var matrix: CGAffineTransform

    static let identity: CanvasTransform = CanvasTransform(matrix: .identity)

    var isIdentity: Bool { matrix.isIdentity }

    func translated(x: CGFloat, y: CGFloat) -> CanvasTransform {
        CanvasTransform(matrix: CGAffineTransform(translationX: x, y: y)).concatenating(self)
    }

    func scaled(x: CGFloat, y: CGFloat) -> CanvasTransform {
        CanvasTransform(matrix: CGAffineTransform(scaleX: x, y: y)).concatenating(self)
    }

    func rotated(by angle: CGFloat) -> CanvasTransform {
        CanvasTransform(matrix: CGAffineTransform(rotationAngle: angle)).concatenating(self)
    }

    func concatenating(_ other: CanvasTransform) -> CanvasTransform {
        CanvasTransform(matrix: matrix.concatenating(other.matrix))
    }
}
