import CoreGraphics

// MARK: - Quad

public struct Quad: Equatable, Sendable {
    var a: Point
    var b: Point
    var c: Point
    var d: Point

    var cgPath: CGPath {
        let path: CGMutablePath = CGMutablePath()
        path.addLines(between: [a.cgPoint, b.cgPoint, c.cgPoint, d.cgPoint])
        path.closeSubpath()
        return path
    }

    func translated(dx: CGFloat, dy: CGFloat) -> Quad {
        return Quad(
            a: Point(x: a.x + dx, y: a.y + dy),
            b: Point(x: b.x + dx, y: b.y + dy),
            c: Point(x: c.x + dx, y: c.y + dy),
            d: Point(x: d.x + dx, y: d.y + dy)
        )
    }
}
