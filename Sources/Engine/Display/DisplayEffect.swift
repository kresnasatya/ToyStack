import CoreGraphics

public struct DisplayEffect {
    var scope: EffectScope
    var children: [DisplayOp]

    var rect: Rect { scope.placement.rect }

    var name: String {
        switch scope.kind {
        case .blend: return "blend"
        case .blur: return "blur"
        case .clip: return "clip"
        case .transform: return "transform"
        case .scroll: return "scroll"
        }
    }

    func execute(renderer: any Renderer) {
        applyEffect(scope.kind, renderer: renderer) { inner in
            for child in children {
                child.execute(renderer: inner)
            }
        }
    }
}

// MARK: - Paint wrapping

@MainActor
func paintBrowserVisualEffects(
    style: PaintEffectStyle,
    node: DOMNode,
    items: [DisplayOp],
    rect: Rect,
    session: inout PaintSession
) -> [DisplayOp] {
    var displayItems: [DisplayOp] = items
    if style.blurRadius > 0 {
        let scope: EffectScope = session.makeScope(
            .blur(radius: style.blurRadius),
            node: NodeKey(node),
            animatedTransform: false
        ).placed(rect: bounds(of: displayItems))
        displayItems = [.effect(DisplayEffect(scope: scope, children: displayItems))]
    }

    let blendScope: EffectScope = session.makeScope(
        .blend(opacity: style.opacity, mode: style.blendMode),
        node: NodeKey(node),
        animatedTransform: false
    ).placed(rect: bounds(of: displayItems))
    let blend: DisplayEffect = DisplayEffect(scope: blendScope, children: displayItems)

    let transformScope: EffectScope = session.makeScope(
        .transform(style.translation),
        node: NodeKey(node),
        animatedTransform: node.animations["transform"] != nil
    ).placed(rect: rect)
    let transform: DisplayEffect = DisplayEffect(scope: transformScope, children: [.effect(blend)])

    return [.effect(transform)]
}

@MainActor
func paintBrowserVisualEffects(
    node: DOMNode,
    items: [DisplayOp],
    rect: Rect,
    session: inout PaintSession
) -> [DisplayOp] {
    guard let style: PaintEffectStyle = paintEffectStyle(node: node) else { return items }
    return paintBrowserVisualEffects(
        style: style,
        node: node,
        items: items,
        rect: rect,
        session: &session
    )
}

private func bounds(of items: [DisplayOp]) -> Rect {
    var result: Rect = Rect(left: 0, top: 0, right: 0, bottom: 0)
    for item in items {
        result = result.union(item.rect)
    }
    return result
}
