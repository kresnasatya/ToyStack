import CoreGraphics

// MARK: - RoundedRectPath

public func roundedRectPath(rect: Rect, radii: CornerRadii) -> CGPath {
    let resolved: CornerRadii = radii.resolved(in: rect)
    if resolved.isZero {
        return CGPath(rect: rect.cgRect, transform: nil)
    }
    if let uniform = resolved.uniformPx {
        return CGPath(
            roundedRect: rect.cgRect,
            cornerWidth: uniform.horizontal,
            cornerHeight: uniform.vertical,
            transform: nil
        )
    }
    return perCornerRoundedRectPath(rect: rect, radii: resolved)
}

// How far a cubic's control points sit along each edge to fit a quarter
// circle: the same construction CoreGraphics, PDF, SVG, and Skia use.
//
// It's exactly `(4/3)(sqrt2 - 1)`, the value that puts the curve's midpoint (`t = 1/2`) on the arc's 45-degree point.
// Forcing `B(1/2) = (sqrt2/2, sqrt2/2)` on the unit quarter gives `1/2 + 3k/8 = sqrt2/2`.
// Worst radial error either side of the midpoint is 2.7e-4 of the radius.
private let quarterArcKappa: CGFloat = (4.0 / 3.0) * (2.0.squareRoot() - 1.0)

private func perCornerRoundedRectPath(rect: Rect, radii: CornerRadii) -> CGPath {
    guard let tl = radii.topLeft.px, let tr = radii.topRight.px,
        let br = radii.bottomRight.px, let bl = radii.bottomLeft.px
    else { return CGPath(rect: rect.cgRect, transform: nil) }

    let x0: CGFloat = rect.left
    let y0: CGFloat = rect.top
    let x1: CGFloat = rect.right
    let y1: CGFloat = rect.bottom
    let k: CGFloat = quarterArcKappa
    let path: CGMutablePath = CGMutablePath()

    path.move(to: CGPoint(x: x0 + tl.horizontal, y: y0))

    path.addLine(to: CGPoint(x: x1 - tr.horizontal, y: y0))
    path.addCurve(
        to: CGPoint(x: x1, y: y0 + tr.vertical),
        control1: CGPoint(x: x1 - tr.horizontal + k * tr.horizontal, y: y0),
        control2: CGPoint(x: x1, y: y0 + tr.vertical - k * tr.vertical)
    )

    path.addLine(to: CGPoint(x : x1, y: y1 - br.vertical))
    path.addCurve(
        to: CGPoint(x: x1 - br.horizontal, y: y1),
        control1: CGPoint(x: x1, y: y1 - br.vertical + k * br.vertical),
        control2: CGPoint(x: x1 - br.horizontal + k * br.horizontal, y: y1)
    )

    path.addLine(to: CGPoint(x: x0 + bl.horizontal, y: y1))
    path.addCurve(
        to: CGPoint(x: x0, y: y1 - bl.vertical),
        control1: CGPoint(x : x0 + bl.horizontal - k * bl.horizontal, y: y1),
        control2: CGPoint(x: x0, y: y1 - bl.vertical + k * bl.vertical)
    )

    path.addLine(to: CGPoint(x: x0, y: y0 + tl.vertical))
    path.addCurve(
        to: CGPoint(x: x0 + tl.horizontal, y: y0),
        control1: CGPoint(x: x0, y: y0 + tl.vertical - k * tl.vertical),
        control2: CGPoint(x: x0 + tl.horizontal - k * tl.horizontal, y: y0)
    )

    path.closeSubpath()
    return path
}
