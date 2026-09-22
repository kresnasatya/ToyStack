import CoreGraphics

public class VisualEffect: DisplayItem {
    public var rect: Rect
    var children: [any DisplayItem]
    weak var node: DOMNode?
    var needsCompositing: Bool
    weak var parent: VisualEffect?

    init(rect: Rect, children: [any DisplayItem], node: DOMNode? = nil) {
        self.rect = rect
        self.children = children
        self.node = node
        self.needsCompositing = children.compactMap({
            $0 as? VisualEffect
        })
        .contains(where: {
            $0.needsCompositing
        })
    }

    public func execute(renderer: any Renderer) {}

    func map(rect: Rect) -> Rect { return rect }

    func unmap(rect: Rect) -> Rect { return rect }
}

func paintVisualEffects(node: DOMNode, items: [any DisplayItem], rect: Rect) -> [any DisplayItem] {
    let opacity: Double = Double(node.style["opacity"] ?? "1.0") ?? 1.0
    let blendModeStr: String? = node.style["mix-blend-mode"]
    let translation: CGPoint? = parseTransform(node.style["transform"] ?? "")
    let radiusStr: String = (node.style["border-radius"] ?? "0px").replacingOccurrences(of: "px", with: "")
    let borderRadius: CGFloat = CGFloat(Double(radiusStr) ?? 0)
    let blurRadius: CGFloat = parseBlur(node.style["filter"] ?? "")

    let blendMode: BrowserBlendMode? = {
        switch blendModeStr {
        case "multiply": return .multiply
        case "difference": return .difference
        case "destination-in": return .destinationIn
        default: return nil
        }
    }()
    let animated: Bool = node.animations["transform"] != nil || node.animations["opacity"] != nil
    guard borderRadius > 0 || blurRadius > 0 || opacity < 1
        || (blendMode != nil && blendMode != .normal)
        || translation != nil || animated
    else { return items }

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

func addParentPointers(_ items: inout [any DisplayItem], parent: VisualEffect? = nil) {
    var visited: Set<ObjectIdentifier> = Set<ObjectIdentifier>()
    var stack: [([any DisplayItem], VisualEffect?)] = [(items, parent)]

    while !stack.isEmpty {
        let (currentNodes, currentParent) = stack.removeLast()
        for node in currentNodes {
            if let ve = node as? VisualEffect {
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
