import CoreGraphics

func drawCursor(origin: Point, height: CGFloat, offset: CGFloat) -> DisplayOp {
    let x: CGFloat = origin.x + offset
    return .line(
        from: Point(x: x, y: origin.y),
        to: Point(x: x, y: origin.y + height),
        color: BrowserColor(cssName: "red"),
        width: 1
    )
}
