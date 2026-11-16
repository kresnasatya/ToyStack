import CoreGraphics

// MARK: - BorderSideLine

/// The middle line of one border side, the path its dots or dashes follow.
/// Walking clockwise, it takes in the whole corner curve at each end; the
/// side's region cuts off the part that belongs to the neighbouring side.
/// At a square corner it can run past the middle line by an overhang.
struct BorderSideLine: Sendable {
    /// Halfway between the outer and inner edges of the border.
    let middle: ClipShape
    let side: BoxSide
    let startOverhang: CGFloat
    let endOverhang: CGFloat

    var path: CGPath {
        let path: CGMutablePath = CGMutablePath()
        walk(into: path)
        return path
    }

    var length: CGFloat {
        return walk(into: nil)
    }

    func translated(dx: CGFloat, dy: CGFloat) -> BorderSideLine {
        return BorderSideLine(
            middle: ClipShape(rect: middle.rect.translated(dx: dx, dy: dy), radii: middle.radii),
            side: side,
            startOverhang: startOverhang,
            endOverhang: endOverhang
        )
    }

    @discardableResult
    private func walk(into path: CGMutablePath?) -> CGFloat {
        let corners: [MiddleCorner] = MiddleCorner.all(in: middle)
        let from: MiddleCorner = corners[side.rawValue]
        let to: MiddleCorner = corners[side.next.rawValue]
        let direction: CGVector = unitVector(from: from.point, to: to.point)
        var length: CGFloat = 0

        if from.isRound {
            path?.move(to: from.before)
            from.addCurve(to: path)
            length += from.arcLength
        } else {
            path?.move(to: moved(from.point, along: direction, by: -startOverhang))
            length += startOverhang
        }
        path?.addLine(to: to.before)
        length += distance(from.after, to.before)
        if to.isRound {
            to.addCurve(to: path)
            length += to.arcLength
        } else if endOverhang > 0 {
            path?.addLine(to: moved(to.point, along: direction, by: endOverhang))
            length += endOverhang
        }
        return length
    }
}

// MARK: - MiddleCorner

/// One corner of the middle line: the corner of its rectangle, and where its
/// curve meets the side before it and the side after it, walking clockwise.
/// A square corner has all three at the same point.
private struct MiddleCorner {
    let point: CGPoint
    let before: CGPoint
    let after: CGPoint

    var isRound: Bool { before != after }

    /// Ramanujan's approximation of a quarter of an ellipse's perimeter.
    var arcLength: CGFloat {
        let a: CGFloat = distance(before, point)
        let b: CGFloat = distance(after, point)
        return CGFloat.pi / 4 * (3 * (a + b) - ((3 * a + b) * (a + 3 * b)).squareRoot())
    }

    func addCurve(to path: CGMutablePath?) {
        path?.addCurve(
            to: after,
            control1: CGPoint(
                x: before.x + quarterArcKappa * (point.x - before.x),
                y: before.y + quarterArcKappa * (point.y - before.y)
            ),
            control2: CGPoint(
                x: after.x + quarterArcKappa * (point.x - after.x),
                y: after.y + quarterArcKappa * (point.y - after.y)
            )
        )
    }

    /// Top left, top right, bottom right, bottom left: the index of each
    /// corner is the `BoxSide` that starts there.
    static func all(in shape: ClipShape) -> [MiddleCorner] {
        let rect: Rect = shape.rect
        let radii: CornerRadii = shape.radii.resolved(in: rect)

        func reach(_ corner: CornerRadius) -> (horizontal: CGFloat, vertical: CGFloat) {
            guard let px: (horizontal: CGFloat, vertical: CGFloat) = corner.px, px.horizontal > 0, px.vertical > 0 else {
                return (0, 0)
            }
            return px
        }

        let topLeft: (horizontal: CGFloat, vertical: CGFloat) = reach(radii.topLeft)
        let topRight: (horizontal: CGFloat, vertical: CGFloat) = reach(radii.topRight)
        let bottomRight: (horizontal: CGFloat, vertical: CGFloat) = reach(radii.bottomRight)
        let bottomLeft: (horizontal: CGFloat, vertical: CGFloat) = reach(radii.bottomLeft)
        return [
            MiddleCorner(
                point: CGPoint(x: rect.left, y: rect.top),
                before: CGPoint(x: rect.left, y: rect.top + topLeft.vertical),
                after: CGPoint(x: rect.left + topLeft.horizontal, y: rect.top)
            ),
            MiddleCorner(
                point: CGPoint(x: rect.right, y: rect.top),
                before: CGPoint(x: rect.right - topRight.horizontal, y: rect.top),
                after: CGPoint(x: rect.right, y: rect.top + topRight.vertical)
            ),
            MiddleCorner(
                point: CGPoint(x: rect.right, y: rect.bottom),
                before: CGPoint(x: rect.right, y: rect.bottom - bottomRight.vertical),
                after: CGPoint(x: rect.right - bottomRight.horizontal, y: rect.bottom)
            ),
            MiddleCorner(
                point: CGPoint(x: rect.left, y: rect.bottom),
                before: CGPoint(x: rect.left + bottomLeft.horizontal, y: rect.bottom),
                after: CGPoint(x: rect.left, y: rect.bottom - bottomLeft.vertical)
            ),
        ]
    }
}

// MARK: - Vector helpers

private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    return ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
}

private func unitVector(from a: CGPoint, to b: CGPoint) -> CGVector {
    let length: CGFloat = distance(a, b)
    guard length > 0 else { return CGVector(dx: 0, dy: 0) }
    return CGVector(dx: (b.x - a.x) / length, dy: (b.y - a.y) / length)
}

private func moved(_ point: CGPoint, along direction: CGVector, by amount: CGFloat) -> CGPoint {
    return CGPoint(x: point.x + direction.dx * amount, y: point.y + direction.dy * amount)
}
