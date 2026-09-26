import Foundation

final class AncestorScope {
    private var counts: [SelectorKey: Int] = [:]

    @discardableResult
    func push(_ element: Element) -> [SelectorKey] {
        let keys: [SelectorKey] = selectorKeys(of: element)
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

    private func selectorKeys(of element: Element) -> [SelectorKey] {
        var keys: [SelectorKey] = [.tag(element.tag)]
        if let id = element.attributes["id"] { keys.append(.id(id)) }
        if let cls = element.attributes["class"] {
            for name in cls.split(separator: " ") {
                keys.append(.className(String(name)))
            }
        }
        return keys
    }
}
