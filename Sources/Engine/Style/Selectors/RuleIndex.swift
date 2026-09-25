import Foundation

struct RuleIndex {
    typealias Rule = (String?, any CSSSelector, [String: String])

    let rules: [Rule]
    private let byTag: [String: [Int]]
    private let byClass: [String: [Int]]
    private let byID: [String: [Int]]
    private let universal: [Int]
    var universalCount: Int { universal.count }
    private let descendantRequirements: [Int: Set<SelectorBucketKey>]

    init(rules: [Rule]) {
        self.rules = rules
        var byTag: [String: [Int]] = [:]
        var byClass: [String: [Int]] = [:]
        var byID: [String: [Int]] = [:]
        var universal: [Int] = []
        var descendantRequirements: [Int: Set<SelectorBucketKey>] = [:]
        for (index, rule) in rules.enumerated() {
            let requirements: Set<SelectorBucketKey> = ancestorRequirements(rule.1)
            if !requirements.isEmpty { descendantRequirements[index] = requirements }
            switch rule.1.bucketKey {
                case .tag(let tag):
                    byTag[tag, default: []].append(index)
                case .className(let cls):
                    byClass[cls, default: []].append(index)
                case .id(let id):
                    byID[id, default: []].append(index)
                case .universal:
                    universal.append(index)
            }
        }
        self.byTag = byTag
        self.byClass = byClass
        self.byID = byID
        self.universal = universal
        self.descendantRequirements = descendantRequirements
    }

    func candidateFlags(for element: Element, ancestors: AncestorScope) -> [Bool] {
        var flags: [Bool] = [Bool](repeating: false, count: rules.count)
        for index in universal where requirementsMet(index, ancestors) { flags[index] = true }
        for index in byTag[element.tag] ?? [] where requirementsMet(index, ancestors) {
            flags[index] = true
        }
        if let id = element.attributes["id"] {
            for index in byID[id] ?? [] where requirementsMet(index, ancestors) {
                flags[index] = true
            }
        }
        let classes: [Substring] = element.attributes["class"]?.split(separator: " ") ?? []
        for cls in classes {
            for index in byClass[String(cls)] ?? [] where requirementsMet(index, ancestors) {
                flags[index] = true
            }
        }
        return flags
    }

    private func requirementsMet(_ index: Int, _ ancestors: AncestorScope) -> Bool {
        guard let required = descendantRequirements[index] else { return true }
        for key in required where !ancestors.contains(key) { return false }
        return true
    }
}

private func ancestorRequirements(_ selector: any CSSSelector) -> Set<SelectorBucketKey> {
    if let descendant = selector as? DescendantSelector {
        return descendant.selectors.dropLast().reduce(into: []) {
            $0.formUnion(necessaryKeys($1))
        }
    }
    if let important = selector as? ImportantSelector {
        return ancestorRequirements(important.base)
    }
    return []
}

private func necessaryKeys(_ selector: any CSSSelector) -> Set<SelectorBucketKey> {
    switch selector {
        case let tag as TagSelector: return [.tag(tag.tag)]
        case let cls as ClassSelector: return [.className(cls.cls)]
        case let id as IDSelector: return [.id(id.id)]
        case let seq as SelectorSequence:
            return seq.selectors.reduce(into: [], { $0.formUnion(necessaryKeys($1)) })
        case let pseudoclass as PseudoclassSelector: return necessaryKeys(pseudoclass.base)
        case let important as ImportantSelector: return necessaryKeys(important.base)
        default: return []
    }
}
