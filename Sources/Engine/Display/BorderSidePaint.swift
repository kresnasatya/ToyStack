import CoreGraphics

// MARK: - BorderSidePaint

public struct BorderSidePaint: Sendable {
    let band: BorderBand
    let region: Quad
    let color: BrowserColor
    let dash: BorderDash?

    func translated(dx: CGFloat, dy: CGFloat) -> BorderSidePaint {
        return BorderSidePaint(
            band: BorderBand(
                outer: ClipShape(rect: band.outer.rect.translated(dx: dx, dy: dy), radii: band.outer.radii),
                inner: ClipShape(rect: band.inner.rect.translated(dx: dx, dy: dy), radii: band.inner.radii)
            ),
            region: region.translated(dx: dx, dy: dy),
            color: color,
            dash: dash?.translated(dx: dx, dy: dy)
        )
    }
}

// MARK: - BorderBand

public struct BorderBand: Sendable {
    let outer: ClipShape
    let inner: ClipShape
}

// MARK: - BorderDash

public struct BorderDash: Sendable {
    let line: BorderSideLine
    let lineWidth: CGFloat
    let on: CGFloat
    let off: CGFloat

    func translated(dx: CGFloat, dy: CGFloat) -> BorderDash {
        return BorderDash(line: line.translated(dx: dx, dy: dy), lineWidth: lineWidth, on: on, off: off)
    }
}
