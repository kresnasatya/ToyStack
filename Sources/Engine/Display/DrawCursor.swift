import CoreGraphics

@MainActor
func drawCursor(_ object: LayoutRef, offset: CGFloat) -> DisplayOp {
    let x: CGFloat = object.x + offset
    return .line(
        from: Point(x: x, y: object.y),
        to: Point(x: x, y: object.y + object.height),
        color: BrowserColor(cssName: "red"),
        width: 1
    )
}
