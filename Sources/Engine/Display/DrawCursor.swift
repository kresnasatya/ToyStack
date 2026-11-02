import CoreGraphics

@MainActor
func drawCursor(_ object: any LayoutObject, offset: CGFloat) -> DisplayOp {
    let x: CGFloat = object.x + offset
    return .line(
        Point(x: x, y: object.y),
        Point(x: x, y: object.y + object.height),
        BrowserColor(cssName: "red"),
        1
    )
}
