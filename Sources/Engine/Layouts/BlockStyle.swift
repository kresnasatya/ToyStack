import CoreGraphics

// MARK: - BlockStyle

@MainActor
struct BlockStyle {
    let display: String
    let position: String
    let box: BlockBoxStyle
    let flags: BlockStyleFlags

    init(node: any DOMNode) {
        let style: StyleFields = node.style
        self.display = style["display"] ?? "inline"
        self.position = style["position"] ?? "static"
        self.box = BlockBoxStyle(
            width: BlockStyle.px(style["width"]),
            height: BlockStyle.px(style["height"]),
            padding: EdgeInsets(
                top: max(0, BlockStyle.px(style["padding-top"]) ?? 0),
                right: max(0, BlockStyle.px(style["padding-right"]) ?? 0),
                bottom: max(0, BlockStyle.px(style["padding-bottom"]) ?? 0),
                left: max(0, BlockStyle.px(style["padding-left"]) ?? 0),
            ),
            margin: EdgeInsets(
                top: BlockStyle.px(style["margin-top"]) ?? 0,
                right: BlockStyle.px(style["margin-right"]) ?? 0,
                bottom: BlockStyle.px(style["margin-bottom"]) ?? 0,
                left: BlockStyle.px(style["margin-left"]) ?? 0,
            )
        )
        self.flags = BlockStyleFlags(
            left: BlockStyle.px(style["left"]),
            top: BlockStyle.px(style["top"]),
            overflowScroll: style["overflow"] == "scroll",
            directionRTL: style["direction"] == "rtl"
        )
    }

    private static func px(_ raw: String?) -> CGFloat? {
        guard let raw, raw.hasSuffix("px"),
            let value = Double(raw.dropLast(2))
        else { return nil }
        return CGFloat(value)
    }
}

// MARK: - BlockBoxStyle

@MainActor
struct BlockBoxStyle {
    let width: CGFloat?
    let height: CGFloat?
    let padding: EdgeInsets
    let margin: EdgeInsets
}

// MARK: - BlockStyleFlags

@MainActor
struct BlockStyleFlags {
    let left: CGFloat?
    let top: CGFloat?
    let overflowScroll: Bool
    let directionRTL: Bool
}

// MARK: - EdgeInsets

@MainActor
struct EdgeInsets {
    let top: CGFloat
    let right: CGFloat
    let bottom: CGFloat
    let left: CGFloat
}
