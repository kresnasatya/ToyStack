import Foundation

/// A viewport pass only re-evaluates rules whose media query flipped. Matching
/// every rule against every node is quadratic, so rules are bucketed by the key
/// their selector ends with; a node tests only rules for its own tag, id,
/// classes, and the universal bucket.
struct ScopedStyleMatcher {
    private static let indexedThreshold: Int = 8

    private let selectors: [any CSSSelector]
    private let buckets: Buckets?

    init(selectors: [any CSSSelector]) {
        self.selectors = selectors
        guard selectors.count > Self.indexedThreshold else {
            self.buckets = nil
            return
        }
        var universal: [Int] = []
        var byTag: [String: [Int]] = [:]
        var byClass: [String: [Int]] = [:]
        var byID: [String: [Int]] = [:]
        for (index, selector) in selectors.enumerated() {
            switch selector.key {
            case .tag(let tag):
                byTag[tag, default: []].append(index)
            case .className(let name):
                byClass[name, default: []].append(index)
            case .id(let id):
                byID[id, default: []].append(index)
            case .universal:
                universal.append(index)
            }
        }
        self.buckets = Buckets(
            universal: universal,
            byTag: byTag,
            byClass: byClass,
            byID: byID
        )
    }

    func directMatches(in snapshot: StyleSnapshot) -> Set<NodeID> {
        var matches: Set<NodeID> = []
        collect(from: snapshot.root, snapshot: snapshot, into: &matches)
        return matches
    }

    private func collect(
        from index: Int,
        snapshot: StyleSnapshot,
        into matches: inout Set<NodeID>
    ) {
        guard let node: StyleNode = snapshot.nodes[index] else { return }
        if node.content.tag != nil,
            matchesAny(content: node.content, snapshot: snapshot, index: index)
        {
            matches.insert(node.identity.id)
        }
        for child in node.identity.children {
            collect(from: child, snapshot: snapshot, into: &matches)
        }
    }

    private func matchesAny(
        content: StyleContent,
        snapshot: StyleSnapshot,
        index: Int
    ) -> Bool {
        guard let buckets: Buckets = buckets else {
            for selector in selectors where selector.matches(snapshot, index) {
                return true
            }
            return false
        }
        return matchesIndexed(
            content: content,
            snapshot: snapshot,
            index: index,
            buckets: buckets
        )
    }

    private func matchesIndexed(
        content: StyleContent,
        snapshot: StyleSnapshot,
        index: Int,
        buckets: Buckets
    ) -> Bool {
        for ruleIndex in buckets.universal
        where selectors[ruleIndex].matches(snapshot, index) {
            return true
        }
        if let tag: String = content.tag {
            for ruleIndex in buckets.byTag[tag] ?? []
            where selectors[ruleIndex].matches(snapshot, index) {
                return true
            }
        }
        if let id: String = content.attributes["id"] {
            for ruleIndex in buckets.byID[id] ?? []
            where selectors[ruleIndex].matches(snapshot, index) {
                return true
            }
        }
        let classes: [Substring] = content.attributes["class"]?.split(separator: " ") ?? []
        for name in classes {
            for ruleIndex in buckets.byClass[String(name)] ?? []
            where selectors[ruleIndex].matches(snapshot, index) {
                return true
            }
        }
        return false
    }
}

// MARK: - Buckets

private struct Buckets {
    let universal: [Int]
    let byTag: [String: [Int]]
    let byClass: [String: [Int]]
    let byID: [String: [Int]]
}
