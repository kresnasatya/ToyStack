// MARK: - SelectionHighlight

/// Over a white page this blends to #B3D7FF, the light blue macOS puts behind
/// selected text; being see-through, it stays visible on dark pages too.
let selectionHighlightColor: BrowserColor = BrowserColor(red: 0, green: 0.478, blue: 1, alpha: 0.3)

func selectionHighlightOps(_ rects: [Rect]) -> [DisplayOp] {
    return rects.map({ DisplayOp.rect(rect: $0, color: selectionHighlightColor) })
}
