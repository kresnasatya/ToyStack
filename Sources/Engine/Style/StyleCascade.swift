import Foundation

// MARK: - StyleScope

struct StyleScope {
    let direct: Set<ObjectIdentifier>

    var isEmpty: Bool { direct.isEmpty }

    func matches(_ node: any DOMNode) -> Bool {
        direct.contains(ObjectIdentifier(node))
    }
}

// MARK: - StyleCascade

@MainActor
final class StyleCascade {
    let index: RuleIndex
    let media: MediaFeatures
    let scope: StyleScope?
    let ancestorKeys: AncestorSelectorKeys = AncestorSelectorKeys()
    private var oldStyles: [ObjectIdentifier: [String: String]] = [:]
    private(set) var appliedNodes: [any DOMNode] = []

    init(
        index: RuleIndex,
        media: MediaFeatures,
        scope: StyleScope?
    ) {
        self.index = index
        self.media = media
        self.scope = scope
    }

    func record(_ node: any DOMNode) {
        appliedNodes.append(node)
        oldStyles[ObjectIdentifier(node)] = node.style.snapshot()
    }

    func oldStyle(for node: any DOMNode) -> [String: String] {
        return oldStyles[ObjectIdentifier(node)] ?? [:]
    }

    func inheritedChanged(_ node: any DOMNode) -> Bool {
        guard let old: [String: String] = oldStyles[ObjectIdentifier(node)] else {
            return true
        }
        for property in inheritedPropertyDefaults.keys {
            if old[property] != node.style[property] { return true }
        }
        return false
    }
}
