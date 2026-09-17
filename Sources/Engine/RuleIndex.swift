import Foundation

struct RuleIndex {
    typealias Rule = (String?, any CSSSelector, [String: String])

    let rules: [Rule]
    private let byTag: [String: [Int]]
    private let byClass: [String: [Int]]
    private let byID: [String: [Int]]
    private let universal: [Int]

    init(rules: [Rule]) {
        self.rules = rules
        var byTag: [String: [Int]] = [:]
        var byClass: [String: [Int]] = [:]
        var byID: [String: [Int]] = [:]
        var universal: [Int] = []
        for (index, rule) in rules.enumerated() {
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
    }

    func candidateFlags(for element: Element) -> [Bool] {
        var flags: [Bool] = [Bool](repeating: false, count: rules.count)
        for index in universal { flags[index] = true }
        for index in byTag[element.tag] ?? [] { flags[index] = true }
        if let id = element.attributes["id"] {
            for index in byID[id] ?? [] { flags[index] = true }
        }
        let classes: [Substring] = element.attributes["class"]?.split(separator: " ") ?? []
        for cls in classes {
            for index in byClass[String(cls)] ?? [] { flags[index] = true }
        }
        return flags
    }
}
