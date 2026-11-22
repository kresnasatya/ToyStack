import CoreGraphics

// MARK: - BorderPainter

struct BorderPainter {
    let box: Rect
    let border: BoxStyle.Decoration.Border
    let widths: EdgeInsets

    func emit(into items: inout [DisplayOp]) {
        let visible: [BoxSide] = BoxSide.allCases.filter({ widths[$0] > 0 })
        guard let first: BoxSide = visible.first else { return }
        let color: BrowserColor = border.sides[first].color
        let oneSolidColor: Bool = visible.allSatisfy({ side in
            let line: BoxStyle.Decoration.Border.Side = border.sides[side]
            return line.color == color && Self.paintsSolid(line.style)
        })
        if oneSolidColor {
            emitSolid(color, into: &items)
            return
        }
        let regions: [Quad] = sideRegions()
        for side in visible {
            let pattern: BorderDash? = dash(side)
            for band in bands(side) {
                items.append(.borderSide(BorderSidePaint(
                    band: BorderBand(outer: shape(inset: band.from), inner: shape(inset: band.to)),
                    region: regions[side.rawValue],
                    color: band.color,
                    dash: pattern
                )))
            }
        }
    }

    private func emitSolid(_ color: BrowserColor, into items: inout [DisplayOp]) {
        if !border.radii.isZero {
            items.append(.ring(outer: shape(inset: 0), inner: shape(inset: 1), color: color))
            return
        }
        let innerTop: CGFloat = box.top + widths.top
        let innerBottom: CGFloat = box.bottom - widths.bottom
        let pieces: [Rect] = [
            Rect(left: box.left, top: box.top, right: box.right, bottom: innerTop),
            Rect(left: box.right - widths.right, top: innerTop, right: box.right, bottom: innerBottom),
            Rect(left: box.left, top: innerBottom, right: box.right, bottom: box.bottom),
            Rect(left: box.left, top: innerTop, right: box.left + widths.left, bottom: innerBottom),
        ]
        for side in BoxSide.allCases where widths[side] > 0 {
            items.append(.rect(rect: pieces[side.rawValue], color: color))
        }
    }

    /// The border box shrunk by `fraction` of each side's width, with its
    /// corner curves shrunk to match (CSS Backgrounds 3 §4.2).
    private func shape(inset fraction: CGFloat) -> ClipShape {
        let inset: EdgeInsets = widths.scaled(by: fraction)
        return ClipShape(rect: box.inset(by: inset), radii: border.radii.inner(in: box, inset: inset))
    }

    // MARK: - Styles

    private static func paintsSolid(_ style: BoxStyle.Decoration.LineStyle) -> Bool {
        switch style {
        case .solid, .other: return true
        default: return false
        }
    }

    /// CSS Backgrounds 3 §3.2: groove looks carved into the canvas, ridge looks like it comes
    /// out of it, inset makes the content look sunken into it, and outset raised out of it.
    /// Each band covers part of the side's width, measured from the outside in. Light falls from
    /// the top left, so a sunken top or left side is in shadow and a sunken bottom or right side
    /// is lit; groove and ridge are half sunken, half raised.
    private func bands(_ side: BoxSide) -> [(from: CGFloat, to: CGFloat, color: BrowserColor)] {
        let line: BoxStyle.Decoration.Border.Side = border.sides[side]
        let lit: BrowserColor = line.color
        let shaded: BrowserColor = Self.shadow(of: lit)
        let facesLight: Bool = side == .top || side == .left
        let sunken: BrowserColor = facesLight ? shaded : lit
        let raised: BrowserColor = facesLight ? lit : shaded
        switch line.style {
        case .double:
            return [(0, 1.0 / 3.0, lit), (2.0 / 3.0, 1, lit)]
        case .groove:
            return [(0, 0.5, sunken), (0.5, 1, raised)]
        case .ridge:
            return [(0, 0.5, raised), (0.5, 1, sunken)]
        case .inset:
            return [(0, 1, sunken)]
        case .outset:
            return [(0, 1, raised)]
        default:
            return [(0, 1, lit)]
        }
    }

    /// The darker tone of groove, ridge, inset and outset. Black has no darker tone, so it
    /// shades to gray instead; the CSS Backgrounds 3 §3.2 note says colors close to black may
    /// need different color calculations.
    private static func shadow(of color: BrowserColor) -> BrowserColor {
        let brightest: Double = max(color.red, color.green, color.blue)
        guard brightest > 0 else {
            return BrowserColor(red: 84.0 / 255.0, green: 84.0 / 255.0, blue: 84.0 / 255.0, alpha: color.alpha)
        }
        let scale: Double = max(0, (brightest - 0.33) / brightest)
        return BrowserColor(
            red: color.red * scale,
            green: color.green * scale,
            blue: color.blue * scale,
            alpha: color.alpha
        )
    }

    /// CSS Backgrounds 3 §3.2 note: implementations are encouraged to choose a spacing that
    /// makes the corners symmetrical. So each side starts and ends on a dot or a dash and spreads
    /// the rest evenly. Dots are as wide as the border with a gap of the same size; dashes are
    /// three times as long as the border is wide.
    private func dash(_ side: BoxSide) -> BorderDash? {
        let width: CGFloat = widths[side]
        let middle: ClipShape = shape(inset: 0.5)
        switch border.sides[side].style {
        case .dotted:
            let length: CGFloat = BorderSideLine(middle: middle, side: side, startOverhang: 0, endOverhang: 0).length
            guard length > 0 else { return nil }
            let spacing: CGFloat = length / max(1, (length / (2 * width)).rounded())
            let line: BorderSideLine = BorderSideLine(middle: middle, side: side, startOverhang: 0, endOverhang: spacing / 2)
            return BorderDash(line: line, lineWidth: width, on: 0, off: spacing)
        case .dashed:
            let line: BorderSideLine = BorderSideLine(
                middle: middle,
                side: side,
                startOverhang: widths[side.previous] / 2,
                endOverhang: widths[side.next] / 2
            )
            let length: CGFloat = line.length
            let dash: CGFloat = 3 * width
            let count: CGFloat = ((length + dash) / (2 * dash)).rounded()
            guard count > 1 else { return nil }
            return BorderDash(line: line, lineWidth: width, on: dash, off: (length - count * dash) / (count - 1))
        default:
            return nil
        }
    }

    // MARK: - Corners

    /// CSS Backgrounds 3 §4.4 only asks that two sides change over inside the
    /// corner, at a point that moves steadily with the ratio of their widths;
    /// it leaves the shape of the change undefined. Like Chromium, this
    /// engine splits the corner on the line from the outer corner through
    /// the corner of the padding box. Where the inner edge is curved the line
    /// runs on to the chord of that curve, so every part of the corner falls
    /// on one side or the other. A side with no width leaves the whole corner
    /// to its neighbour, as §4.4 requires.
    private func sideRegions() -> [Quad] {
        let inner: CornerRadii = border.radii.inner(in: box, inset: widths)
        let outer: [Point] = [
            Point(x: box.left, y: box.top),
            Point(x: box.right, y: box.top),
            Point(x: box.right, y: box.bottom),
            Point(x: box.left, y: box.bottom),
        ]
        let ends: [Point] = [
            cornerLineEnd(outer[0], inward: CGVector(dx: widths.left, dy: widths.top), curve: inner.topLeft),
            cornerLineEnd(outer[1], inward: CGVector(dx: -widths.right, dy: widths.top), curve: inner.topRight),
            cornerLineEnd(outer[2], inward: CGVector(dx: -widths.right, dy: -widths.bottom), curve: inner.bottomRight),
            cornerLineEnd(outer[3], inward: CGVector(dx: widths.left, dy: -widths.bottom), curve: inner.bottomLeft),
        ]
        return BoxSide.allCases.map({ side in
            let start: Int = side.rawValue
            let end: Int = side.next.rawValue
            return Quad(a: outer[start], b: outer[end], c: ends[end], d: ends[start])
        })
    }

    private func cornerLineEnd(_ corner: Point, inward: CGVector, curve: CornerRadius) -> Point {
        let padding: Point = Point(x: corner.x + inward.dx, y: corner.y + inward.dy)
        guard let radius: (horizontal: CGFloat, vertical: CGFloat) = curve.px,
            radius.horizontal > 0, radius.vertical > 0,
            inward.dx != 0 || inward.dy != 0
        else { return padding }
        let reach: CGFloat = 1 / (abs(inward.dx) / radius.horizontal + abs(inward.dy) / radius.vertical)
        return Point(x: padding.x + inward.dx * reach, y: padding.y + inward.dy * reach)
    }
}
