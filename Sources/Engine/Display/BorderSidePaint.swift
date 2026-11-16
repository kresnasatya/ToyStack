import CoreGraphics

// MARK: - BorderSidePaint

/// One side of one band of a border. The band is the ring between two
/// curves; `region` is this side's share of it, cut at the corner lines so
/// neighbouring sides meet without overlapping.
public struct BorderSidePaint: Sendable {
    let band: BorderBand
    let region: Quad
    let color: BrowserColor
    /// Dots or dashes along the band; nil fills the whole region.
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

/// A stroke along the middle of a band, broken into dashes. A dash of
/// length zero with round caps is a dot.
public struct BorderDash: Sendable {
    let line: BorderSideLine
    let lineWidth: CGFloat
    let on: CGFloat
    let off: CGFloat

    func translated(dx: CGFloat, dy: CGFloat) -> BorderDash {
        return BorderDash(line: line.translated(dx: dx, dy: dy), lineWidth: lineWidth, on: on, off: off)
    }
}
