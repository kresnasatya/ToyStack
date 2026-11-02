import CoreGraphics

// MARK: - BlockStyle

@MainActor
struct BlockStyle {
    let display: LayoutStyle.Display
    let position: LayoutStyle.Position
    let box: BlockBoxStyle
    let flags: BlockStyleFlags

    init(node: any DOMNode) {
        let style: ComputedStyle = node.style.computed
        self.display = style.layout.display
        self.position = style.layout.position.kind
        self.box = BlockBoxStyle(
            width: style.box.size.width,
            height: style.box.size.height,
            padding: EdgeInsets(
                top: max(0, style.box.spacing.padding.top),
                right: max(0, style.box.spacing.padding.right),
                bottom: max(0, style.box.spacing.padding.bottom),
                left: max(0, style.box.spacing.padding.left)
            ),
            margin: style.box.spacing.margin
        )
        self.flags = BlockStyleFlags(
            left: style.layout.position.left,
            top: style.layout.position.top,
            overflowScroll: style.layout.overflow == .scroll,
            directionRTL: style.text.direction == .rtl
        )
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

struct EdgeInsets: Equatable {
    let top: CGFloat
    let right: CGFloat
    let bottom: CGFloat
    let left: CGFloat
}
