import CoreGraphics

// MARK: - Own paint

func emit(_ node: PaintNode, into items: inout [DisplayOp]) {
    switch node.content {
    case .document:
        break
    case .block(let block):
        emitBlock(node, block: block, into: &items)
    case .line(let line):
        items.append(contentsOf: line.focusRing)
        for text in line.inlineText {
            items.append(.text(
                text: text.string,
                font: text.font,
                color: text.color,
                rect: text.rect
            ))
        }
    case .text(let text):
        emitText(node, text: text, into: &items)
    case .embed(let embed):
        emitEmbed(node, embed: embed, into: &items)
    }
}

func emitBlock(_ node: PaintNode, block: PaintBlock, into items: inout [DisplayOp]) {
    let style: ComputedStyle = node.surface.style
    let box: Rect = node.geometry.rect
    let background: BrowserColor? = style.visual.background.color
    if background != nil || style.layout.overflow == .scroll {
        let radii: CornerRadii = style.box.decoration.border.radii
        let color: BrowserColor = background ?? BrowserColor(red: 0, green: 0, blue: 0, alpha: 0)
        if !radii.isZero {
            items.append(.rrect(rect: box, radii: radii, color: color))
        } else {
            items.append(.rect(rect: box, color: color))
        }
    }

    if let image: CGImage = block.extras.backgroundImage, style.visual.background.image != nil {
        let dest: Rect = BackgroundSize(box: box, image: image, zoom: node.geometry.zoom)
            .rect(spec: style.visual.background.size)
        items.append(.clippedImage(
            image: image,
            rendering: style.visual.image.rendering,
            rect: dest,
            clip: box
        ))
    }

    if let border: DisplayOp = DisplayOp.fromBorderStyle(style, rect: borderRect(box, style)) {
        items.append(border)
    }

    let outline: DisplayOp? = DisplayOp.fromStyle(style, rect: box)
    if node.surface.state.isFocusVisible && outline == nil {
        let ring: (outer: String, inner: String) = focusRingColors(
            forcedColors: node.surface.state.forcedColors
        )
        items.append(.outline(rect: box, color: BrowserColor(cssName: ring.outer), width: 4))
        items.append(.outline(rect: box, color: BrowserColor(cssName: ring.inner), width: 2))
    }
    if let outline { items.append(outline) }

    if block.isListItem {
        let bulletX: CGFloat = node.geometry.frame.left - liIndent
        let bulletY: CGFloat = node.geometry.frame.top + (VSTEP - bulletSize) / 2
        items.append(.rect(
            rect: Rect(
                left: bulletX,
                top: bulletY,
                right: bulletX + bulletSize,
                bottom: bulletY + bulletSize
            ),
            color: BrowserColor(
                cssName: node.surface.state.forcedColors ? ForcedColor.canvasText : "black"
            )
        ))
    }
}

func emitText(_ node: PaintNode, text: PaintText, into items: inout [DisplayOp]) {
    items.append(.text(
        text: text.string,
        font: node.surface.font,
        color: text.color,
        rect: Rect(
            left: node.geometry.frame.left,
            top: text.top,
            right: node.geometry.frame.left + text.width,
            bottom: text.top + node.surface.font.linespace
        )
    ))
}

// MARK: - Embeds

func emitEmbed(_ node: PaintNode, embed: PaintEmbed, into items: inout [DisplayOp]) {
    switch embed {
    case .image(let image):
        emitImage(node, image: image, into: &items)
    case .input(let input):
        emitInput(node, input: input, into: &items)
    case .button:
        emitButton(node, into: &items)
    case .iframe:
        emitIframe(node, into: &items)
    case .canvas(let canvas):
        emitCanvas(node, canvas: canvas, into: &items)
    }
}

func emitImage(_ node: PaintNode, image: PaintImage, into items: inout [DisplayOp]) {
    guard let cgImage: CGImage = image.image else { return }
    let frame: Rect = node.geometry.frame
    let box: Rect = Rect(
        left: frame.left,
        top: frame.top + (frame.bottom - frame.top) - image.height,
        right: frame.right,
        bottom: frame.bottom
    )
    let style: ComputedStyle = node.surface.style
    let content: Rect = ObjectFit(
        box: box,
        intrinsicWidth: CGFloat(cgImage.width) * node.geometry.zoom,
        intrinsicHeight: CGFloat(cgImage.height) * node.geometry.zoom,
        fit: style.visual.image.fit
    ).contentRect
    items.append(.clippedImage(
        image: cgImage,
        rendering: style.visual.image.rendering,
        rect: content,
        clip: box
    ))
}

func emitInput(_ node: PaintNode, input: PaintInput, into items: inout [DisplayOp]) {
    let style: ComputedStyle = node.surface.style
    let rect: Rect = node.geometry.rect
    let forced: Bool = node.surface.state.forcedColors

    if let bgcolor: BrowserColor = style.visual.background.color {
        let radii: CornerRadii = style.box.decoration.border.radii
        if !radii.isZero {
            items.append(.rrect(rect: rect, radii: radii, color: bgcolor))
        } else {
            items.append(.rect(rect: rect, color: bgcolor))
        }
    }

    if input.isCheckbox {
        items.append(.rect(
            rect: rect,
            color: BrowserColor(cssName: forced ? ForcedColor.buttonFace : "white")
        ))
        items.append(.outline(
            rect: rect,
            color: BrowserColor(cssName: forced ? ForcedColor.buttonBorder : "black"),
            width: 1
        ))
        if input.isChecked {
            let font: BrowserFont = node.surface.font
            let x: CGFloat = node.geometry.frame.left
            let y: CGFloat = node.geometry.frame.top
            items.append(.text(
                text: "X",
                font: font,
                color: BrowserColor(cssName: forced ? ForcedColor.buttonText : "black"),
                rect: Rect(
                    left: x,
                    top: y,
                    right: x + font.measure("X"),
                    bottom: y + font.linespace
                )
            ))
        }
        emitFocusOutline(node, coercedWidths: (2, 4), into: &items)
    }

    let font: BrowserFont = node.surface.font
    let x: CGFloat = node.geometry.frame.left
    let y: CGFloat = node.geometry.frame.top
    items.append(.text(
        text: input.text,
        font: font,
        color: style.text.color,
        rect: Rect(
            left: x,
            top: y,
            right: x + font.measure(input.text),
            bottom: y + font.linespace
        )
    ))

    if node.surface.state.isFocused {
        items.append(drawCursor(
            origin: Point(x: x, y: y),
            height: node.geometry.frame.bottom - y,
            offset: font.measure(input.text)
        ))
    }
    emitFocusOutline(node, coercedWidths: (4, 2), into: &items)
}

func emitButton(_ node: PaintNode, into items: inout [DisplayOp]) {
    let style: ComputedStyle = node.surface.style
    let rect: Rect = node.geometry.rect
    let forced: Bool = node.surface.state.forcedColors
    let displayColor: BrowserColor = style.visual.background.color
        ?? BrowserColor(cssName: forced ? ForcedColor.buttonFace : "white")
    items.append(.rect(rect: rect, color: displayColor))
    items.append(.outline(
        rect: rect,
        color: BrowserColor(cssName: forced ? ForcedColor.buttonBorder : "black"),
        width: 1
    ))
    emitFocusOutline(node, coercedWidths: (4, 2), into: &items)
}

func emitIframe(_ node: PaintNode, into items: inout [DisplayOp]) {
    let style: ComputedStyle = node.surface.style
    guard let bgColor: BrowserColor = style.visual.background.color else { return }
    items.append(.rrect(
        rect: node.geometry.rect,
        radii: style.box.decoration.border.radii,
        color: bgColor
    ))
}

func emitCanvas(_ node: PaintNode, canvas: PaintCanvas, into items: inout [DisplayOp]) {
    guard let image: CGImage = canvas.image else { return }
    items.append(.image(
        image: image,
        rendering: .auto,
        rect: node.geometry.rect,
        version: canvas.revision
    ))
}

func emitFocusOutline(
    _ node: PaintNode,
    coercedWidths: (outer: CGFloat, inner: CGFloat),
    into items: inout [DisplayOp]
) {
    let rect: Rect = node.geometry.rect
    let outline: DisplayOp? = DisplayOp.fromStyle(node.surface.style, rect: rect)
    if node.surface.state.isFocusVisible && outline == nil {
        let ring: (outer: String, inner: String) = focusRingColors(
            forcedColors: node.surface.state.forcedColors
        )
        items.append(.outline(
            rect: rect,
            color: BrowserColor(cssName: ring.outer),
            width: coercedWidths.outer
        ))
        items.append(.outline(
            rect: rect,
            color: BrowserColor(cssName: ring.inner),
            width: coercedWidths.inner
        ))
    }
    if let outline { items.append(outline) }
}

// MARK: - Geometry

func borderRect(_ box: Rect, _ style: ComputedStyle) -> Rect {
    let width: CGFloat = style.box.decoration.border.width
    guard width > 0 else { return box }
    let half: CGFloat = width / 2
    return Rect(
        left: box.left - half,
        top: box.top - half,
        right: box.right + half,
        bottom: box.bottom + half
    )
}

// MARK: - Node scopes

func openScopes(
    _ node: PaintNode,
    into ops: inout [DisplayOp],
    session: inout PaintSession
) -> [OpenScope] {
    var opened: [OpenScope] = []
    for kind in scopeKinds(node) {
        let scope: EffectScope = session.makeScope(
            kind,
            node: node.links.dom,
            animatedTransform: node.surface.effects.animatedTransform
        )
        opened.append(OpenScope(index: ops.count, scope: scope))
        ops.append(.beginEffect(scope))
    }
    return opened
}

func scopeKinds(_ node: PaintNode) -> [EffectKind] {
    if case .line = node.content { return [] }
    guard let style: PaintEffectStyle = node.surface.effects.style else { return [] }
    var kinds: [EffectKind] = [.transform(style.translation)]
    kinds.append(.blend(opacity: style.opacity, mode: style.blendMode))
    if style.blurRadius > 0 {
        kinds.append(.blur(radius: style.blurRadius))
    }
    return kinds
}

func closeScopes(
    _ opened: [OpenScope],
    node: PaintNode,
    ops: inout [DisplayOp]
) {
    for open in opened.reversed() {
        let rect: Rect = scopeRect(open.scope.kind, node: node, ops: ops, from: open.index + 1)
        ops[open.index] = .beginEffect(EffectScope(
            id: open.scope.id,
            kind: open.scope.kind,
            placement: EffectPlacement(
                rect: rect,
                node: open.scope.placement.node,
                animatedTransform: open.scope.placement.animatedTransform
            )
        ))
        ops.append(.endEffect)
    }
}

func scopeRect(_ kind: EffectKind, node: PaintNode, ops: [DisplayOp], from start: Int) -> Rect {
    switch kind {
    case .transform:
        return node.geometry.rect
    case .clip(let shape), .scroll(let shape, _):
        return shape.rect
    case .blend, .blur:
        var rect: Rect = Rect(left: 0, top: 0, right: 0, bottom: 0)
        for index in start..<ops.count {
            switch ops[index] {
            case .beginEffect, .endEffect:
                continue
            default:
                rect = rect.union(ops[index].rect)
            }
        }
        return rect
    }
}

// MARK: - Iframe scopes

func openIframeScopes(
    _ node: PaintNode,
    iframe: PaintIframe,
    into ops: inout [DisplayOp],
    session: inout PaintSession
) -> IframeScopes {
    let rect: Rect = node.geometry.rect
    let scroll: CGFloat = iframe.scroll
    let clipRect: Rect = Rect(
        left: 0,
        top: scroll,
        right: iframe.inner.right - iframe.inner.left,
        bottom: scroll + (iframe.inner.bottom - iframe.inner.top)
    )

    var blendRect: Rect = rect
    if let bar = iframe.bar {
        blendRect = blendRect.union(bar.rect)
    }

    let blend: EffectScope = session.makeScope(
        .blend(opacity: 1.0, mode: .normal),
        node: node.links.dom,
        animatedTransform: false
    ).placed(rect: blendRect)
    ops.append(.beginEffect(blend))

    let transform: EffectScope = session.makeScope(
        .transform(CGPoint(x: iframe.inner.left, y: iframe.inner.top - scroll)),
        node: node.links.dom,
        animatedTransform: false
    ).placed(rect: rect)
    ops.append(.beginEffect(transform))

    let clip: EffectScope = session.makeScope(
        .clip(ClipShape(rect: clipRect, radii: .zero)),
        node: nil,
        animatedTransform: false
    ).placed(rect: iframe.inner)
    ops.append(.beginEffect(clip))

    return IframeScopes(bar: iframe.bar, rect: rect)
}

func closeIframeScopes(
    _ node: PaintNode,
    iframe: PaintIframe,
    scopes: IframeScopes,
    into ops: inout [DisplayOp]
) {
    ops.append(.endEffect)
    ops.append(.endEffect)
    if let bar = scopes.bar {
        ops.append(bar)
    }
    ops.append(.endEffect)

    if let border: DisplayOp = DisplayOp.fromBorderStyle(
        node.surface.style,
        rect: scopes.rect
    ) {
        ops.append(border)
    }
    if let outline: DisplayOp = DisplayOp.fromStyle(node.surface.style, rect: scopes.rect) {
        ops.append(outline)
    }
}
