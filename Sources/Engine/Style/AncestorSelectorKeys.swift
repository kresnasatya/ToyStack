import Foundation

final class AncestorSelectorKeys {
    private var counts: [SelectorKey: Int] = [:]

    @discardableResult
    func push(_ snapshot: StyleSnapshot, _ index: Int) -> [SelectorKey] {
        let keys: [SelectorKey] = selectorKeys(of: snapshot, at: index)
        for key in keys { counts[key, default: 0] += 1 }
        return keys
    }

    func pop(_ keys: [SelectorKey]) {
        for key in keys {
            guard let count = counts[key] else { continue }
            if count <= 1 { counts[key] = nil } else { counts[key] = count - 1 }
        }
    }

    func contains(_ key: SelectorKey) -> Bool {
        counts[key] != nil
    }

    private func selectorKeys(of snapshot: StyleSnapshot, at index: Int) -> [SelectorKey] {
        let content: StyleContent = snapshot.node(index).content
        guard let tag = content.tag else { return [] }
        var keys: [SelectorKey] = [.tag(tag)]
        if let id = content.attributes["id"] { keys.append(.id(id)) }
        if let cls = content.attributes["class"] {
            for name in cls.split(separator: " ") {
                keys.append(.className(String(name)))
            }
        }
        return keys
    }
}
