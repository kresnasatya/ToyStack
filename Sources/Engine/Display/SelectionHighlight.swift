// MARK: - SelectionHighlight

let selectionHighlightColor: BrowserColor = BrowserColor(red: 0, green: 0.478, blue: 1, alpha: 0.3)

func selectionHighlightOps(_ rects: [Rect]) -> [DisplayOp] {
    return rects.map({ DisplayOp.rect(rect: $0, color: selectionHighlightColor) })
}
