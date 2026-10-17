import CoreGraphics

public class BrowserVisualEffect: DisplayItem {
    public var rect: Rect
    var children: [any DisplayItem]
    weak var node: DOMNode?
    var needsCompositing: Bool
    weak var parent: BrowserVisualEffect?

    init(rect: Rect, children: [any DisplayItem], node: DOMNode? = nil) {
        self.rect = rect
        self.children = children
        self.node = node
        self.needsCompositing = children.compactMap({
            $0 as? BrowserVisualEffect
        })
        .contains(where: {
            $0.needsCompositing
        })
    }

    public func execute(renderer: any Renderer) {}

    func map(rect: Rect) -> Rect { return rect }

    func unmap(rect: Rect) -> Rect { return rect }

    func clone(children: [any DisplayItem]) -> BrowserVisualEffect {
        fatalError("\(type(of: self)) must be implement clone(children:)")
    }
}

func paintBrowserVisualEffects(node: DOMNode, items: [any DisplayItem], rect: Rect) -> [any DisplayItem] {
    guard let style: PaintEffectStyle = paintEffectStyle(node: node) else { return items }
    let opacity: Double = style.opacity
    let blendMode: BrowserBlendMode? = style.blendMode
    let translation: CGPoint? = style.translation
    let borderRadius: CGFloat = style.borderRadius
    let blurRadius: CGFloat = style.blurRadius

    var displayItems: [any DisplayItem] = items
    if borderRadius > 0 {
        let clip: Blend = Blend(
            opacity: 1.0, blendMode: .normal, node: node,
            children: [
                DrawRRect(rect: rect, parentEffect: nil, radius: borderRadius, color: "transparent")
            ])
        displayItems = [clip] + displayItems
    }

    if blurRadius > 0 {
        displayItems = [BlurFilter(radius: blurRadius, node: node, children: displayItems)]
    }

    let blend: Blend = Blend(opacity: opacity, blendMode: blendMode, node: node, children: displayItems)
    let transform: Transform = Transform(translation: translation, rect: rect, node: node, children: [blend])
    return [transform]
}

func addParentPointers(_ items: inout [any DisplayItem], parent: BrowserVisualEffect? = nil) {
    var visited: Set<ObjectIdentifier> = Set<ObjectIdentifier>()
    var stack: [([any DisplayItem], BrowserVisualEffect?)] = [(items, parent)]

    while !stack.isEmpty {
        let (currentNodes, currentParent) = stack.removeLast()
        for node in currentNodes {
            if let ve = node as? BrowserVisualEffect {
                let id: ObjectIdentifier = ObjectIdentifier(ve)
                guard !visited.contains(id) else { continue }
                visited.insert(id)
                ve.parent = currentParent
                for i in 0..<ve.children.count {
                    if var pc = ve.children[i] as? (any DisplayCommand) {
                        pc.parentEffect = ve
                        ve.children[i] = pc
                    }
                }
                stack.append((ve.children, ve))
            }
        }
    }
}

func maxRectBottom(_ items: [any DisplayItem]) -> CGFloat {
    var result: CGFloat = 0
    for item in items {
        if let cmd = item as? any DisplayCommand {
            result = max(result, cmd.rect.bottom)
        } else if let ve = item as? BrowserVisualEffect {
            result = max(result, ve.rect.bottom)
            if ve is Clip || ve is ScrollEffect {
                continue
            }
            result = max(result, maxRectBottom(ve.children))
        }
    }
    return result
}
