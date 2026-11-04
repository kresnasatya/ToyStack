import Foundation

// MARK: - StyleScope

struct StyleScope {
    let direct: Set<NodeID>

    var isEmpty: Bool { direct.isEmpty }

    func matches(_ node: DOMRef) -> Bool {
        direct.contains(node.id)
    }
}

// MARK: - StyleCascade

@MainActor
final class StyleCascade {
    let index: RuleIndex
    let media: MediaFeatures
    let scope: StyleScope?
    let ancestorKeys: AncestorSelectorKeys = AncestorSelectorKeys()
    private var oldStyles: [NodeID: ComputedStyle] = [:]
    private(set) var appliedNodes: [DOMRef] = []

    init(
        index: RuleIndex,
        media: MediaFeatures,
        scope: StyleScope?
    ) {
        self.index = index
        self.media = media
        self.scope = scope
    }

    func record(_ node: DOMRef) {
        record(node, old: node.style.computed)
    }

    func record(_ node: DOMRef, old: ComputedStyle) {
        appliedNodes.append(node)
        oldStyles[node.id] = old
    }

    func oldStyle(for node: DOMRef) -> ComputedStyle? {
        return oldStyles[node.id]
    }

    func inheritedChanged(_ node: DOMRef) -> Bool {
        guard let old: ComputedStyle = oldStyles[node.id] else {
            return true
        }
        return StyleProperty.inherited.contains {
            !old.matches(node.style.computed, for: $0)
        }
    }
}
