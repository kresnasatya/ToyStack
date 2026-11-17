import Foundation

enum TopLevelDomains {
    private static let names: Set<String> = load()

    static func contains(_ label: String) -> Bool {
        names.contains(label)
    }

    private static func load() -> Set<String> {
        guard let url: URL = EngineResources.bundle.url(forResource: "tlds-alpha-by-domain", withExtension: "txt"),
            let text: String = try? String(contentsOf: url, encoding: .utf8)
        else {
            return []
        }
        var names: Set<String> = []
        for line: Substring in text.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            names.insert(line.lowercased())
        }
        return names
    }
}
