import Foundation

final class AncestorSelectorKeys {
    private var counts: [SelectorKey: Int] = [:]

    @MainActor
    @discardableResult
    func push(_ element: ElementRef) -> [SelectorKey] {
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

    @MainActor
    private func selectorKeys(of element: ElementRef) -> [SelectorKey] {
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
