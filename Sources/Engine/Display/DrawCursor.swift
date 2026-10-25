import CoreGraphics

@MainActor
func drawCursor(_ object: any LayoutObject, offset: CGFloat) -> DrawLine {
    let x: CGFloat = object.x + offset
    return DrawLine(
        from: Point(x: x, y: object.y),
        to: Point(x: x, y: object.y + object.height),
        color: "red",
        thickness: 1
    )
}
